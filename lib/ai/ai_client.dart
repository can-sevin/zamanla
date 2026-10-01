import 'dart:convert';

/// Desteklenen yapay zeka sağlayıcıları. Hangisinin kullanılacağı
/// Ayarlar ekranından seçilir; uygulamanın geri kalanı yalnızca [AiClient]
/// arayüzünü bilir.
enum AiProviderKind {
  anthropic('Anthropic (Claude)', 'claude-opus-5-5', [
    'claude-opus-5-5',
    'claude-sonnet-5-5',
    'claude-haiku-4-5',
  ]),
  openai('OpenAI', 'gpt-5', ['gpt-5', 'gpt-5-mini']),
  gemini('Google Gemini', 'gemini-2.5-flash', [
    'gemini-2.5-pro',
    'gemini-2.5-flash',
  ]),
  openaiCompatible('OpenAI uyumlu (Ollama, LM Studio, OpenRouter, Groq…)',
      'llama3.1', []);

  const AiProviderKind(this.label, this.defaultModel, this.suggestedModels);

  final String label;
  final String defaultModel;
  final List<String> suggestedModels;

  bool get needsBaseUrl => this == AiProviderKind.openaiCompatible;
  bool get apiKeyOptional => this == AiProviderKind.openaiCompatible;

  static AiProviderKind fromName(String? name) => AiProviderKind.values
      .firstWhere((k) => k.name == name, orElse: () => AiProviderKind.anthropic);
}

enum AiEffort { low, medium, high }

class AiMessage {
  const AiMessage.user(this.content) : role = 'user';
  const AiMessage.assistant(this.content) : role = 'assistant';

  final String role;
  final String content;
}

class AiException implements Exception {
  AiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sağlayıcıdan bağımsız metin üretim arayüzü.
abstract class AiClient {
  /// [schema] verildiğinde model yanıtı o JSON şemasına uyan tek bir JSON
  /// nesnesi olmalıdır. Kısıtlı çıktıyı destekleyen sağlayıcılar şemayı
  /// API düzeyinde uygular; diğerleri sistem istemindeki talimata dayanır.
  Future<String> generate({
    required String system,
    required List<AiMessage> messages,
    Map<String, dynamic>? schema,
    AiEffort effort = AiEffort.medium,
    int maxTokens = 16000,
  });
}

/// Model çıktısından JSON nesnesini çıkarır. Kod bloğu çitlerini ve
/// nesnenin öncesindeki/sonrasındaki metni tolere eder.
Map<String, dynamic> decodeJsonObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start == -1 || end <= start) {
    throw AiException('Yapay zeka yanıtında JSON bulunamadı.');
  }
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    if (decoded is Map<String, dynamic>) return decoded;
  } on FormatException {
    // aşağıdaki hata mesajına düş
  }
  throw AiException('Yapay zeka yanıtı geçerli JSON değil.');
}

/// HTTP hata gövdesinden okunabilir bir mesaj üretir.
String describeHttpError(String provider, int status, String body) {
  String? detail;
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      final error = json['error'];
      if (error is Map && error['message'] is String) {
        detail = error['message'] as String;
      } else if (error is String) {
        detail = error;
      } else if (json['message'] is String) {
        detail = json['message'] as String;
      }
    } else if (json is List && json.isNotEmpty && json.first is Map) {
      final error = (json.first as Map)['error'];
      if (error is Map && error['message'] is String) {
        detail = error['message'] as String;
      }
    }
  } on FormatException {
    // gövde JSON değil
  }
  final hint = switch (status) {
    401 || 403 => 'API anahtarını kontrol edin.',
    404 => 'Model adını veya adresi kontrol edin.',
    429 => 'Kota/limit aşıldı, biraz sonra tekrar deneyin.',
    >= 500 => 'Sağlayıcı geçici bir sorun yaşıyor.',
    _ => null,
  };
  return [
    '$provider hatası ($status)',
    ?detail,
    ?hint,
  ].join(' — ');
}
