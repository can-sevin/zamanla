import 'package:intl/intl.dart';

import 'ai_client.dart';

// ---------------------------------------------------------------------------
// Girdi / çıktı modelleri (veritabanından bağımsız, test edilebilir)
// ---------------------------------------------------------------------------

class AiArea {
  const AiArea({required this.id, required this.name, required this.kind});
  final String id;
  final String name;
  final String kind; // work | personal | other
}

class AiTaskInfo {
  const AiTaskInfo({
    required this.id,
    required this.title,
    this.areaName,
    this.dueAt,
    this.dueHasTime = false,
    this.estimateMinutes,
    this.priority = 0,
    this.important = false,
    this.urgent = false,
    this.goalTitle,
  });

  final String id;
  final String title;
  final String? areaName;
  final DateTime? dueAt;
  final bool dueHasTime;
  final int? estimateMinutes;
  final int priority;
  final bool important;
  final bool urgent;
  final String? goalTitle;
}

class AiBusySlot {
  const AiBusySlot({required this.title, required this.start, required this.end});
  final String title;
  final DateTime start;
  final DateTime end;
}

class QuickAddItem {
  QuickAddItem({
    required this.kind,
    required this.title,
    this.areaId,
    this.dueAt,
    this.dueHasTime = false,
    this.start,
    this.end,
    this.estimateMinutes,
    this.priority = 0,
    this.important = false,
    this.urgent = false,
    this.notes = '',
  });

  /// `task` veya `event`
  final String kind;
  final String title;
  final String? areaId;
  final DateTime? dueAt;
  final bool dueHasTime;
  final DateTime? start;
  final DateTime? end;
  final int? estimateMinutes;
  final int priority;
  final bool important;
  final bool urgent;
  final String notes;

  bool get isEvent => kind == 'event' && start != null && end != null;
}

class PlannedBlock {
  PlannedBlock({
    required this.title,
    required this.start,
    required this.end,
    required this.kind,
    this.taskId,
    this.reason = '',
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String kind; // task | focus | break | event
  final String? taskId;
  final String reason;
}

class DayPlan {
  DayPlan({required this.summary, required this.blocks});
  final String summary;
  final List<PlannedBlock> blocks;
}

class SubtaskSuggestion {
  SubtaskSuggestion({required this.title, this.estimateMinutes});
  final String title;
  final int? estimateMinutes;
}

// ---------------------------------------------------------------------------
// JSON şemaları (Claude ve OpenAI yapılandırılmış çıktı kurallarına uygun:
// tüm nesnelerde additionalProperties=false, tüm alanlar required)
// ---------------------------------------------------------------------------

const _nullableString = {
  'anyOf': [
    {'type': 'string'},
    {'type': 'null'},
  ],
};
const _nullableInt = {
  'anyOf': [
    {'type': 'integer'},
    {'type': 'null'},
  ],
};

const quickAddSchema = {
  'type': 'object',
  'properties': {
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['task', 'event'],
          },
          'title': {'type': 'string'},
          'area_id': _nullableString,
          'due_date': _nullableString,
          'due_time': _nullableString,
          'start': _nullableString,
          'end': _nullableString,
          'estimate_minutes': _nullableInt,
          'priority': {'type': 'integer'},
          'important': {'type': 'boolean'},
          'urgent': {'type': 'boolean'},
          'notes': {'type': 'string'},
        },
        'required': [
          'kind',
          'title',
          'area_id',
          'due_date',
          'due_time',
          'start',
          'end',
          'estimate_minutes',
          'priority',
          'important',
          'urgent',
          'notes',
        ],
        'additionalProperties': false,
      },
    },
  },
  'required': ['items'],
  'additionalProperties': false,
};

const dayPlanSchema = {
  'type': 'object',
  'properties': {
    'summary': {'type': 'string'},
    'blocks': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'task_id': _nullableString,
          'title': {'type': 'string'},
          'start': {'type': 'string'},
          'end': {'type': 'string'},
          'kind': {
            'type': 'string',
            'enum': ['task', 'focus', 'break', 'event'],
          },
          'reason': {'type': 'string'},
        },
        'required': ['task_id', 'title', 'start', 'end', 'kind', 'reason'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['summary', 'blocks'],
  'additionalProperties': false,
};

const breakdownSchema = {
  'type': 'object',
  'properties': {
    'subtasks': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'estimate_minutes': _nullableInt,
        },
        'required': ['title', 'estimate_minutes'],
        'additionalProperties': false,
      },
    },
  },
  'required': ['subtasks'],
  'additionalProperties': false,
};

