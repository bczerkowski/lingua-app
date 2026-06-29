import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/sync/sync_service.dart';
import '../../theme.dart';

/// Cloud sync: sign in / create an account, see status, sign out.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  SyncService get _sync => AppServices.of(context).sync;

  Future<bool> _askConflict(int localCards) async {
    if (!mounted) return true;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Two decks found'),
        content: Text(
            'This device has $localCards ${localCards == 1 ? 'card' : 'cards'}, '
            'and your account already has a saved deck in the cloud.\n\n'
            'Which one do you want to keep? The other will be replaced.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Upload THIS device'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Use the cloud deck'),
          ),
        ],
      ),
    );
    return keep ?? true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _sync.conflictResolver = _askConflict;
    try {
      await action();
    } catch (e) {
      _error = e is String ? e : 'Could not sign in. Check your email/password and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _sync.signIn(_email.text, _password.text);

  Future<void> _signUp() async {
    if (_password.text.length < 6) {
      throw 'Password must be at least 6 characters.';
    }
    await _sync.signUp(_email.text, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final sync = _sync;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud sync'),
        backgroundColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: sync,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: sync.signedIn ? _signedIn(sync) : _signedOut(),
            ),
          );
        },
      ),
    );
  }

  Widget _signedOut() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sync your deck across devices',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'Sign in (or create an account) to keep the same deck on your '
          'computer and phone. Changes sync automatically.',
          style: TextStyle(color: AppTheme.muted, height: 1.4),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEAE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFB3261E), size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFB3261E), fontSize: 13.5))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : () => _run(_signIn),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Sign in'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _busy ? null : () => _run(_signUp),
            child: const Text('Create a new account'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Use any email and a password you choose. Your deck is private to '
          'your account.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  Widget _signedIn(SyncService sync) {
    final (icon, label, color) = _statusBits(sync);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_done_outlined, color: AppTheme.coral),
            const SizedBox(width: 10),
            Expanded(
              child: Text(sync.email ?? 'Signed in',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (sync.lastSyncedAt != null)
                      Text('Last synced ${_ago(sync.lastSyncedAt!)}',
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 12.5)),
                    if (sync.message != null && sync.state == SyncState.error)
                      Text(sync.message!,
                          style: const TextStyle(
                              color: Color(0xFFB3261E), fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Your deck syncs automatically whenever you make a change. Edits on '
          'one device appear on the other within ~15 seconds (while online).',
          style: TextStyle(color: AppTheme.muted, height: 1.4, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => sync.pullNow(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Sync now'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () => sync.signOut(),
          icon: const Icon(Icons.logout, size: 18),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Signing out stops syncing on this device. Your cards stay on the '
          'device and in the cloud.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }

  (IconData, String, Color) _statusBits(SyncService sync) {
    switch (sync.state) {
      case SyncState.syncing:
        return (Icons.sync, 'Syncing…', AppTheme.coral);
      case SyncState.synced:
        return (
          Icons.check_circle_outline,
          'Up to date',
          const Color(0xFF2E7D32)
        );
      case SyncState.error:
        return (Icons.error_outline, 'Sync problem', const Color(0xFFB3261E));
      case SyncState.offline:
        return (Icons.cloud_off_outlined, 'Offline', AppTheme.muted);
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
