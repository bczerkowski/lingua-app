/// Supabase project connection details (public by design — protected by Row
/// Level Security, so each signed-in user can only touch their own row).
class SupabaseConfig {
  static const String url = 'https://yqmlbfgxzqhqstdktibg.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlxbWxiZmd4enFocXN0ZGt0aWJnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1Njc5ODAsImV4cCI6MjA5ODE0Mzk4MH0.3-MqAPjlqQbh1MsiIVv9O2I0D_ZkBBvDJlPjgQJCTc4';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