// ---------------------------------------------------------------------------
// Servis
// ---------------------------------------------------------------------------

final _dateFmt = DateFormat('yyyy-MM-dd');
final _timeFmt = DateFormat('HH:mm');
final _dateTimeFmt = DateFormat("yyyy-MM-dd'T'HH:mm");

String _describeNow(DateTime now) {
  final weekday = DateFormat('EEEE', 'en').format(now);
  final offset = now.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hh = offset.inHours.abs().toString().padLeft(2, '0');
  final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return '${_dateTimeFmt.format(now)} ($weekday, UTC$sign$hh:$mm)';
}

/// Uygulamadaki yapay zeka özellikleri. Tüm sağlayıcılarla aynı şekilde
/// çalışır; sağlayıcı farkları [AiClient] uygulamalarında kalır.
class AiService {
  AiService(this.client);

  final AiClient client;

  static const _jsonOnly =
      'Return only one JSON object that matches the schema described above, '
      'with no surrounding prose and no code fences.';

  /// Doğal dildeki bir girdiyi ("yarın 15:00 müşteri toplantısı 1 saat")
  /// görev ve/veya takvim etkinliklerine dönüştürür.
  Future<List<QuickAddItem>> parseQuickAdd(
    String input, {
    required DateTime now,
    required List<AiArea> areas,
  }) async {
    final areaLines = areas
        .map((a) => '- id: "${a.id}", name: "${a.name}", kind: ${a.kind}')
        .join('\n');
    final system = '''
You turn a user's free-form note into items for a personal time-management app.
The user may write in Turkish or English. Keep titles in the user's language,
short and actionable, without the date/time words that you extracted.

Current local date and time: ${_describeNow(now)}

The user's life areas:
$areaLines

For each distinct thing the user wants to do, output one item:
- kind: "event" when it happens at a specific time span (meeting, appointment,
  class); "task" for everything else.
- area_id: the id of the best matching area (work-related -> kind work,
  family/health/home/hobby -> personal). null if unclear.
- due_date: "YYYY-MM-DD" when a task has a deadline or day, otherwise null.
  Resolve relative words (bugün, yarın, cuma, haftaya, ay sonu) from the
  current date.
- due_time: "HH:MM" (24h) only if a time is stated for a task, otherwise null.
- start / end: "YYYY-MM-DDTHH:MM" local time for events, otherwise null. If an
  event has a start but no duration, assume 60 minutes.
- estimate_minutes: effort estimate for tasks when stated or obvious, else null.
- priority: 0 none, 1 low, 2 medium, 3 high.
- important / urgent: Eisenhower flags inferred from the wording.
- notes: any extra details worth keeping, otherwise "".

Output JSON shape: {"items": [ {kind, title, area_id, due_date, due_time,
start, end, estimate_minutes, priority, important, urgent, notes} ]}
$_jsonOnly''';

    final text = await client.generate(
      system: system,
      messages: [AiMessage.user(input)],
      schema: quickAddSchema,
      effort: AiEffort.low,
    );
    return parseQuickAddJson(decodeJsonObject(text),
        validAreaIds: areas.map((a) => a.id).toSet());
  }

