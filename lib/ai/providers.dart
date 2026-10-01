import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_client.dart';

const _timeout = Duration(minutes: 5);

AiClient createAiClient({
  required AiProviderKind kind,
  required String model,
  required String apiKey,
  String baseUrl = '',
  http.Client? httpClient,
}) {
  final client = httpClient ?? http.Client();
  return switch (kind) {
    AiProviderKind.anthropic =>
      AnthropicClient(apiKey: apiKey, model: model, httpClient: client),
    AiProviderKind.openai => OpenAiClient(
        apiKey: apiKey,
        model: model,
        baseUrl: 'https://api.openai.com/v1',
        strictSchema: true,
        httpClient: client,
      ),
    AiProviderKind.openaiCompatible => OpenAiClient(
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
        strictSchema: false,
        httpClient: client,
      ),
    AiProviderKind.gemini =>
      GeminiClient(apiKey: apiKey, model: model, httpClient: client),
  };
}

Future<Map<String, dynamic>> _postJson(
  http.Client client,
  String provider,
  Uri uri,
  Map<String, String> headers,
  Map<String, dynamic> body,
) async {
  final http.Response res;
  try {
    res = await client
        .post(uri,
            headers: {'content-type': 'application/json', ...headers},
            body: jsonEncode(body))
        .timeout(_timeout);
  } on Exception catch (e) {
    throw AiException('$provider sunucusuna bağlanılamadı: $e');
  }
  final text = utf8.decode(res.bodyBytes);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw AiException(describeHttpError(provider, res.statusCode, text));
  }
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic>) {
    throw AiException('$provider beklenmeyen bir yanıt döndürdü.');
  }
  return json;
}

/// Anthropic Messages API (resmi Dart SDK'sı olmadığı için doğrudan HTTP).
class AnthropicClient implements AiClient {
  AnthropicClient({
    required this.apiKey,
    required this.model,
    required this.httpClient,
    this.baseUrl = 'https://api.anthropic.com',
  });

  final String apiKey;
  final String model;
  final String baseUrl;
  final http.Client httpClient;

  // effort parametresi Haiku 4.5 ve Sonnet 4.5'te hata döndürür.
  bool get _supportsEffort =>
      !model.contains('haiku') && !model.startsWith('claude-sonnet-4-5');

  // Sunucu taraflı yedek model (reddetme durumunda) destekleyen modeller.
  bool get _supportsDefaultFallback => const {
        'claude-fable-5-1',
        'claude-opus-5-5',
        'claude-opus-5',
        'claude-sonnet-5-5',
      }.contains(model);

  @override
  Future<String> generate({
    required String system,
    required List<AiMessage> messages,
    Map<String, dynamic>? schema,
    AiEffort effort = AiEffort.medium,
    int maxTokens = 16000,
  }) async {
    final outputConfig = <String, dynamic>{
      if (_supportsEffort) 'effort': effort.name,
      if (schema != null) 'format': {'type': 'json_schema', 'schema': schema},
    };
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        for (final m in messages) {'role': m.role, 'content': m.content},
      ],
      if (outputConfig.isNotEmpty) 'output_config': outputConfig,
      if (_supportsDefaultFallback) 'fallbacks': 'default',
    };
    final json = await _postJson(
      httpClient,
      'Anthropic',
      Uri.parse('$baseUrl/v1/messages'),
      {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        if (_supportsDefaultFallback)
          'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      body,
    );

    final stopReason = json['stop_reason'];
    if (stopReason == 'refusal') {
      throw AiException('Model bu isteği yanıtlamayı reddetti.');
    }
    final text = [
      for (final block in (json['content'] as List? ?? const []))
        if (block is Map && block['type'] == 'text') block['text'] as String,
    ].join();
    if (stopReason == 'max_tokens' && schema != null) {
      throw AiException('Yanıt uzunluk sınırına takıldı, tekrar deneyin.');
    }
    if (text.trim().isEmpty) {
      throw AiException('Model boş bir yanıt döndürdü.');
    }
    return text;
  }
}

/// OpenAI Chat Completions ve onunla uyumlu uç noktalar
/// (Ollama, LM Studio, OpenRouter, Groq, DeepSeek, Mistral…).
class OpenAiClient implements AiClient {
  OpenAiClient({
    required this.apiKey,
    required this.model,
    required this.baseUrl,
    required this.strictSchema,
    required this.httpClient,
  });

  final String apiKey;
  final String model;
  final String baseUrl;

  /// true: resmi OpenAI — `json_schema` yanıt formatı kullanılır.
  /// false: uyumlu sunucular — format desteği değiştiği için yalnızca
  /// sistem istemine güvenilir.
  final bool strictSchema;
  final http.Client httpClient;

  @override
  Future<String> generate({
    required String system,
    required List<AiMessage> messages,
    Map<String, dynamic>? schema,
    AiEffort effort = AiEffort.medium,
    int maxTokens = 16000,
  }) async {
    if (baseUrl.trim().isEmpty) {
      throw AiException('Sunucu adresi (base URL) girilmemiş.');
    }
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        for (final m in messages) {'role': m.role, 'content': m.content},
      ],
      if (strictSchema) 'max_completion_tokens': maxTokens,
      if (!strictSchema) 'max_tokens': maxTokens,
      if (schema != null && strictSchema)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'output', 'strict': true, 'schema': schema},
        },
    };
    final json = await _postJson(
      httpClient,
      strictSchema ? 'OpenAI' : 'Sunucu',
      Uri.parse('$root/chat/completions'),
      {if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey'},
      body,
    );
    final choices = json['choices'] as List? ?? const [];
    if (choices.isEmpty) throw AiException('Model boş bir yanıt döndürdü.');
    final message = (choices.first as Map)['message'] as Map? ?? const {};
    if (message['refusal'] is String) {
      throw AiException('Model bu isteği yanıtlamayı reddetti.');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw AiException('Model boş bir yanıt döndürdü.');
    }
    return content;
  }
}

/// Google Gemini generateContent API.
class GeminiClient implements AiClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    required this.httpClient,
  });

  final String apiKey;
  final String model;
  final http.Client httpClient;

  @override
  Future<String> generate({
    required String system,
    required List<AiMessage> messages,
    Map<String, dynamic>? schema,
    AiEffort effort = AiEffort.medium,
    int maxTokens = 16000,
  }) async {
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        for (final m in messages)
          {
            'role': m.role == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m.content},
            ],
          },
      ],
      'generationConfig': {
        'maxOutputTokens': maxTokens,
        if (schema != null) 'responseMimeType': 'application/json',
        'responseJsonSchema': ?schema,
      },
    };
    final json = await _postJson(
      httpClient,
      'Gemini',
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
          '${Uri.encodeComponent(model)}:generateContent'),
      {'x-goog-api-key': apiKey},
      body,
    );
    final candidates = json['candidates'] as List? ?? const [];
    if (candidates.isEmpty) {
      final reason = (json['promptFeedback'] as Map?)?['blockReason'];
      throw AiException(reason != null
          ? 'Gemini isteği engelledi ($reason).'
          : 'Model boş bir yanıt döndürdü.');
    }
    final parts =
        ((candidates.first as Map)['content'] as Map?)?['parts'] as List? ??
            const [];
    final text = [
      for (final p in parts)
        if (p is Map && p['text'] is String && p['thought'] != true)
          p['text'] as String,
    ].join();
    if (text.trim().isEmpty) throw AiException('Model boş bir yanıt döndürdü.');
    return text;
  }
}
