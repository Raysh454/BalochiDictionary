import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../constants/balochi_alphabet.dart';

/// Port of `LetterJumpSidebar.vue`, reshaped into a vertical rail that suits a
/// phone screen.
///
/// Only letters that actually start a headword are offered, using the counts
/// returned by the browse-letters query.
class LetterJumpRail extends StatelessWidget {
  const LetterJumpRail({
    super.key,
    required this.activeLetter,
    required this.letterCounts,
    required this.onLetterSelected,
  });

  final String activeLetter;
  final Map<String, int> letterCounts;
  final ValueChanged<String> onLetterSelected;

  @override
  Widget build(BuildContext context) {
    final visibleLetters = balochiAlphabet
        .where((entry) => (letterCounts[entry.letter] ?? 0) > 0)
        .toList(growable: false);

    return Container(
      width: 44,
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        itemCount: visibleLetters.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _LetterButton(
              label: 'All',
              isActive: activeLetter.isEmpty,
              tooltip: 'All words',
              fontSize: 12,
              onPressed: () => onLetterSelected(''),
            );
          }

          final entry = visibleLetters[index - 1];
          final count = letterCounts[entry.letter] ?? 0;

          return _LetterButton(
            label: entry.letter,
            isActive: activeLetter == entry.letter,
            tooltip: '${entry.name} ($count)',
            onPressed: () => onLetterSelected(entry.letter),
          );
        },
      ),
    );
  }
}

class _LetterButton extends StatelessWidget {
  const _LetterButton({
    required this.label,
    required this.isActive,
    required this.tooltip,
    required this.onPressed,
    this.fontSize = 17,
  });

  final String label;
  final bool isActive;
  final String tooltip;
  final VoidCallback onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: isActive ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Text(
                label,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.2,
                  color: isActive ? Colors.white : AppColors.text,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