  /// Seçilen gün için görevleri çalışma saatleri içinde zaman bloklarına
  /// yerleştiren bir plan önerir.
  Future<DayPlan> planDay({
    required DateTime day,
    required DateTime now,
    required DateTime dayStart,
    required DateTime dayEnd,
    required List<AiTaskInfo> tasks,
    required List<AiBusySlot> busy,
    String note = '',
  }) async {
    final taskLines = tasks.isEmpty
        ? '(no open tasks)'
        : tasks.map(_taskLine).join('\n');
    final busyLines = busy.isEmpty
        ? '(nothing scheduled)'
        : busy
            .map((b) =>
                '- ${_timeFmt.format(b.start)}-${_timeFmt.format(b.end)} ${b.title}')
            .join('\n');
    final planFrom = now.isAfter(dayStart) && _sameDay(now, day) ? now : dayStart;

    final system = '''
You are a pragmatic planning assistant inside a time-management app. Build a
realistic time-blocked plan for one day. Write the summary and any new block
titles in Turkish unless the tasks are clearly in another language.

Day to plan: ${_dateFmt.format(day)} (${DateFormat('EEEE', 'en').format(day)})
Current local time: ${_describeNow(now)}
Plan only between ${_timeFmt.format(planFrom)} and ${_timeFmt.format(dayEnd)}.

Already scheduled (fixed, do not overlap or repeat these):
$busyLines

Open tasks (id | title | area | due | estimate | priority | flags):
$taskLines

Guidelines:
- Prefer overdue and due-today items, then important+urgent, then important.
- Do not try to fit everything; leave the rest out rather than overbooking.
- Use the task's estimate; if missing, guess 30-60 minutes.
- Put demanding work earlier, group small tasks together, and add a short
  break (kind "break") after about 90 minutes of continuous work, plus lunch
  around midday if the window covers it.
- For blocks that come from a task, copy its id into task_id exactly;
  otherwise task_id is null.
- start/end are "HH:MM" 24h times on the planned day, in chronological order,
  never overlapping each other or the fixed items.
- reason: one short phrase on why this block is placed there.
- summary: 1-3 sentences about the plan and anything left out.

Output JSON shape: {"summary": string, "blocks": [ {task_id, title, start,
end, kind, reason} ]}
$_jsonOnly''';

    final text = await client.generate(
      system: system,
      messages: [
        AiMessage.user(note.trim().isEmpty
            ? 'Günümü planla.'
            : 'Günümü planla. Notum: ${note.trim()}'),
      ],
      schema: dayPlanSchema,
      effort: AiEffort.medium,
    );
    return parseDayPlanJson(
      decodeJsonObject(text),
      day: day,
      validTaskIds: tasks.map((t) => t.id).toSet(),
    );
  }

  /// Bir görevi uygulanabilir alt görevlere böler.
  Future<List<SubtaskSuggestion>> breakDown({
    required String title,
    String notes = '',
    List<String> existingSubtasks = const [],
  }) async {
    final system = '''
You split a task into 3-8 concrete, sequential subtasks for a to-do app.
Each subtask starts with a verb and is small enough to finish in one sitting.
Write in the same language as the task (Turkish by default).
Do not repeat subtasks that already exist.
estimate_minutes is your effort estimate per subtask or null.

Output JSON shape: {"subtasks": [ {title, estimate_minutes} ]}
$_jsonOnly''';
    final existing = existingSubtasks.isEmpty
        ? ''
        : '\nMevcut alt görevler:\n${existingSubtasks.map((s) => '- $s').join('\n')}';
    final text = await client.generate(
      system: system,
      messages: [
        AiMessage.user('Görev: $title'
            '${notes.trim().isEmpty ? '' : '\nNotlar: ${notes.trim()}'}'
            '$existing'),
      ],
      schema: breakdownSchema,
      effort: AiEffort.low,
    );
    return parseBreakdownJson(decodeJsonObject(text));
  }

  /// Kullanıcının verilerinin özetiyle sohbet.
  Future<String> chat({
    required List<AiMessage> history,
    required String contextSnapshot,
    required DateTime now,
  }) {
    final system = '''
You are the built-in assistant of "Zamanla", a time-management app the user
runs for both work and personal life. Help them plan, prioritise, reflect on
how they spend their time, and keep a healthy work/life balance.

Answer in the user's language (Turkish by default). Be concrete and brief:
short paragraphs or simple "-" bullet lists, no tables, no headings, no
markdown emphasis. Base statements about their schedule only on the data
below; if something is not in the data, say so instead of guessing. You
cannot change their data yourself — when useful, tell them which screen to
use (Görevler, Takvim, Odak, Alışkanlıklar, Hedefler).

Current local time: ${_describeNow(now)}

User data snapshot:
$contextSnapshot''';
    return client.generate(
      system: system,
      messages: history,
      effort: AiEffort.medium,
    );
  }

  static String _taskLine(AiTaskInfo t) {
    final due = t.dueAt == null
        ? '-'
        : t.dueHasTime
            ? _dateTimeFmt.format(t.dueAt!)
            : _dateFmt.format(t.dueAt!);
    final flags = [
      if (t.important) 'important',
      if (t.urgent) 'urgent',
      if (t.goalTitle != null) 'goal:${t.goalTitle}',
    ].join(',');
    return '- ${t.id} | ${t.title} | ${t.areaName ?? '-'} | $due | '
        '${t.estimateMinutes != null ? '${t.estimateMinutes}m' : '-'} | '
        'p${t.priority} | ${flags.isEmpty ? '-' : flags}';
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ---------------------------------------------------------------------------
// Ayrıştırıcılar — modelin çıktısına körü körüne güvenmez.
// ---------------------------------------------------------------------------

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty || t.toLowerCase() == 'null' ? null : t;
}

int? _int(Object? v) => switch (v) {
      int i => i,
      double d => d.round(),
      String s => int.tryParse(s),
      _ => null,
    };

bool _bool(Object? v) => v == true || v == 'true';

DateTime? _parseLocalDateTime(String? v) {
  if (v == null) return null;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) return null;
  // Saat dilimi bilgisi yoksa yerel kabul edilir; varsa yerele çevrilir.
  return parsed.isUtc ? parsed.toLocal() : parsed;
}

