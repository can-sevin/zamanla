import 'package:flutter/material.dart';

const seedColor = Color(0xFF3F6FD8);

ThemeData buildTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12))),
    ),
    dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
  );
}

/// Alan / alışkanlık renk paleti.
const paletteColors = <int>[
  0xFF3F6FD8, // mavi
  0xFF2E9D6A, // yeşil
  0xFFE0663B, // turuncu
  0xFF9B59B6, // mor
  0xFFD94F70, // pembe
  0xFF1F9AA8, // camgöbeği
  0xFFC9A227, // hardal
  0xFF607D8B, // gri-mavi
];

/// Takvim bloğu türleri.
const blockKinds = <String, String>{
  'event': 'Etkinlik',
  'task': 'Görev',
  'focus': 'Odak',
  'break': 'Mola',
};

const priorityLabels = ['Yok', 'Düşük', 'Orta', 'Yüksek'];

Color priorityColor(int p, ColorScheme scheme) => switch (p) {
      3 => const Color(0xFFD9443B),
      2 => const Color(0xFFE59A1F),
      1 => scheme.primary,
      _ => scheme.outline,
    };

const recurrenceLabels = <String?, String>{
  null: 'Tekrarlamaz',
  'daily': 'Her gün',
  'weekdays': 'Hafta içi her gün',
  'weekly': 'Her hafta',
  'monthly': 'Her ay',
};
