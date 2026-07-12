import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/database.dart';
import 'supabase_config.dart';

enum SyncState { offline, syncing, synced, error }

/// Cloud sync over plain HTTP (no Flutter plugins, so it can never run code at
/// app-startup — the whole feature is inert until the user signs in).
///
/// The entire deck is stored as one JSON document (the manual-backup format)
/// per user in the Supabase `decks` table. Changes are pushed (debounced) and
/// pulled (polled every ~15s + on open), reconciled last-write-wins by
/// `updated_at`.
class SyncService extends ChangeNotifier {
  final AppDatabase db;
  final Dio _dio = Dio(BaseOptions(
    baseUrl: SupabaseConfig.url,
    headers: {'apikey': SupabaseConfig.anonKey},
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  ));

  SyncService(this.db);

  // Session (persisted in shared_preferences; no plugin, no startup network).
  String? _access, _refresh, _uid, _email;
  DateTime? _expiresAt;

  SyncState _state = SyncState.offline;
  String? _message;
  DateTime? _lastSyncedAt;
  String? _lastSyncedData; // echo guard
  bool _applyingRemote = false;
  Timer? _pushDebounce;
  Timer? _poll;
  StreamSubscription<dynamic>? _localSub;
  bool _started = false;

  /// First-sign-in resolver (this device has cards AND the cloud already has a
  /// deck): true = keep cloud, false = upload this device. Set by the UI.
  Future<bool> Function(int localCards)? conflictResolver;

  SyncState get state => _state;
  String? get message => _message;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get signedIn => _refresh != null && _uid != null;
  String? get email => _email;

  void _set(SyncState s, [String? m]) {
    _state = s;
    _message = m;
    notifyListeners();
  }

