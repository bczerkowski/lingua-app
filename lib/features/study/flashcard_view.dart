import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../theme.dart';
import 'study_controller.dart';

/// A single flashcard whose reveal state is controlled by the parent.
class FlashcardView extends StatefulWidget {
  final Flashcard card;
  final List<Meaning> extraMeanings;
  final StudyDirection direction;
  final bool revealed;
  final VoidCallback onReveal;
  final void Function(String text, String lang) onSpeak;
  const FlashcardView({
    super.key,
    required this.card,
    this.extraMeanings = const [],
    required this.direction,
    required this.revealed,
    required this.onReveal,
    required this.onSpeak,
  });

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));

  @override
  void initState() {
    super.initState();
    if (widget.revealed) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant FlashcardView old) {
    super.didUpdateWidget(old);
    if (widget.revealed != old.revealed) {
      widget.revealed ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All Polish translations for this term: the primary plus any extras.
    final polish = [
      widget.card.polish,
      for (final m in widget.extraMeanings)
        if (m.polishTranslation.trim().isNotEmpty) m.polishTranslation.trim(),
    ].join(', ');

    return GestureDetector(
      onTap: widget.revealed ? null : widget.onReveal,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final angle = _c.value * math.pi;
          final showingBack = angle > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // perspective
              ..rotateY(angle),
            child: showingBack
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _CardFace(
                        child: _Back(
                            card: widget.card,
                            polish: polish,
                            onSpeak: widget.onSpeak)),
                  )
                : _CardFace(
                    child: _Front(
                        card: widget.card,
                        polish: polish,
                        direction: widget.direction,
                        onSpeak: widget.onSpeak)),
          );
        },
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  final Widget child;
  const _CardFace({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

class _TagHeader extends StatelessWidget {
  final Flashcard card;
  const _TagHeader({required this.card});

  @override
  Widget build(BuildContext context) {
    final all = card.tags
        .split(';')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final pos = all.isNotEmpty ? all.first : null;
    final topics = all.length > 1 ? all.sublist(1) : <String>[];
    if (all.isEmpty) return const SizedBox(height: 4);

    return Wrap(
      spacing: 7,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        if (pos != null)
          _pill(pos.toUpperCase(), AppTheme.sand, const Color(0xFF55524B),
              bold: true),
        for (final t in topics)
          _pill('#$t', Colors.white, AppTheme.muted, border: true),
      ],
    );
  }

  Widget _pill(String text, Color bg, Color fg,
      {bool bold = false, bool border = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: border ? Border.all(color: AppTheme.border) : null,
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: bold ? 0.5 : 0,
              color: fg)),
    );
  }
}

/// Both terms on one line: English (headword) · Polish translation(s).
class _TargetLine extends StatelessWidget {
  final Flashcard card;
  final String polish;
  final void Function(String, String) onSpeak;
  const _TargetLine(
      {required this.card, required this.polish, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(card.english,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.black)),
        ),
        IconButton(
          icon: const Icon(Icons.volume_up_rounded, size: 20),
          color: scheme.primary,
          tooltip: 'Hear English',
          onPressed: () => onSpeak(card.english, 'en-US'),
        ),
        Text('·', style: TextStyle(fontSize: 24, color: Colors.grey.shade300)),
        Flexible(
          child: Text(polish,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF3A3833))),
        ),
      ],
    );
  }
}

/// A single big prompt word (used on the front when direction hides one side).
class _PromptWord extends StatelessWidget {
  final String text;
  final VoidCallback? onSpeak;
  const _PromptWord({required this.text, this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Colors.black)),
        ),
        if (onSpeak != null)
          IconButton(
            icon: const Icon(Icons.volume_up_rounded, size: 20),
            color: scheme.primary,
            tooltip: 'Hear it',
            onPressed: onSpeak,
          ),
      ],
    );
  }
}

class _Front extends StatelessWidget {
  final Flashcard card;
  final String polish;
  final StudyDirection direction;
  final void Function(String, String) onSpeak;
  const _Front(
      {required this.card,
      required this.polish,
      required this.direction,
      required this.onSpeak});

  Widget _prompt() {
    switch (direction) {
      case StudyDirection.both:
        return _TargetLine(card: card, polish: polish, onSpeak: onSpeak);
      case StudyDirection.englishToPolish:
        return _PromptWord(
            text: card.english,
            onSpeak: () => onSpeak(card.english, 'en-US'));
      case StudyDirection.polishToEnglish:
        return _PromptWord(text: polish);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagHeader(card: card),
        const SizedBox(height: 32),
        _prompt(),
        const SizedBox(height: 32),
        Text(
          direction == StudyDirection.both
              ? 'Recall the meaning'
              : 'Recall the translation',
          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  final Flashcard card;
  final String polish;
  final void Function(String, String) onSpeak;
  const _Back(
      {required this.card, required this.polish, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagHeader(card: card),
        const SizedBox(height: 14),
        // English · all Polish translations.
        _TargetLine(card: card, polish: polish, onSpeak: onSpeak),
        const Divider(height: 26),
        if (card.exampleSentence != null && card.exampleSentence!.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('“${card.exampleSentence}”',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, fontSize: 16, height: 1.4)),
              ),
              IconButton(
                icon: const Icon(Icons.volume_up, size: 18),
                tooltip: 'Hear sentence',
                onPressed: () => onSpeak(card.exampleSentence!, 'en-US'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (card.englishDefinition != null &&
            card.englishDefinition!.isNotEmpty)
          Text(card.englishDefinition!,
              style: const TextStyle(fontSize: 15, color: Colors.black)),
        const SizedBox(height: 18),
        _ImageAnchor(card: card),
      ],
    );
  }
}

class _ImageAnchor extends StatelessWidget {
  final Flashcard card;
  const _ImageAnchor({required this.card});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.sand,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        // contain keeps the image's aspect ratio intact (no stretching/squishing).
        child: card.imageBytes != null
            ? Image.memory(card.imageBytes!, fit: BoxFit.contain)
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, color: AppTheme.muted, size: 30),
                    SizedBox(height: 6),
                    Text('No image yet — add one in the editor',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ],
                ),
              ),
      ),
    );
  }
}
