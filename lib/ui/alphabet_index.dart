import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const alphabetLetters = [
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

String indexLetterFor(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '#';
  final first = trimmed.characters.first.toUpperCase();
  final code = first.runes.first;
  if (code >= 0x41 && code <= 0x5A) return first;
  if (code >= 0x30 && code <= 0x39) return '#';
  if (code >= 0x410 && code <= 0x42F) return first;
  if (code == 0x401) return 'Ё';
  if (code > 127) return first;
  return '#';
}

List<String> alphabetLettersFor(Iterable<String> labels) {
  final extra = <String>{};
  for (final label in labels) {
    final letter = indexLetterFor(label);
    if (letter == '#' || (letter.codeUnitAt(0) >= 0x41 && letter.codeUnitAt(0) <= 0x5A)) {
      continue;
    }
    extra.add(letter);
  }
  final extras = extra.toList()..sort((a, b) => a.compareTo(b));
  return [...alphabetLetters, ...extras];
}

Map<String, int> firstIndexByLetter(List<String> labels) {
  final map = <String, int>{};
  for (var i = 0; i < labels.length; i++) {
    map.putIfAbsent(indexLetterFor(labels[i]), () => i);
  }
  return map;
}

int indexForLetter(String letter, Map<String, int> firstIndex, List<String> letters) {
  if (firstIndex.containsKey(letter)) return firstIndex[letter]!;
  final start = letters.indexOf(letter);
  if (start < 0) return firstIndex.values.isEmpty ? 0 : firstIndex.values.reduce((a, b) => a < b ? a : b);
  for (var i = start + 1; i < letters.length; i++) {
    final hit = firstIndex[letters[i]];
    if (hit != null) return hit;
  }
  for (var i = start - 1; i >= 0; i--) {
    final hit = firstIndex[letters[i]];
    if (hit != null) return hit;
  }
  return 0;
}

class AlphabetJumpBar extends StatefulWidget {
  const AlphabetJumpBar({
    super.key,
    required this.labels,
    required this.activeLetter,
    required this.onSelect,
  });

  final List<String> labels;
  final String? activeLetter;
  final ValueChanged<String> onSelect;

  @override
  State<AlphabetJumpBar> createState() => _AlphabetJumpBarState();
}

class _AlphabetJumpBarState extends State<AlphabetJumpBar> {
  String? _dragging;

  void _pick(Offset local, double height) {
    final letters = widget.labels;
    if (letters.isEmpty || height <= 0) return;
    final i = (local.dy / height * letters.length).floor().clamp(0, letters.length - 1);
    final letter = letters[i];
    if (_dragging != letter) {
      HapticFeedback.selectionClick();
    }
    setState(() => _dragging = letter);
    widget.onSelect(letter);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final letters = widget.labels;
    final active = _dragging ?? widget.activeLetter;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 22,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (details) => _pick(details.localPosition, constraints.maxHeight),
                onVerticalDragUpdate: (details) => _pick(details.localPosition, constraints.maxHeight),
                onVerticalDragEnd: (_) => setState(() => _dragging = null),
                onVerticalDragCancel: () => setState(() => _dragging = null),
                onTapDown: (details) => _pick(details.localPosition, constraints.maxHeight),
                onTapUp: (_) => setState(() => _dragging = null),
                child: Column(
                  children: [
                    for (final letter in letters)
                      Expanded(
                        child: Center(
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: letter.length > 1 ? 8 : 10,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: letter == active
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.42),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_dragging != null)
          Transform.translate(
            offset: const Offset(-52, 0),
            child: Material(
              color: theme.colorScheme.primary,
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: Text(
                    _dragging!,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
