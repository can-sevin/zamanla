import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../settings/ai_settings_screen.dart';
import 'ai_context.dart';
import 'plan_day_sheet.dart';
import 'quick_add_sheet.dart';

class _ChatMessage {
  _ChatMessage(this.role, this.text, {this.error = false});
  final String role; // user | assistant
  final String text;
  final bool error;
}

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_ChatMessage>[];
  bool _busy = false;

  static const _prompts = [
    'Bugün neye odaklanmalıyım?',
    'Bu haftamı değerlendir',
    'İş-yaşam dengem nasıl?',
    'Geciken işlerim için bir plan öner',
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final ai = await ref.read(aiServiceProvider.future);
    if (ai == null) return;
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage('user', text));
      _busy = true;
    });
    _scrollToEnd();
    try {
      final now = DateTime.now();
      final snapshot =
          await buildAssistantSnapshot(ref.read(databaseProvider), now);
      final history = [
        for (final m in _messages.where((m) => !m.error))
          m.role == 'user' ? AiMessage.user(m.text) : AiMessage.assistant(m.text),
      ];
      final reply = await ai.chat(
          history: history, contextSnapshot: snapshot, now: now);
      setState(() => _messages.add(_ChatMessage('assistant', reply.trim())));
    } on AiException catch (e) {
      setState(() => _messages.add(_ChatMessage('assistant', e.message, error: true)));
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiAsync = ref.watch(aiServiceProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistan'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Yeni sohbet',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : () => setState(_messages.clear),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: aiAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : aiAsync.value == null
              ? AiNotConfigured(
                  onOpenSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const AiSettingsScreen())))
              : ContentWidth(
                  maxWidth: 820,
                  child: Column(
                    children: [
                      Expanded(
                        child: _messages.isEmpty
                            ? _Welcome(
                                model:
                                    '${settings.aiProvider.label} · ${settings.effectiveAiModel}',
                                prompts: _prompts,
                                onPrompt: _send,
                              )
                            : ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.all(16),
                                itemCount: _messages.length + (_busy ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i == _messages.length) {
                                    return const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      ),
                                    );
                                  }
                                  return _Bubble(message: _messages[i]);
                                },
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                    hintText: 'Planın, zamanın veya önceliklerin hakkında sor…'),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Gönder',
                              onPressed: _busy ? null : _send,
                              icon: const Icon(Icons.arrow_upward),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'Asistan verilerini yalnızca soru sorduğunda, seçtiğin sağlayıcıya gönderir.',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    required this.model,
    required this.prompts,
    required this.onPrompt,
  });

  final String model;
  final List<String> prompts;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Icon(Icons.auto_awesome, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Merhaba! Zamanını birlikte planlayalım.',
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(model, style: theme.textTheme.bodySmall),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final p in prompts)
                ActionChip(label: Text(p), onPressed: () => onPrompt(p)),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => showPlanDay(context, DateTime.now()),
                icon: const Icon(Icons.calendar_month),
                label: const Text('Bugünü planla'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => showQuickAdd(context),
                icon: const Icon(Icons.bolt),
                label: const Text('Hızlı ekle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.role == 'user';
    final bg = message.error
        ? theme.colorScheme.errorContainer
        : mine
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: SelectableText(message.text, style: theme.textTheme.bodyLarge),
        ),
      ),
    );
  }
}
