/// Supabase project connection details (public by design — protected by Row
/// Level Security, so each signed-in user can only touch their own row).
class SupabaseConfig {
  static const String url = 'https://alfitpzqcpwpktjgclhj.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsZml0cHpxY3B3cGt0amdjbGhqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkwMTgwMTIsImV4cCI6MjEwNDU5NDAxMn0.6XYZ-JmZIgdcDXOJPBPhyY-abJKeKUlQIozgMPbZLNk';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
