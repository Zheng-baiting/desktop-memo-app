part of 'main.dart';

class MemoStyle {
  const MemoStyle(
    this.id,
    this.zh,
    this.en,
    this.paper,
    this.ink,
    this.muted,
    this.accent,
    this.divider,
  );

  final String id;
  final String zh;
  final String en;
  final Color paper;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color divider;

  String label(BuildContext context) => uiText(context, zh, en);
}

const memoStyles = [
  MemoStyle(
    'yellow',
    '奶油黄',
    'Butter',
    memoPaper,
    memoInk,
    memoMuted,
    memoAccent,
    memoDivider,
  ),
  MemoStyle(
    'mint',
    '薄荷绿',
    'Mint',
    Color(0xFFDFF2E4),
    Color(0xFF263F35),
    Color(0xFF526B5E),
    Color(0xFF3F6954),
    Color(0xFFB6D1BF),
  ),
  MemoStyle(
    'blue',
    '晴空蓝',
    'Sky',
    Color(0xFFE0EFFB),
    Color(0xFF293D53),
    Color(0xFF526A81),
    Color(0xFF426488),
    Color(0xFFB7CCDF),
  ),
  MemoStyle(
    'pink',
    '樱花粉',
    'Blossom',
    Color(0xFFFBE5EB),
    Color(0xFF51333F),
    Color(0xFF805A68),
    Color(0xFF90566D),
    Color(0xFFDEBDCA),
  ),
  MemoStyle(
    'lavender',
    '淡紫',
    'Lavender',
    Color(0xFFEDE5FA),
    Color(0xFF40334F),
    Color(0xFF6E5D80),
    Color(0xFF73578F),
    Color(0xFFCDBDDF),
  ),
  MemoStyle(
    'ivory',
    '米白',
    'Ivory',
    Color(0xFFF6F2E9),
    Color(0xFF403C34),
    Color(0xFF71695D),
    Color(0xFF736550),
    Color(0xFFD4CDBF),
  ),
];

// Unknown or missing preferences keep the original appearance. Stored per-note
// color indexes are retained for compatibility, without rewriting note data.
MemoStyle memoStyle(String? id) => memoStyles.firstWhere(
  (style) => style.id == id,
  orElse: () => memoStyles.first,
);