DateTime? _combine(DateTime day, String? hhmm) {
  if (hhmm == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(hhmm);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 24 || min > 59) return null;
  return DateTime(day.year, day.month, day.day, h, min);
}

List<QuickAddItem> parseQuickAddJson(
  Map<String, dynamic> json, {
  required Set<String> validAreaIds,
}) {
  final items = <QuickAddItem>[];
  for (final raw in (json['items'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final title = _str(raw['title']);
    if (title == null) continue;
    final areaId = _str(raw['area_id']);
    final dueDate = _parseLocalDateTime(_str(raw['due_date']));
    final dueTime = _str(raw['due_time']);
    DateTime? dueAt;
    var dueHasTime = false;
    if (dueDate != null) {
      final withTime = _combine(dueDate, dueTime);
      dueAt = withTime ?? DateTime(dueDate.year, dueDate.month, dueDate.day);
      dueHasTime = withTime != null;
    }
    var start = _parseLocalDateTime(_str(raw['start']));
    var end = _parseLocalDateTime(_str(raw['end']));
    if (start != null && (end == null || !end.isAfter(start))) {
      end = start.add(const Duration(hours: 1));
    }
    var kind = _str(raw['kind']) == 'event' ? 'event' : 'task';
    if (kind == 'event' && start == null) {
      // Saati olmayan "etkinlik" aslında bir görevdir.
      kind = 'task';
      end = null;
    }
    if (kind == 'task') {
      start = null;
      end = null;
    }
    final estimate = _int(raw['estimate_minutes']);
    items.add(QuickAddItem(
      kind: kind,
      title: title,
      areaId: validAreaIds.contains(areaId) ? areaId : null,
      dueAt: dueAt,
      dueHasTime: dueHasTime,
      start: start,
      end: end,
      estimateMinutes: estimate != null && estimate > 0 ? estimate : null,
      priority: (_int(raw['priority']) ?? 0).clamp(0, 3),
      important: _bool(raw['important']),
      urgent: _bool(raw['urgent']),
      notes: _str(raw['notes']) ?? '',
    ));
  }
  return items;
}

DayPlan parseDayPlanJson(
  Map<String, dynamic> json, {
  required DateTime day,
  required Set<String> validTaskIds,
}) {
  final blocks = <PlannedBlock>[];
  for (final raw in (json['blocks'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final title = _str(raw['title']);
    final start = _combine(day, _str(raw['start']));
    final end = _combine(day, _str(raw['end']));
    if (title == null || start == null || end == null || !end.isAfter(start)) {
      continue;
    }
    final taskId = _str(raw['task_id']);
    final kind = switch (_str(raw['kind'])) {
      'focus' => 'focus',
      'break' => 'break',
      'event' => 'event',
      _ => 'task',
    };
    blocks.add(PlannedBlock(
      title: title,
      start: start,
      end: end,
      kind: kind,
      taskId: validTaskIds.contains(taskId) ? taskId : null,
      reason: _str(raw['reason']) ?? '',
    ));
  }
  blocks.sort((a, b) => a.start.compareTo(b.start));
  // Çakışan blokları ele: modelin hatası kullanıcıya taşınmasın.
  final cleaned = <PlannedBlock>[];
  for (final b in blocks) {
    if (cleaned.isEmpty || !b.start.isBefore(cleaned.last.end)) cleaned.add(b);
  }
  return DayPlan(summary: _str(json['summary']) ?? '', blocks: cleaned);
}

List<SubtaskSuggestion> parseBreakdownJson(Map<String, dynamic> json) {
  return [
    for (final raw in (json['subtasks'] as List? ?? const []))
      if (raw is Map && _str(raw['title']) != null)
        SubtaskSuggestion(
          title: _str(raw['title'])!,
          estimateMinutes: _int(raw['estimate_minutes']),
        ),
  ];
}
