import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/providers.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Sağlayıcı, model ve API anahtarı ayarları. Anahtar cihazın güvenli
/// deposunda (Android Keystore / Windows Credential Manager) tutulur ve
/// senkronize edilmez.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late AiProviderKind _kind = ref.read(settingsProvider).aiProvider;
  late final _model = TextEditingController(text: ref.read(settingsProvider).aiModel);
  late final _baseUrl =
      TextEditingController(text: ref.read(settingsProvider).aiBaseUrl);
  final _key = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final key = await secureStorage.read(key: aiKeyStorageKey(_kind)) ?? '';
    if (mounted) setState(() => _key.text = key);
  }

  @override
  void dispose() {
    _model.dispose();
    _baseUrl.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _save({bool quiet = false}) async {
    await secureStorage.write(key: aiKeyStorageKey(_kind), value: _key.text.trim());
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(
          aiProvider: _kind,
          aiModel: _model.text.trim(),
          aiBaseUrl: _baseUrl.text.trim(),
        ));
    ref.invalidate(aiKeyProvider(_kind));
    if (!quiet && mounted) showSnack(context, 'Yapay zeka ayarları kaydedildi.');
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    await _save(quiet: true);
    try {
      final client = createAiClient(
        kind: _kind,
        model: _model.text.trim().isEmpty ? _kind.defaultModel : _model.text.trim(),
        apiKey: _key.text.trim(),
        baseUrl: _baseUrl.text.trim(),
      );
      final reply = await client.generate(
        system: 'Reply with a single short Turkish greeting.',
        messages: const [AiMessage.user('Merhaba')],
        effort: AiEffort.low,
        maxTokens: 2000,
      );
      setState(() {
        _testOk = true;
        _testResult = 'Bağlantı başarılı: "${reply.trim()}"';
      });
    } on AiException catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Yapay zeka')),
      body: ContentWidth(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Zamanla belirli bir yapay zekaya bağlı değil. Kullanmak istediğin '
              'sağlayıcıyı seç ve kendi API anahtarını gir. Hızlı ekleme, gün '
              'planlama, görev parçalama ve asistan bu ayarı kullanır.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<AiProviderKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sağlayıcı'),
              items: [
                for (final k in AiProviderKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (k) {
                if (k == null) return;
                setState(() {
                  _kind = k;
                  _model.text = '';
                  _testResult = null;
                });
                _loadKey();
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _model,
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: _kind.defaultModel,
                helperText: 'Boş bırakılırsa: ${_kind.defaultModel}',
              ),
            ),
            if (_kind.suggestedModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _kind.suggestedModels)
                    ActionChip(
                      label: Text(m),
                      onPressed: () => setState(() => _model.text = m),
                    ),
                ],
              ),
            ],
            if (_kind.needsBaseUrl) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Sunucu adresi (base URL)',
                  helperText:
                      'Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1\n'
                      'OpenRouter: https://openrouter.ai/api/v1 · Groq: https://api.groq.com/openai/v1',
                  helperMaxLines: 3,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _kind.apiKeyOptional
                    ? 'API anahtarı (yerel sunucular için gerekmez)'
                    : 'API anahtarı',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Anahtar yalnızca bu cihazın güvenli deposunda saklanır, '
              'senkronize edilmez.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Bağlantıyı test et'),
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Kaydet')),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              Card(
                color: _testOk
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_testResult!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
