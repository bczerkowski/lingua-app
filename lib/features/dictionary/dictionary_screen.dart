import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../theme.dart';
import '../editor/card_editor_screen.dart';

class DictionaryScreen extends StatefulWidget {
  final VoidCallback onStudyTap;
  const DictionaryScreen({super.key, required this.onStudyTap});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final db = services.db;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add, size: 24),
        label: const Text('New entry', style: TextStyle(fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(db: db, onStudyTap: widget.onStudyTap),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: TextField(
                style: const TextStyle(fontSize: 17),
                decoration: const InputDecoration(
                  hintText: 'Search in Polish or English…',
                  prefixIcon: Icon(Icons.search, size: 24),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Flashcard>>(
                stream: db.searchEntries(_query),
                builder: (context, snap) {
                  final items = snap.data ?? const [];
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (items.isEmpty) {
                    return Center(
                      child: Text('No matching entries.',
                          style: TextStyle(
                              fontSize: 16, color: AppTheme.muted)),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _EntryRow(
                      card: items[i],
                      services: services,
                      db: db,
                      onTap: () => _openEditor(context, items[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, int? cardId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CardEditorScreen(cardId: cardId)),
    );
  }
}

/// Eyebrow label, serif title, and a live "cards due — study now" link.
class _Header extends StatelessWidget {
  final AppDatabase db;
  final VoidCallback onStudyTap;
  const _Header({required this.db, required this.onStudyTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SŁOWNIK · DICTIONARY',
              style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                  color: AppTheme.muted)),
          const SizedBox(height: 2),
          Text('Lexicon',
              style: GoogleFonts.sourceSerif4(
                  fontSize: 38,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: AppTheme.ink)),
          const SizedBox(height: 6),
          StreamBuilder<int>(
            stream: db.watchDueCount(),
            builder: (context, snap) {
              final due = snap.data ?? 0;
              if (due == 0) {
                return Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 19, color: AppTheme.muted),
                    const SizedBox(width: 7),
                    Text('No cards due right now',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.muted)),
                  ],
                );
              }
              return InkWell(
                onTap: onStudyTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 20, color: AppTheme.coralDark),
                      const SizedBox(width: 7),
                      Text('$due cards due — study now →',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.coralDark)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A rich dictionary row: target line, example sentence, and a tag strip
/// (part of speech, gender, topics) with a circular add/added button.
class _EntryRow extends StatelessWidget {
  final Flashcard card;
  final AppServices services;
  final AppDatabase db;
  final VoidCallback onTap;
  const _EntryRow({
    required this.card,
    required this.services,
    required this.db,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final allTags =
        card.tags.split(';').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final pos = allTags.isNotEmpty ? allTags.first : null;
    final topics = allTags.length > 1 ? allTags.sublist(1) : <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _targetLine(),
                      if (card.exampleSentence != null) ...[
                        const SizedBox(height: 6),
                        Text('“${card.exampleSentence}”',
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontStyle: FontStyle.italic,
                                color: Color(0xFF55524B))),
                      ],
                      const SizedBox(height: 10),
                      _tagStrip(pos, topics),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _addButton(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _targetLine() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(card.polish,
            style: GoogleFonts.sourceSerif4(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                color: Colors.black)),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => services.tts.speak(card.polish, 'pl-PL'),
          customBorder: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: Icon(Icons.volume_up_rounded,
                size: 19, color: AppTheme.muted),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('·',
              style: TextStyle(fontSize: 19, color: AppTheme.muted)),
        ),
        Text(card.english,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black)),
      ],
    );
  }

  Widget _tagStrip(String? pos, List<String> topics) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (pos != null) _posPill(pos),
        if (card.gender != null) _genderPill(card.gender!),
        for (final t in topics) _topicPill(t),
      ],
    );
  }

  Widget _posPill(String pos) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.sand,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(pos.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF55524B))),
      );

  Widget _genderPill(String g) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFE2CC),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(g.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Color(0xFF8A6A3B))),
      );

  Widget _topicPill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text('#$t',
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppTheme.muted)),
      );

  Widget _addButton(BuildContext context) {
    if (card.isCard) {
      return Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(
          color: AppTheme.coral,
          shape: BoxShape.circle,
        ),
        child: const Tooltip(
          message: 'In study deck',
          child: Icon(Icons.check_rounded, color: Colors.white, size: 24),
        ),
      );
    }
    return Material(
      color: AppTheme.coral,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          await db.promoteToCard(card.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Added to study deck')),
            );
          }
        },
        child: const SizedBox(
          width: 46,
          height: 46,
          child: Tooltip(
            message: 'Add to study deck',
            child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
