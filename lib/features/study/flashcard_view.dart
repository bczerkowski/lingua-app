import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';

/// A single flippable flashcard. Tap to reveal the back.
class FlashcardView extends StatefulWidget {
  final Flashcard card;
  final void Function(String text, String lang) onSpeak;
  const FlashcardView({super.key, required this.card, required this.onSpeak});

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 460));
  bool _showBack = false;

  @override
  void didUpdateWidget(covariant FlashcardView old) {
    super.didUpdateWidget(old);
    // Reset to the front whenever a new card is shown.
    if (old.card.id != widget.card.id && _showBack) {
      _showBack = false;
      _c.reverse();
    }
  }

  void _flip() {
    setState(() => _showBack = !_showBack);
    _showBack ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
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
                    child: _CardFace(child: _Back(card: widget.card, onSpeak: widget.onSpeak)),
                  )
                : _CardFace(child: _Front(card: widget.card, onSpeak: widget.onSpeak)),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
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
    final tags = card.tags.split(';').where((t) => t.trim().isNotEmpty).toList();
    if (tags.isEmpty) return const SizedBox(height: 4);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(t,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onPrimaryContainer)),
          ),
      ],
    );
  }
}

class _TargetLine extends StatelessWidget {
  final Flashcard card;
  final void Function(String, String) onSpeak;
  const _TargetLine({required this.card, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(card.polish,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          icon: const Icon(Icons.volume_up, size: 20),
          tooltip: 'Hear Polish',
          onPressed: () => onSpeak(card.polish, 'pl-PL'),
        ),
        const Text('·', style: TextStyle(fontSize: 24, color: Colors.grey)),
        Flexible(
          child: Text(card.english,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400)),
        ),
        IconButton(
          icon: const Icon(Icons.volume_up, size: 20),
          tooltip: 'Hear English',
          onPressed: () => onSpeak(card.english, 'en-US'),
        ),
      ],
    );
  }
}

class _Front extends StatelessWidget {
  final Flashcard card;
  final void Function(String, String) onSpeak;
  const _Front({required this.card, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagHeader(card: card),
        const SizedBox(height: 28),
        _TargetLine(card: card, onSpeak: onSpeak),
        const SizedBox(height: 28),
        Text('Tap to reveal',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ],
    );
  }
}

class _Back extends StatelessWidget {
  final Flashcard card;
  final void Function(String, String) onSpeak;
  const _Back({required this.card, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagHeader(card: card),
        const SizedBox(height: 14),
        _TargetLine(card: card, onSpeak: onSpeak),
        const Divider(height: 26),
        if (card.exampleSentence != null) ...[
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
        if (card.englishDefinition != null)
          Text(card.englishDefinition!,
              style: const TextStyle(fontSize: 15, color: Colors.black87)),
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
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
        ),
        clipBehavior: Clip.antiAlias,
        child: card.imageBytes != null
            ? Image.memory(card.imageBytes!, fit: BoxFit.cover)
            : const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, color: Colors.grey, size: 30),
                    SizedBox(height: 6),
                    Text('No image yet — add one in the editor',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
      ),
    );
  }
}
