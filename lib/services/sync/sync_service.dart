import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/db/database.dart';

enum SyncState { offline, syncing, synced, error }

/// Keeps the local deck in sync with the user's `decks` row in Supabase.
///
/// Model: the entire deck is stored as one JSON document (the same format as
/// the manual backup) per signed-in user. Changes are pushed (debounced) and
/// pulled (via realtime), reconciled last-write-wins using `updated_at`.
class SyncService extends ChangeNotifier {
  final AppDatabase db;
  SyncService(this.db);

  SupabaseClient get _sb => Supabase.instance.client;

  SyncState _state = SyncState.offline;
  String? _message;
  DateTime? _lastSyncedAt;

  // In-session echo guard: the deck JSON we last pushed/applied. Prevents the
  // realtime echo of our own write (and the table-update from importing) from
  // bouncing back as another sync.
  String? _lastSyncedData;
  bool _applyingRemote = false;

  Timer? _pushDebounce;
  StreamSubscription<dynamic>? _localSub;
  StreamSubscription<AuthState>? _authSub;
  RealtimeChannel? _channel;
  bool _started = false;

  /// One ambiguous case on first sign-in (this device has cards AND the account
  /// already has a cloud deck): returns true to keep the CLOUD deck, false to
  /// upload THIS device's deck. Set by the sync screen before signing in.
  Future<bool> Function(int localCards)? conflictResolver;

  SyncState get state => _state;
  String? get message => _message;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  User? get user {
    try {
      return _sb.auth.currentUser;
    } catch (_) {
      return null; // Supabase not initialized (offline at launch)
    }
  }

  bool get signedIn => user != null;
  String? get email => user?.email;

  void _set(SyncState s, [String? msg]) {
    _state = s;
    _message = msg;
    notifyListeners();
  }

