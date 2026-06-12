import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../editor/card_editor_screen.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

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
      appBar: AppBar(
        title: const Text('Dictionary'),
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New entry'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search Polish or English…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
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
                  return const Center(child: Text('No matching entries.'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ListTile(
                      title: Text('${c.polish}  ·  ${c.english}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: c.englishDefinition != null
                          ? Text(c.englishDefinition!,
                              maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () => _openEditor(context, c.id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.volume_up, size: 20),
                            tooltip: 'Hear Polish',
                            onPressed: () =>
                                services.tts.speak(c.polish, 'pl-PL'),
                          ),
                          if (c.isCard)
                            const Tooltip(
                              message: 'Already a study card',
                              child: Icon(Icons.check_circle,
                                  color: Colors.green, size: 22),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Add to study deck',
                              onPressed: () async {
                                await db.promoteToCard(c.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Added to study deck')),
                                  );
                                }
                              },
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, int? cardId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CardEditorScreen(cardId: cardId)),
    );
  }
}
