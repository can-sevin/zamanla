import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../ai/plan_day_sheet.dart';
import 'block_editor.dart';

const _hourHeight = 56.0;
const _gutter = 52.0;

bool get _isDesktop =>
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

Color blockColor(TimeBlock b, Map<String, Area> areas, ColorScheme scheme) {
  if (b.color != null) return Color(b.color!);
  if (b.kind == 'break') return scheme.outline;
  final area = areas[b.areaId];
  return area != null ? Color(area.color) : scheme.primary;
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _day = startOfDay(DateTime.now());
  bool? _weekView;

  void _shift(int direction, bool week) =>
      setState(() => _day = addDays(_day, direction * (week ? 7 : 1)));

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final week = _weekView ?? wide;
    final weekStart = startOfWeek(_day);
    final days = week ? [for (var i = 0; i < 7; i++) addDays(weekStart, i)] : [_day];
    final title = DateFormat('MMMM y', 'tr').format(_day);
    final showPanel = MediaQuery.sizeOf(context).width >= 1280;

    return Scaffold(
      appBar: AppBar(
        title: Text(title[0].toUpperCase() + title.substring(1)),
        actions: [
          IconButton(
            tooltip: 'Önceki',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1, week),
          ),
          TextButton(
            onPressed: () => setState(() => _day = startOfDay(DateTime.now())),
            child: const Text('Bugün'),
          ),
          IconButton(
            tooltip: 'Sonraki',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1, week),
          ),
          IconButton(
            tooltip: week ? 'Gün görünümü' : 'Hafta görünümü',
            icon: Icon(week ? Icons.view_day_outlined : Icons.view_week_outlined),
            onPressed: () => setState(() => _weekView = !week),
          ),
          IconButton(
            tooltip: 'Yapay zeka ile günü planla',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => showPlanDay(context, _day),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Takvime ekle',
        onPressed: () {
          final now = DateTime.now();
          final start = isSameDay(_day, now)
              ? roundUpToQuarter(now)
              : _day.add(const Duration(hours: 9));
          showBlockEditor(context, start: start);
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (!week)
            _WeekStrip(
              selected: _day,
              onSelect: (d) => setState(() => _day = d),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Timeline(
                    key: ValueKey('${days.first}-${days.length}'),
                    days: days,
                    onDayTap: week ? (d) => setState(() {
                          _day = d;
                          _weekView = false;
                        }) : null,
                  ),
                ),
                if (showPanel) ...[
                  const VerticalDivider(width: 1),
                  SizedBox(width: 300, child: _UnscheduledPanel(day: _day)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.selected, required this.onSelect});
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final start = startOfWeek(selected);
    final today = ref.watch(todayProvider);
    final blocks = ref
            .watch(blocksInRangeProvider((start, addDays(start, 7))))
            .value ??
        const <TimeBlock>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Builder(builder: (context) {
              final d = addDays(start, i);
              final isSel = isSameDay(d, selected);
              final isToday = isSameDay(d, today);
              final has = blocks.any((b) => isSameDay(b.startAt, d));
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelect(d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? theme.colorScheme.primaryContainer : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(weekdayShort[i], style: theme.textTheme.labelSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${d.day}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: isToday ? FontWeight.w800 : null,
                            color: isToday ? theme.colorScheme.primary : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AreaDot(
                          color: has
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          size: 5,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _Timeline extends ConsumerStatefulWidget {
  const _Timeline({super.key, required this.days, this.onDayTap});
  final List<DateTime> days;
  final ValueChanged<DateTime>? onDayTap;

  @override
  ConsumerState<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends ConsumerState<_Timeline> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final startHour = widget.days.any((d) => isSameDay(d, now))
        ? math.max(0, now.hour - 2)
        : ref.read(settingsProvider).workStartMinutes ~/ 60 - 1;
    _scroll = ScrollController(initialScrollOffset: startHour * _hourHeight);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = widget.days.first;
    final last = widget.days.last;
    final blocks = ref
            .watch(blocksInRangeProvider((first, endOfDay(last))))
            .value ??
        const <TimeBlock>[];
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final filter = ref.watch(areaFilterProvider);
    final visible =
        blocks.where((b) => matchesArea(filter, b.areaId)).toList();
    final multi = widget.days.length > 1;

    return Column(
      children: [
        if (multi)
          Padding(
            padding: const EdgeInsets.only(left: _gutter, bottom: 4),
            child: Row(
              children: [
                for (final d in widget.days)
                  Expanded(
                    child: InkWell(
                      onTap: widget.onDayTap == null
                          ? null
                          : () => widget.onDayTap!(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Text(weekdayShort[d.weekday - 1],
                                style: theme.textTheme.labelSmall),
                            Text(
                              '${d.day}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight:
                                    isSameDay(d, now) ? FontWeight.w800 : null,
                                color: isSameDay(d, now)
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * _hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * _hourHeight - 8,
                            right: 8,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in widget.days)
                    Expanded(
                      child: _DayColumn(
                        day: d,
                        blocks: visible
                            .where((b) =>
                                b.startAt.isBefore(endOfDay(d)) &&
                                b.endAt.isAfter(d))
                            .toList(),
                        now: now,
                        compact: multi,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Çakışan blokları yan yana şeritlere yerleştirir: (blok, şerit, şerit sayısı).
List<(TimeBlock, int, int)> layoutLanes(List<TimeBlock> blocks) {
  final sorted = [...blocks]..sort((a, b) => a.startAt.compareTo(b.startAt));
  final result = <(TimeBlock, int, int)>[];
  var cluster = <(TimeBlock, int)>[];
  var laneEnds = <DateTime>[];
  DateTime? clusterEnd;

  void flush() {
    for (final (b, lane) in cluster) {
      result.add((b, lane, laneEnds.length));
    }
    cluster = [];
    laneEnds = [];
    clusterEnd = null;
  }

  for (final b in sorted) {
    if (clusterEnd != null && !b.startAt.isBefore(clusterEnd!)) flush();
    var lane = laneEnds.indexWhere((end) => !b.startAt.isBefore(end));
    if (lane == -1) {
      lane = laneEnds.length;
      laneEnds.add(b.endAt);
    } else {
      laneEnds[lane] = b.endAt;
    }
    cluster.add((b, lane));
    if (clusterEnd == null || b.endAt.isAfter(clusterEnd!)) clusterEnd = b.endAt;
  }
  flush();
  return result;
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.day,
    required this.blocks,
    required this.now,
    required this.compact,
  });

  final DateTime day;
  final List<TimeBlock> blocks;
  final DateTime now;
  final bool compact;

  double _y(DateTime t) {
    final clamped = t.isBefore(day)
        ? day
        : t.isAfter(endOfDay(day))
            ? endOfDay(day)
            : t;
    return clamped.difference(day).inMinutes / 60 * _hourHeight;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final areas = ref.watch(areaMapProvider);
    final lanes = layoutLanes(blocks);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final minutes = (details.localPosition.dy / _hourHeight * 60).floor();
          final start = day.add(Duration(minutes: minutes - minutes % 15));
          showBlockEditor(context,
              start: start, end: start.add(const Duration(hours: 1)));
        },
        child: Stack(
          children: [
            // Çalışma saatleri arka planı
            Positioned(
              top: settings.workStartMinutes / 60 * _hourHeight,
              height: (settings.workEndMinutes - settings.workStartMinutes) /
                  60 *
                  _hourHeight,
              left: 0,
              right: 0,
              child: ColoredBox(
                  color: theme.colorScheme.primary.withValues(alpha: 0.03)),
            ),
            for (var h = 0; h < 24; h++)
              Positioned(
                top: h * _hourHeight,
                left: 0,
                right: 0,
                child: Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.4)),
              ),
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: VerticalDivider(
                  width: 1,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            for (final (b, lane, laneCount) in lanes)
              Positioned(
                top: _y(b.startAt),
                height: math.max(18, _y(b.endAt) - _y(b.startAt)),
                left: 2 + lane * (width - 4) / laneCount,
                width: (width - 4) / laneCount - 2,
                child: _BlockCard(
                  block: b,
                  color: blockColor(b, areas, theme.colorScheme),
                  compact: compact,
                ),
              ),
            if (isSameDay(day, now))
              Positioned(
                top: _y(now) - 1,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle),
                      ),
                      Expanded(
                          child: Container(
                              height: 2, color: theme.colorScheme.error)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _BlockCard extends ConsumerStatefulWidget {
  const _BlockCard({
    required this.block,
    required this.color,
    required this.compact,
  });

  final TimeBlock block;
  final Color color;
  final bool compact;

  @override
  ConsumerState<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends ConsumerState<_BlockCard> {
  double _moveDy = 0;
  double _resizeDy = 0;

  int _snap(double dy) => ((dy / _hourHeight * 60) / 15).round() * 15;

  Future<void> _commit() async {
    final move = _snap(_moveDy);
    final resize = _snap(_resizeDy);
    setState(() {
      _moveDy = 0;
      _resizeDy = 0;
    });
    if (move == 0 && resize == 0) return;
    final b = widget.block;
    final start = b.startAt.add(Duration(minutes: move));
    var end = b.endAt.add(Duration(minutes: move + resize));
    if (end.difference(start).inMinutes < 15) {
      end = start.add(const Duration(minutes: 15));
    }
    await ref.read(blocksRepoProvider).save(
        b.id, BlocksCompanion(startAt: Value(start), endAt: Value(end)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.block;
    final isBreak = b.kind == 'break';
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Color.lerp(widget.color, Colors.black, 0.55)!;
    final card = Container(
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: isBreak ? 0.10 : 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: widget.color, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 3, 4, 2),
      child: LayoutBuilder(builder: (context, c) {
        return ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                b.title,
                maxLines: c.maxHeight > 40 ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontStyle: isBreak ? FontStyle.italic : null,
                ),
              ),
              if (c.maxHeight > 34)
                Text(
                  '${formatTime(b.startAt)}–${formatTime(b.endAt)}',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: textColor.withValues(alpha: 0.8)),
                ),
            ],
          ),
        );
      }),
    );

    return Transform.translate(
      offset: Offset(0, _moveDy),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: -_resizeDy,
            child: GestureDetector(
              onTap: () => showBlockEditor(context, block: b),
              onVerticalDragUpdate: _isDesktop
                  ? (d) => setState(() => _moveDy += d.delta.dy)
                  : null,
              onVerticalDragEnd: _isDesktop ? (_) => _commit() : null,
              onLongPressMoveUpdate: _isDesktop
                  ? null
                  : (d) => setState(() => _moveDy = d.offsetFromOrigin.dy),
              onLongPressEnd: _isDesktop ? null : (_) => _commit(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: card,
              ),
            ),
          ),
          if (_isDesktop)
            Positioned(
              left: 0,
              right: 0,
              bottom: -_resizeDy - 3,
              height: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) =>
                      setState(() => _resizeDy += d.delta.dy),
                  onVerticalDragEnd: (_) => _commit(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Geniş ekranda: takvime henüz yerleştirilmemiş açık görevler.
class _UnscheduledPanel extends ConsumerWidget {
  const _UnscheduledPanel({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(filteredOpenTasksProvider).value ?? const <Task>[];
    final weekStart = startOfWeek(day);
    final blocks = ref
            .watch(blocksInRangeProvider((weekStart, addDays(weekStart, 7))))
            .value ??
        const <TimeBlock>[];
    final scheduled = {for (final b in blocks) b.taskId};
    final pending = tasks.where((t) => !scheduled.contains(t.id)).toList();
    final areas = ref.watch(areaMapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Bu hafta planlanmamış', style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Bir görevi takvime yerleştirmek için tıkla.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline)),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: pending.isEmpty
              ? const EmptyState(
                  icon: Icons.done_all, title: 'Hepsi planlandı')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: pending.length,
                  itemBuilder: (context, i) {
                    final t = pending[i];
                    final area = areas[t.areaId];
                    return ListTile(
                      dense: true,
                      leading: AreaDot(
                          color: area == null
                              ? theme.colorScheme.outline
                              : Color(area.color)),
                      title: Text(t.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (t.dueAt != null) formatDue(t.dueAt!, t.dueHasTime),
                        if (t.estimateMinutes != null)
                          formatDuration(Duration(minutes: t.estimateMinutes!)),
                      ].join(' · ')),
                      trailing: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: () => scheduleTaskBlock(context, ref, t),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
