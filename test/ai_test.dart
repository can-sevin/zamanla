import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zamanla/ai/ai_client.dart';
import 'package:zamanla/ai/ai_service.dart';
import 'package:zamanla/ai/providers.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUpAll(() => initializeDateFormatting());

  group('decodeJsonObject', () {
    test('kod çitlerini ve çevre metni tolere eder', () {
      final json = decodeJsonObject('Tabii:\n```json\n{"a": 1}\n```\n');
      expect(json, {'a': 1});
    });

    test('JSON yoksa AiException fırlatır', () {
      expect(() => decodeJsonObject('yok'), throwsA(isA<AiException>()));
    });
  });

  group('parseQuickAddJson', () {
    test('görev ve etkinliği ayırır, geçersiz alanı temizler', () {
      final items = parseQuickAddJson({
        'items': [
          {
            'kind': 'event',
            'title': 'Müşteri toplantısı',
            'area_id': 'area-work',
            'due_date': null,
            'due_time': null,
            'start': '2026-10-02T14:00',
            'end': null,
            'estimate_minutes': null,
            'priority': 2,
            'important': true,
            'urgent': false,
            'notes': '',
          },
          {
            'kind': 'task',
            'title': 'Rapor teslimi',
            'area_id': 'uydurma',
            'due_date': '2026-10-03',
            'due_time': '17:30',
            'start': null,
            'end': null,
            'estimate_minutes': 90,
            'priority': 9,
            'important': false,
            'urgent': true,
            'notes': 'PDF olarak',
          },
          {'kind': 'task', 'title': '   '},
        ],
      }, validAreaIds: {'area-work', 'area-personal'});

      expect(items, hasLength(2));
      final event = items[0];
      expect(event.isEvent, isTrue);
      expect(event.start, DateTime(2026, 10, 2, 14));
      expect(event.end, DateTime(2026, 10, 2, 15), reason: 'süre yoksa 1 saat');
      expect(event.areaId, 'area-work');

      final task = items[1];
      expect(task.isEvent, isFalse);
      expect(task.areaId, isNull);
      expect(task.dueAt, DateTime(2026, 10, 3, 17, 30));
      expect(task.dueHasTime, isTrue);
      expect(task.priority, 3, reason: 'öncelik 0-3 aralığına kırpılır');
      expect(task.estimateMinutes, 90);
    });

    test('saati olmayan etkinlik göreve dönüşür', () {
      final items = parseQuickAddJson({
        'items': [
          {'kind': 'event', 'title': 'Doğum günü', 'due_date': '2026-10-05'},
        ],
      }, validAreaIds: {});
      expect(items.single.kind, 'task');
      expect(items.single.dueAt, DateTime(2026, 10, 5));
      expect(items.single.dueHasTime, isFalse);
    });
  });

  group('parseDayPlanJson', () {
    test('sıralar, çakışanları ve geçersizleri eler, bilinmeyen task_id\'yi siler', () {
      final day = DateTime(2026, 10, 1);
      final plan = parseDayPlanJson({
        'summary': 'Yoğun bir gün.',
        'blocks': [
          {'task_id': 't2', 'title': 'B', 'start': '11:00', 'end': '12:00', 'kind': 'task', 'reason': ''},
          {'task_id': 't1', 'title': 'A', 'start': '09:00', 'end': '10:30', 'kind': 'task', 'reason': 'öncelikli'},
          {'task_id': null, 'title': 'Çakışan', 'start': '10:00', 'end': '10:45', 'kind': 'focus', 'reason': ''},
          {'task_id': 'x', 'title': 'Ters', 'start': '15:00', 'end': '14:00', 'kind': 'task', 'reason': ''},
          {'task_id': 'hayali', 'title': 'Mola', 'start': '10:30', 'end': '10:45', 'kind': 'break', 'reason': ''},
        ],
      }, day: day, validTaskIds: {'t1', 't2'});

      expect(plan.summary, 'Yoğun bir gün.');
      expect(plan.blocks.map((b) => b.title), ['A', 'Mola', 'B']);
      expect(plan.blocks[0].start, DateTime(2026, 10, 1, 9));
      expect(plan.blocks[0].taskId, 't1');
      expect(plan.blocks[1].taskId, isNull);
      expect(plan.blocks[1].kind, 'break');
    });
  });

  group('AnthropicClient', () {
    test('Messages API isteğini doğru kurar ve metin bloklarını birleştirir', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'thinking', 'thinking': ''},
              {'type': 'text', 'text': '{"subtasks": []}'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = createAiClient(
        kind: AiProviderKind.anthropic,
        model: 'claude-opus-5-5',
        apiKey: 'test-key',
        httpClient: mock,
      );
      final text = await client.generate(
        system: 'sys',
        messages: const [AiMessage.user('merhaba')],
        schema: breakdownSchema,
        effort: AiEffort.low,
      );

      expect(text, '{"subtasks": []}');
      expect(captured.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(captured.headers['x-api-key'], 'test-key');
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(captured.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['system'], 'sys');
      expect(body['fallbacks'], 'default');
      expect(body['output_config']['effort'], 'low');
      expect(body['output_config']['format']['type'], 'json_schema');
      expect(body.containsKey('thinking'), isFalse);
    });

    test('Haiku için effort ve fallback göndermez', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'Merhaba!'},
              ],
            }),
            200);
      });
      await createAiClient(
        kind: AiProviderKind.anthropic,
        model: 'claude-haiku-4-5',
        apiKey: 'k',
        httpClient: mock,
      ).generate(system: 's', messages: const [AiMessage.user('x')]);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('output_config'), isFalse);
      expect(body.containsKey('fallbacks'), isFalse);
      expect(captured.headers.containsKey('anthropic-beta'), isFalse);
    });

    test('refusal durumunda anlaşılır hata verir', () async {
      final mock = MockClient((_) async => http.Response(
          jsonEncode({'stop_reason': 'refusal', 'content': []}), 200));
      final client = createAiClient(
          kind: AiProviderKind.anthropic,
          model: 'claude-opus-5-5',
          apiKey: 'k',
          httpClient: mock);
      expect(
        client.generate(system: 's', messages: const [AiMessage.user('x')]),
        throwsA(isA<AiException>()),
      );
    });

    test('HTTP hatasını Türkçe ipucuyla açıklar', () async {
      final mock = MockClient((_) async => http.Response(
          jsonEncode({
            'type': 'error',
            'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'},
          }),
          401));
      final client = createAiClient(
          kind: AiProviderKind.anthropic,
          model: 'claude-opus-5-5',
          apiKey: 'yanlis',
          httpClient: mock);
      await expectLater(
        client.generate(system: 's', messages: const [AiMessage.user('x')]),
        throwsA(isA<AiException>().having((e) => e.message, 'message',
            allOf(contains('401'), contains('invalid x-api-key'), contains('API anahtarını')))),
      );
    });
  });

  group('OpenAI ve Gemini istemcileri', () {
    test('OpenAI json_schema yanıt formatı kullanır', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': '{"subtasks": []}'},
                },
              ],
            }),
            200);
      });
      await createAiClient(
        kind: AiProviderKind.openai,
        model: 'gpt-5',
        apiKey: 'sk',
        httpClient: mock,
      ).generate(
          system: 's', messages: const [AiMessage.user('x')], schema: breakdownSchema);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(captured.headers['authorization'], 'Bearer sk');
      expect(body['response_format']['type'], 'json_schema');
      expect(body['messages'][0]['role'], 'system');
    });

    test('OpenAI uyumlu yerel sunucu: anahtarsız, response_format yok', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'content': 'tamam'}},
              ],
            }),
            200);
      });
      await createAiClient(
        kind: AiProviderKind.openaiCompatible,
        model: 'llama3.1',
        apiKey: '',
        baseUrl: 'http://localhost:11434/v1/',
        httpClient: mock,
      ).generate(
          system: 's', messages: const [AiMessage.user('x')], schema: breakdownSchema);
      expect(captured.url.toString(), 'http://localhost:11434/v1/chat/completions');
      expect(captured.headers.containsKey('authorization'), isFalse);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('response_format'), isFalse);
    });

    test('Gemini rolleri ve düşünce parçalarını doğru işler', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return _json({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'iç düşünce', 'thought': true},
                  {'text': 'yanıt'},
                ],
              },
            },
          ],
        });
      });
      final text = await createAiClient(
        kind: AiProviderKind.gemini,
        model: 'gemini-2.5-flash',
        apiKey: 'g',
        httpClient: mock,
      ).generate(system: 's', messages: const [
        AiMessage.user('a'),
        AiMessage.assistant('b'),
        AiMessage.user('c'),
      ]);
      expect(text, 'yanıt');
      expect(captured.headers['x-goog-api-key'], 'g');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect((body['contents'] as List).map((c) => c['role']), ['user', 'model', 'user']);
    });
  });

  group('AiService.parseQuickAdd uçtan uca (sahte istemci)', () {
    test('modelin JSON yanıtını öğelere çevirir', () async {
      final service = AiService(_FakeClient(jsonEncode({
        'items': [
          {
            'kind': 'task',
            'title': 'Annemi ara',
            'area_id': 'area-personal',
            'due_date': '2026-10-01',
            'due_time': null,
            'start': null,
            'end': null,
            'estimate_minutes': 15,
            'priority': 1,
            'important': true,
            'urgent': false,
            'notes': '',
          },
        ],
      })));
      final items = await service.parseQuickAdd(
        'akşam annemi ara',
        now: DateTime(2026, 10, 1, 9),
        areas: const [
          AiArea(id: 'area-work', name: 'İş', kind: 'work'),
          AiArea(id: 'area-personal', name: 'Kişisel', kind: 'personal'),
        ],
      );
      expect(items.single.title, 'Annemi ara');
      expect(items.single.areaId, 'area-personal');
      expect(items.single.dueAt, DateTime(2026, 10, 1));
    });
  });
}

class _FakeClient implements AiClient {
  _FakeClient(this.reply);
  final String reply;

  @override
  Future<String> generate({
    required String system,
    required List<AiMessage> messages,
    Map<String, dynamic>? schema,
    AiEffort effort = AiEffort.medium,
    int maxTokens = 16000,
  }) async =>
      reply;
}
