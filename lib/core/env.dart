/// Derleme zamanı yapılandırması. Değerler `env.json` dosyasından gelir:
///
///   flutter run --dart-define-from-file=env.json
///
/// Supabase bilgileri yoksa uygulama yalnızca yerel modda çalışır.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase "publishable" anahtarı (eski projelerde "anon" anahtarı).
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
