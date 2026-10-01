import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../providers.dart';

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// "Tümü / İş / Kişisel / …" filtre çipleri.
class AreaFilterBar extends ConsumerWidget {
  const AreaFilterBar({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? const <Area>[];
    final selected = ref.watch(areaFilterProvider);
    final notifier = ref.read(areaFilterProvider.notifier);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Tümü'),
              selected: selected == null,
              onSelected: (_) => notifier.select(null),
            ),
            for (final a in areas) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                avatar: a.icon.isEmpty ? null : Text(a.icon),
                label: Text(a.name),
                selected: selected == a.id,
                selectedColor: Color(a.color).withValues(alpha: 0.25),
                onSelected: (_) =>
                    notifier.select(selected == a.id ? null : a.id),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AreaDot extends StatelessWidget {
  const AreaDot({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Alan seçici (görev/blok/alışkanlık düzenleyicilerinde).
class AreaPicker extends ConsumerWidget {
  const AreaPicker({super.key, required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final areas = ref.watch(areasProvider).value ?? const <Area>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in areas)
          ChoiceChip(
            avatar: a.icon.isEmpty
                ? AreaDot(color: Color(a.color))
                : Text(a.icon),
            label: Text(a.name),
            selected: value == a.id,
            selectedColor: Color(a.color).withValues(alpha: 0.25),
            onSelected: (sel) => onChanged(sel ? a.id : null),
          ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.count});

  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Geniş ekranlarda içeriği ortalayıp okunabilir genişlikte tutar.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 860});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Sil',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Telefonda alttan açılan sayfa, geniş ekranda diyalog olarak gösterir.
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  if (isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: builder(context),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}

Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial) =>
    showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

Future<DateTime?> pickDate(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

/// Yapay zeka yapılandırılmamışsa kullanıcıyı ayarlara yönlendiren kart.
class AiNotConfigured extends StatelessWidget {
  const AiNotConfigured({super.key, required this.onOpenSettings});
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.auto_awesome_outlined,
    title: 'Yapay zeka henüz ayarlanmadı',
    message: 'Ayarlar > Yapay zeka bölümünden bir sağlayıcı seçip API anahtarını gir.',
    action: FilledButton.tonal(
      onPressed: onOpenSettings,
      child: const Text('Ayarlara git'),
    ),
  );
}