  /// Called once after runApp. Restores any saved session (prefs only, no
  /// network) and starts background sync if signed in. Safe to fail.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _access = p.getString('sb_access');
    _refresh = p.getString('sb_refresh');
    _uid = p.getString('sb_uid');
    _email = p.getString('sb_email');
    final e = p.getInt('sb_exp');
    _expiresAt = e == null ? null : DateTime.fromMillisecondsSinceEpoch(e);
    if (signedIn) await _start();
  }

  // --- Auth --------------------------------------------------------------
  Future<void> signUp(String email, String password) async {
    final r = await _dio.post('/auth/v1/signup',
        data: {'email': email.trim(), 'password': password},
        options: Options(headers: {'Content-Type': 'application/json'}));
    await _saveSession(r.data);
    if (!signedIn) {
      throw 'Account created — if email confirmation is on, confirm it, then sign in.';
    }
    await _afterAuth();
  }

  Future<void> signIn(String email, String password) async {
    final r = await _dio.post('/auth/v1/token?grant_type=password',
        data: {'email': email.trim(), 'password': password},
        options: Options(headers: {'Content-Type': 'application/json'}));
    await _saveSession(r.data);
    await _afterAuth();
  }

  Future<void> signOut() async {
    _stop();
    final p = await SharedPreferences.getInstance();
    for (final k in ['sb_access', 'sb_refresh', 'sb_uid', 'sb_email', 'sb_exp']) {
      await p.remove(k);
    }
    _access = _refresh = _uid = _email = null;
    _expiresAt = null;
    notifyListeners();
  }

  Future<void> _saveSession(dynamic data) async {
    final m = data as Map;
    _access = m['access_token'] as String?;
    _refresh = m['refresh_token'] as String?;
    final user = m['user'] as Map?;
    _uid = (user?['id'] ?? m['id']) as String?;
    _email = (user?['email'] as String?) ?? _email;
    final expIn = m['expires_in'];
    _expiresAt = expIn is int ? DateTime.now().add(Duration(seconds: expIn)) : null;
    final p = await SharedPreferences.getInstance();
    if (_access != null) await p.setString('sb_access', _access!);
    if (_refresh != null) await p.setString('sb_refresh', _refresh!);
    if (_uid != null) await p.setString('sb_uid', _uid!);
    if (_email != null) await p.setString('sb_email', _email!);
    if (_expiresAt != null) {
      await p.setInt('sb_exp', _expiresAt!.millisecondsSinceEpoch);
    }
  }

  Future<void> _afterAuth() async {
    notifyListeners();
    await _start(interactive: true);
  }

  Future<void> _ensureToken() async {
    if (_refresh == null) throw 'Not signed in';
    if (_expiresAt != null &&
        DateTime.now()
            .isBefore(_expiresAt!.subtract(const Duration(seconds: 60)))) {
      return;
    }
    final r = await _dio.post('/auth/v1/token?grant_type=refresh_token',
        data: {'refresh_token': _refresh},
        options: Options(headers: {'Content-Type': 'application/json'}));
    await _saveSession(r.data);
  }

  Map<String, String> get _restHeaders => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer $_access',
        'Content-Type': 'application/json',
      };

  // --- Lifecycle ---------------------------------------------------------
  Future<void> _start({bool interactive = false}) async {
    if (_started) return;
    _started = true;
    _set(SyncState.syncing, 'Syncing…');
    try {
      await _reconcile(interactive: interactive);
      conflictResolver = null;
      _listenLocal();
      _startPolling();
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  void _stop() {
    _started = false;
    _pushDebounce?.cancel();
    _poll?.cancel();
    _localSub?.cancel();
    _localSub = null;
    _lastSyncedData = null;
    _lastSyncedAt = null;
    _set(SyncState.offline);
  }

  // --- Cloud read/write --------------------------------------------------
  Future<({String? data, DateTime? updatedAt})> _fetchCloud() async {
    await _ensureToken();
    final r = await _dio.get('/rest/v1/decks',
        queryParameters: {'select': 'data,updated_at'},
        options: Options(headers: _restHeaders));
    final list = (r.data as List);
    if (list.isEmpty) return (data: null, updatedAt: null);
    final row = list.first as Map;
    return (
      data: row['data'] as String?,
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc()
    );
  }

  /// Cheap poll: only the timestamp, never the (possibly multi-MB) deck body.
  /// The full deck is fetched only when this shows the cloud is newer.
  Future<DateTime?> _fetchCloudMeta() async {
    await _ensureToken();
    final r = await _dio.get('/rest/v1/decks',
        queryParameters: {'select': 'updated_at'},
        options: Options(headers: _restHeaders));
    final list = (r.data as List);
    if (list.isEmpty) return null;
    return DateTime.parse((list.first as Map)['updated_at'] as String).toUtc();
  }

  Future<void> _reconcile({required bool interactive}) async {
    final localCount = await db.countCards();
    final cloud = await _fetchCloud();
    if (cloud.data == null) {
      await _push(force: true); // seed the cloud from this device
      return;
    }
    final last = await _readLastAt();
    final dirty = await _readDirty();
    final cloudIsNew = last == null || cloud.updatedAt!.isAfter(last);

    if (interactive &&
        last == null &&
        localCount > 0 &&
        conflictResolver != null) {
      final keepCloud = await conflictResolver!(localCount);
      if (keepCloud) {
        // User explicitly chose the cloud copy — allow the replace.
        await _applyRemote(cloud.data!, cloud.updatedAt!, force: true);
      } else {
        await _push(force: true);
      }
      return;
    }

    if (cloudIsNew) {
      await _applyRemote(cloud.data!, cloud.updatedAt!);
    } else if (dirty) {
      await _push(force: true);
    }
  }

  /// Number of cards inside a deck JSON document (backup format). Returns -1 if
  /// the document can't be parsed, so callers treat it as "unknown, don't block".
  int _deckCardCount(String data) {
    try {
      final cards = (jsonDecode(data) as Map)['cards'];
      return cards is List ? cards.length : -1;
    } catch (_) {
      return -1;
    }
  }

  /// Number of cards in a deck JSON that carry an image (bytes or URL).
  int _deckImageCount(String data) {
    try {
      final cards = (jsonDecode(data) as Map)['cards'];
      if (cards is! List) return -1;
      return cards.where((c) {
        if (c is! Map) return false;
        final b = c['imageBytes'];
        final u = c['imageUrl'];
        return (b is String && b.isNotEmpty) || (u is String && u.isNotEmpty);
      }).length;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _push({bool force = false, bool userInitiated = false}) async {
    final json = await db.exportDeck();
    if (!force && json == _lastSyncedData) {
      _set(SyncState.synced);
      return;
    }
    await _ensureToken();
    // SAFETY GUARD (push side): never let a suspiciously small local deck — the
    // classic case is a fresh install's 10-card sample deck — clobber a much
    // bigger deck already in the cloud. If we're about to push a tiny deck,
    // first check the cloud; if the cloud is far bigger, adopt it instead.
    // Only an explicit user action (userInitiated) may overwrite a bigger cloud.
    if (!userInitiated) {
      final localCount = _deckCardCount(json);
      if (localCount >= 0 && localCount <= 20) {
        final cloud = await _fetchCloud();
        final cloudCount =
            cloud.data == null ? -1 : _deckCardCount(cloud.data!);
        if (cloudCount - localCount >= 8 && localCount < cloudCount * 0.7) {
          _lastSyncedData = null; // ensure the adopt actually re-imports
          await _applyRemote(cloud.data!, cloud.updatedAt!, force: true);
          _set(SyncState.synced, 'Kept the fuller cloud deck ($cloudCount)');
          return;
        }
      }
    }
    final now = DateTime.now().toUtc();
    await _dio.post('/rest/v1/decks',
        data: {
          'user_id': _uid,
          'data': json,
          'updated_at': now.toIso8601String(),
        },
        options: Options(
            headers: {..._restHeaders, 'Prefer': 'resolution=merge-duplicates'}));
    _lastSyncedData = json;
    _lastSyncedAt = now;
    await _writeLastAt(now);
    await _writeDirty(false);
    _set(SyncState.synced);
  }

  Future<void> _applyRemote(String data, DateTime updatedAt,
      {bool force = false}) async {
    if (data == _lastSyncedData) {
      _lastSyncedAt = updatedAt;
      await _writeLastAt(updatedAt);
      return;
    }
    // SAFETY GUARD: never let a much smaller cloud deck silently wipe a bigger
    // local one (this is exactly how a stale sample deck once ate the whole
    // collection). If applying the remote would delete a large share of local
    // cards, keep the local deck instead and push it up as the source of truth.
    // Explicit user actions (first-run "keep cloud") pass force:true to bypass.
    if (!force) {
      final localCount = await db.countCards();
      final remoteCount = _deckCardCount(data);
      final lost = localCount - remoteCount;
      // Also guard IMAGES: never let a remote deck that has noticeably fewer
      // images overwrite local — that's how newer photos got reverted to older.
      final localImages = await db.countCardsWithImage();
      final remoteImages = _deckImageCount(data);
      final lostImages = localImages - remoteImages;
      final destructive = (remoteCount >= 0 &&
              localCount > 0 &&
              lost >= 8 &&
              remoteCount < localCount * 0.7) ||
          (remoteImages >= 0 &&
              localImages > 0 &&
              lostImages >= 5 &&
              remoteImages < localImages * 0.7);
      if (destructive) {
        await _writeDirty(true);
        await _push(force: true);
        _set(SyncState.synced,
            'Kept this device’s deck ($localCount cards, $localImages images)');
        return;
      }
    }
    _applyingRemote = true;
    try {
      await db.importDeck(data);
      _lastSyncedData = data;
      _lastSyncedAt = updatedAt;
      await _writeLastAt(updatedAt);
      await _writeDirty(false);
    } finally {
      _applyingRemote = false;
    }
  }

  /// Manual "Sync now" — force a pull of the latest cloud deck.
  Future<void> pullNow() async {
    if (!signedIn) return;
    _set(SyncState.syncing, 'Checking…');
    try {
      final c = await _fetchCloud();
      if (c.data != null) await _applyRemote(c.data!, c.updatedAt!);
      _set(SyncState.synced);
    } catch (e) {
      _set(SyncState.error, _friendly(e));
    }
  }

  // --- Image storage -----------------------------------------------------
  static const String imageBucket = 'card-images';

  /// Uploads image [bytes] to Supabase Storage and returns its public URL.
  /// Throws a short descriptive error on failure (the caller keeps the local
  /// bytes, so nothing is ever lost — but we surface WHY it failed).
  Future<String> uploadImage(int cardId, Uint8List bytes) async {
    if (!signedIn) throw 'not signed in';
    await _ensureToken();
    final path = '$_uid/${DateTime.now().microsecondsSinceEpoch}-$cardId.jpg';
    final r = await _dio.post(
      '/storage/v1/object/$imageBucket/$path',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'apikey': SupabaseConfig.anonKey,
          'Authorization': 'Bearer $_access',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        contentType: 'image/jpeg',
        validateStatus: (_) => true, // inspect the status ourselves
      ),
    );
    final code = r.statusCode ?? 0;
    if (code >= 200 && code < 300) {
      return '${SupabaseConfig.url}/storage/v1/object/public/$imageBucket/$path';
    }
    final body = r.data is Map
        ? ((r.data as Map)['message'] ?? (r.data as Map)['error'] ?? '')
        : r.data;
    throw 'HTTP $code ${body.toString().substring(0, body.toString().length.clamp(0, 120))}';
  }

  /// Uploads every local image that isn't in Storage yet, records its URL, and
  /// then syncs the (now lightweight) deck. Returns (uploaded, failed) counts.
  Future<({int uploaded, int failed, String? error})> migrateImagesToStorage(
      {void Function(int done, int total)? onProgress}) async {
    if (!signedIn) return (uploaded: 0, failed: 0, error: 'not signed in');
    final pending = await db.cardsNeedingImageUpload();
    var uploaded = 0, failed = 0;
    String? sampleError;
    for (var i = 0; i < pending.length; i++) {
      final card = pending[i];
      try {
        final url = await uploadImage(card.id, card.imageBytes!);
        await db.setImageUrl(card.id, url);
        uploaded++;
      } catch (e) {
        failed++;
        sampleError ??= e.toString();
      }
      onProgress?.call(i + 1, pending.length);
    }
    if (uploaded > 0) {
      try {
        await _push(force: true);
      } catch (_) {/* deck push can be retried by normal sync */}
    }
    return (uploaded: uploaded, failed: failed, error: sampleError);
  }

  // --- Change listeners --------------------------------------------------
  void _listenLocal() {
    _localSub = db.tableUpdates().listen((_) {
      if (_applyingRemote) return;
      _writeDirty(true);
      _set(SyncState.syncing);
      _pushDebounce?.cancel();
      _pushDebounce = Timer(const Duration(seconds: 2), () async {
        try {
          await _push();
        } catch (e) {
          _set(SyncState.error, _friendly(e));
        }
      });
    });
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_applyingRemote || _state == SyncState.syncing) return;
      try {
        // Cheap check first: only pull the full deck body if it actually changed.
        final at = await _fetchCloudMeta();
        if (at != null &&
            (_lastSyncedAt == null || at.isAfter(_lastSyncedAt!))) {
          final c = await _fetchCloud();
          if (c.data != null) {
            await _applyRemote(c.data!, c.updatedAt!);
            _set(SyncState.synced);
          }
        }
      } catch (_) {/* transient network issue — keep current state */}
    });
  }

  // --- Prefs helpers (namespaced per account) ----------------------------
  Future<DateTime?> _readLastAt() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('sync_last_$_uid');
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> _writeLastAt(DateTime at) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sync_last_$_uid', at.toIso8601String());
  }

  Future<bool> _readDirty() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool('sync_dirty_$_uid') ?? false;
  }

  Future<void> _writeDirty(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sync_dirty_$_uid', v);
  }

  String _friendly(Object e) {
    if (e is String) return e;
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map) {
        return (d['error_description'] ??
                d['msg'] ??
                d['message'] ??
                d['error'] ??
                'Network error')
            .toString();
      }
      return e.message ?? 'Network error';
    }
    return e.toString();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