  /// Wire the auth listener. Supabase restores any saved session and emits an
  /// `initialSession` event, which starts syncing automatically on app launch.
  void init() {
    _authSub = _sb.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
          if (signedIn) _start();
          break;
        case AuthChangeEvent.signedOut:
          _stop();
          break;
        default:
          break;
      }
    });
  }

  // --- Auth ---------------------------------------------------------------
  Future<void> signIn(String email, String password) =>
      _sb.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signUp(String email, String password) =>
      _sb.auth.signUp(email: email.trim(), password: password);

  Future<void> signOut() => _sb.auth.signOut();

  // --- Lifecycle ----------------------------------------------------------
  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final uid = user?.id;
    if (uid == null) return;
    _set(SyncState.syncing, 'Syncing…');
    try {
      await _reconcile(uid, interactive: conflictResolver != null);
      conflictResolver = null;
      _listenLocal(uid);
      _subscribeRemote(uid);
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  void _stop() {
    _started = false;
    _pushDebounce?.cancel();
    _localSub?.cancel();
    _localSub = null;
    if (_channel != null) {
      _sb.removeChannel(_channel!);
      _channel = null;
    }
    _lastSyncedData = null;
    _lastSyncedAt = null;
    _set(SyncState.offline);
  }

  // --- Reconcile / push / pull -------------------------------------------
  Future<void> _reconcile(String uid, {required bool interactive}) async {
    final localCount = await db.countCards();
    final row = await _sb
        .from('decks')
        .select('data, updated_at')
        .eq('user_id', uid)
        .maybeSingle();

    if (row == null) {
      await _pushNow(uid, force: true); // seed the cloud from this device
      return;
    }
    final cloudUpdated = DateTime.parse(row['updated_at'] as String).toUtc();
    final cloudData = row['data'] as String;
    final last = await _readLastAt(uid);
    final dirty = await _readDirty(uid);
    final cloudIsNew = last == null || cloudUpdated.isAfter(last);

    // First sign-in on this device with data on BOTH sides → let the user pick.
    if (interactive &&
        last == null &&
        localCount > 0 &&
        conflictResolver != null) {
      final keepCloud = await conflictResolver!(localCount);
      if (keepCloud) {
        await _applyRemote(uid, cloudData, cloudUpdated);
      } else {
        await _pushNow(uid, force: true);
      }
      return;
    }

    if (cloudIsNew && !dirty) {
      await _applyRemote(uid, cloudData, cloudUpdated);
    } else if (!cloudIsNew && dirty) {
      await _pushNow(uid, force: true);
    } else if (cloudIsNew && dirty) {
      // Both sides changed since the last sync. The cloud is the shared source
      // of truth, so it wins (rare for a single user editing one device).
      await _applyRemote(uid, cloudData, cloudUpdated);
    }
    // else: already in sync.
  }

  Future<void> _pushNow(String uid, {bool force = false}) async {
    final json = await db.exportDeck();
    if (!force && json == _lastSyncedData) {
      _set(SyncState.synced);
      return;
    }
    final now = DateTime.now().toUtc();
    await _sb.from('decks').upsert({
      'user_id': uid,
      'data': json,
      'updated_at': now.toIso8601String(),
    });
    _lastSyncedData = json;
    _lastSyncedAt = now;
    await _writeLastAt(uid, now);
    await _writeDirty(uid, false);
    _set(SyncState.synced);
  }

  Future<void> _applyRemote(
      String uid, String dataJson, DateTime cloudUpdated) async {
    if (dataJson == _lastSyncedData) {
      _lastSyncedAt = cloudUpdated;
      await _writeLastAt(uid, cloudUpdated);
      return;
    }
    _applyingRemote = true;
    try {
      await db.importDeck(dataJson);
      _lastSyncedData = dataJson;
      _lastSyncedAt = cloudUpdated;
      await _writeLastAt(uid, cloudUpdated);
      await _writeDirty(uid, false);
    } finally {
      _applyingRemote = false;
    }
  }

  /// Force a pull of the latest cloud deck (used by the manual refresh button).
  Future<void> pullNow() async {
    final uid = user?.id;
    if (uid == null) return;
    _set(SyncState.syncing, 'Checking…');
    try {
      final row = await _sb
          .from('decks')
          .select('data, updated_at')
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        await _applyRemote(uid, row['data'] as String,
            DateTime.parse(row['updated_at'] as String).toUtc());
      }
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  // --- Change listeners ---------------------------------------------------
  void _listenLocal(String uid) {
    _localSub = db.tableUpdates().listen((_) {
      if (_applyingRemote) return;
      _writeDirty(uid, true);
      _schedulePush(uid);
    });
  }

  void _schedulePush(String uid) {
    _set(SyncState.syncing);
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 2), () async {
      try {
        await _pushNow(uid);
      } catch (e) {
        _set(SyncState.error, _friendly(e));
      }
    });
  }

  void _subscribeRemote(String uid) {
    _channel = _sb.channel('decks_$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'decks',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
        callback: (payload) async {
          final rec = payload.newRecord;
          final data = rec['data'];
          final upStr = rec['updated_at'];
          if (data is! String || upStr is! String) return;
          final cloudUpdated = DateTime.parse(upStr).toUtc();
          if (_lastSyncedAt != null && !cloudUpdated.isAfter(_lastSyncedAt!)) {
            return;
          }
          try {
            await _applyRemote(uid, data, cloudUpdated);
            _set(SyncState.synced);
          } catch (e) {
            _set(SyncState.error, _friendly(e));
          }
        },
      )
      ..subscribe();
  }

  // --- Small prefs helpers (namespaced per account) -----------------------
  Future<DateTime?> _readLastAt(String uid) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('sync_last_$uid');
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> _writeLastAt(String uid, DateTime at) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sync_last_$uid', at.toIso8601String());
  }

  Future<bool> _readDirty(String uid) async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('sync_dirty_$uid') ?? false;
  }

  Future<void> _writeDirty(String uid, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sync_dirty_$uid', v);
  }

  String _friendly(Object e) {
    if (e is AuthException) return e.message;
    if (e is PostgrestException) return e.message;
    return 'Sync error: $e';
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stop();
    super.dispose();
  }
}
