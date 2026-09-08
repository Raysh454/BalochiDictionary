import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_theme.dart';
import '../models/dictionary_models.dart';

/// Renders a headword with its transliteration and definitions.
///
/// Balochi is written in an Arabic-derived script, so the headword is laid out
/// right-to-left while the Latin transliteration and English glosses stay
/// left-to-right.
class WordCard extends StatelessWidget {
  const WordCard({
    super.key,
    required this.entry,
    this.headwordFontSize = 26,
    this.showCopyButton = true,
  });

  final DictionaryEntry entry;
  final double headwordFontSize;
  final bool showCopyButton;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BalochiText(
                        entry.balochi,
                        style: TextStyle(
                          fontSize: headwordFontSize,
                          height: 1.6,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textStrong,
                        ),
                      ),
                      if (entry.latin.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            entry.latin,
                            style: const TextStyle(
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              color: AppColors.partOfSpeech,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (showCopyButton)
                  IconButton(
                    tooltip: 'Copy word',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    color: AppColors.textMuted,
                    onPressed: () => _copyToClipboard(context),
                  ),
              ],
            ),
            if (entry.definitions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No definition recorded for this entry.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final definition in entry.definitions)
                      _DefinitionRow(definition: definition),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(BuildContext context) async {
    final buffer = StringBuffer()..writeln(entry.balochi);
    if (entry.latin.isNotEmpty) buffer.writeln(entry.latin);
    for (final definition in entry.definitions) {
      final pos = definition.partOfSpeech;
      buffer.writeln(pos.isEmpty ? definition.text : '$pos: ${definition.text}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString().trim()));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }
}

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.definition});

  final Definition definition;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7, right: 8),
            child: SizedBox(
              width: 5,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (definition.partOfSpeech.isNotEmpty)
                    TextSpan(
                      text: '${definition.partOfSpeech}  ',
                      style: const TextStyle(
                        color: AppColors.partOfSpeech,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                    ),
                  TextSpan(text: definition.text),
                ],
              ),
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Balochi script text.
///
/// The base direction is right-to-left so mixed digits and punctuation inside
/// a headword order correctly, but the block itself is aligned with the
/// surrounding left-to-right UI unless a caller says otherwise.
class BalochiText extends StatelessWidget {
  const BalochiText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textDirection: TextDirection.rtl,
      textAlign: textAlign ?? TextAlign.left,
      style: style,
    );
  }
}
