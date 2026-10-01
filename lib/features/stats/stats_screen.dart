import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

enum _Range {
  thisWeek('Bu hafta'),
  lastWeek('Geçen hafta'),
  thisMonth('Bu ay');

  const _Range(this.label);
  final String label;

  (DateTime, DateTime) bounds(DateTime today) => switch (this) {
        _Range.thisWeek => (startOfWeek(today), addDays(startOfWeek(today), 7)),
        _Range.lastWeek => (
            addDays(startOfWeek(today), -7),
            startOfWeek(today)
          ),
        _Range.thisMonth => (
            startOfMonth(today),
            DateTime(today.year, today.month + 1)
          ),
      };
}

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _Range _range = _Range.thisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final (start, end) = _range.bounds(today);
    final filter = ref.watch(areaFilterProvider);
    final areas = ref.watch(areaMapProvider);
    final entries = (ref.watch(entriesInRangeProvider((start, end))).value ??
            const <TimeEntry>[])
        .where((e) => e.endAt != null && matchesArea(filter, e.areaId))
        .toList();
    final completed = (ref.watch(completedRecentlyProvider).value ?? const <Task>[])
        .where((t) =>
            t.completedAt != null &&
            !t.completedAt!.isBefore(start) &&
            t.completedAt!.isBefore(end) &&
            matchesArea(filter, t.areaId))
        .toList();
    final habits = (ref.watch(habitsProvider).value ?? const <Habit>[])
        .where((h) => matchesArea(filter, h.areaId))
        .toList();
    final logs =
        ref.watch(habitLogsProvider((start, addDays(end, -1)))).value ??
            const <String, int>{};
    final allTasks = {
      for (final t in ref.watch(openTasksProvider).value ?? const <Task>[]) t.id: t,
      for (final t in ref.watch(completedRecentlyProvider).value ?? const <Task>[])
        t.id: t,
    };

    final dayCount = end.difference(start).inDays;
    final perDay = List.generate(dayCount, (_) => <String?, double>{});
    final perArea = <String?, Duration>{};
    final perTask = <String, Duration>{};
    var total = Duration.zero;
    for (final e in entries) {
      final d = e.endAt!.difference(e.startAt);
      total += d;
      perArea[e.areaId] = (perArea[e.areaId] ?? Duration.zero) + d;
      if (e.taskId != null) {
        perTask[e.taskId!] = (perTask[e.taskId!] ?? Duration.zero) + d;
      }
      final idx = startOfDay(e.startAt).difference(start).inDays;
      if (idx >= 0 && idx < dayCount) {
        perDay[idx][e.areaId] = (perDay[idx][e.areaId] ?? 0) + d.inMinutes;
      }
    }

    var planned = 0;
    var achieved = 0.0;
    for (final h in habits) {
      for (var d = start; d.isBefore(end) && !d.isAfter(today); d = addDays(d, 1)) {
        if (d.isBefore(startOfDay(h.createdAt)) || !weekdayInMask(h.weekdays, d)) {
          continue;
        }
        planned++;
        final c = logs['${h.id}_${dayKey(d)}'] ?? 0;
        achieved += math.min(1, c / math.max(1, h.targetPerDay));
      }
    }
    final habitRate = planned == 0 ? null : achieved / planned;

    Color colorOf(String? areaId) =>
        areas[areaId] == null ? theme.colorScheme.outline : Color(areas[areaId]!.color);
    String nameOf(String? areaId) => areas[areaId]?.name ?? 'Alansız';

    final topTasks = perTask.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('İstatistik')),
      body: ContentWidth(
        maxWidth: 980,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            SegmentedButton<_Range>(
              segments: [
                for (final r in _Range.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
            const SizedBox(height: 12),
            const AreaFilterBar(padding: EdgeInsets.zero),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 700 ? 4 : 2;
              final w = (c.maxWidth - (cols - 1) * 12) / cols;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Kpi(width: w, icon: Icons.timer_outlined, label: 'Odak süresi', value: formatDuration(total)),
                  _Kpi(width: w, icon: Icons.task_alt, label: 'Tamamlanan görev', value: '${completed.length}'),
                  _Kpi(
                      width: w,
                      icon: Icons.repeat,
                      label: 'Alışkanlık başarısı',
                      value: habitRate == null ? '–' : '%${(habitRate * 100).round()}'),
                  _Kpi(
                      width: w,
                      icon: Icons.balance,
                      label: 'İş / Kişisel',
                      value: _balance(perArea, areas)),
                ],
              );
            }),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 16),
                      child: Text('Günlük odak (dakika)',
                          style: theme.textTheme.titleSmall),
                    ),
                    SizedBox(
                      height: 220,
                      child: total == Duration.zero
                          ? const Center(child: Text('Bu aralıkta kayıt yok'))
                          : _DailyBars(
                              perDay: perDay,
                              start: start,
                              colorOf: colorOf,
                              areaOrder: [...areas.keys, null],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final pie = Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Alanlara göre', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      if (perArea.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Veri yok')),
                        )
                      else
                        Row(
                          children: [
                            SizedBox(
                              width: 140,
                              height: 140,
                              child: PieChart(PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 36,
                                sections: [
                                  for (final e in perArea.entries)
                                    PieChartSectionData(
                                      value: e.value.inMinutes.toDouble(),
                                      color: colorOf(e.key),
                                      radius: 28,
                                      showTitle: false,
                                    ),
                                ],
                              )),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final e in perArea.entries)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          AreaDot(color: colorOf(e.key), size: 10),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text(nameOf(e.key))),
                                          Text(formatDuration(e.value)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
              final top = Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('En çok zaman ayrılan görevler',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (topTasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('Göreve bağlı kayıt yok')),
                        ),
                      for (final e in topTasks.take(6))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: AreaDot(color: colorOf(allTasks[e.key]?.areaId)),
                          title: Text(allTasks[e.key]?.title ?? 'Silinmiş görev',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(formatDuration(e.value)),
                        ),
                    ],
                  ),
                ),
              );
              if (c.maxWidth < 700) {
                return Column(children: [pie, const SizedBox(height: 16), top]);
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pie),
                    const SizedBox(width: 16),
                    Expanded(child: top),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _balance(Map<String?, Duration> perArea, Map<String, Area> areas) {
    var work = 0;
    var personal = 0;
    for (final e in perArea.entries) {
      final kind = areas[e.key]?.kind;
      if (kind == 'work') work += e.value.inMinutes;
      if (kind == 'personal') personal += e.value.inMinutes;
    }
    final sum = work + personal;
    if (sum == 0) return '–';
    final w = (work / sum * 100).round();
    return '%$w / %${100 - w}';
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });
  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({
    required this.perDay,
    required this.start,
    required this.colorOf,
    required this.areaOrder,
  });

  final List<Map<String?, double>> perDay;
  final DateTime start;
  final Color Function(String?) colorOf;
  final List<String?> areaOrder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = perDay
        .map((m) => m.values.fold(0.0, (a, b) => a + b))
        .fold(0.0, math.max);
    final many = perDay.length > 7;
    // Okunaklı eksen: 4 civarı çizgi, dakika cinsinden yuvarlak aralıklar.
    final interval = const [5, 10, 15, 30, 60, 90, 120, 180, 240, 360]
        .map((e) => e.toDouble())
        .firstWhere((i) => i * 4 >= maxY, orElse: () => 480);
    return BarChart(
      BarChartData(
        maxY: math.max(interval, (maxY / interval).ceil() * interval),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${DateFormat('d MMM', 'tr').format(addDays(start, group.x))}\n'
              '${formatDuration(Duration(minutes: rod.toY.round()))}',
              TextStyle(color: theme.colorScheme.onInverseSurface),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: interval,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(v.round().toString(), style: theme.textTheme.labelSmall),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final d = addDays(start, v.toInt());
                if (many && d.day % 5 != 1) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(many ? '${d.day}' : weekdayShort[d.weekday - 1],
                      style: theme.textTheme.labelSmall),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < perDay.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                () {
                  var from = 0.0;
                  final stack = <BarChartRodStackItem>[];
                  for (final area in areaOrder) {
                    final v = perDay[i][area] ?? 0;
                    if (v <= 0) continue;
                    stack.add(BarChartRodStackItem(from, from + v, colorOf(area)));
                    from += v;
                  }
                  return BarChartRodData(
                    toY: from,
                    width: many ? 7 : 22,
                    rodStackItems: stack,
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  );
                }(),
              ],
            ),
        ],
      ),
    );
  }
}
