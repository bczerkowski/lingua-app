/// Supabase project connection details.
///
/// These two values are *public by design* — they ship inside the client app.
/// Access to data is protected by Supabase Row Level Security (each signed-in
/// user can only read/write their own `decks` row), so it is safe for them to
/// live in source control.
class SupabaseConfig {
  static const String url = 'https://yqmlbfgxzqhqstdktibg.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxbWxiZmd4enFocXN0ZGt0aWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1Njc5ODAsImV4cCI6MjA5ODE0Mzk4MH0.3-MqAPjlqQbh1MsiIVv9O2I0D_ZkBBvDJlPjgQJCTc4';

  /// Whether sync is configured (non-empty credentials).
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
