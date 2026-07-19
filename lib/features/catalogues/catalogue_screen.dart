import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../theme.dart';

/// Create, rename, and delete the user's own categories (catalogues).
class CatalogueScreen extends StatelessWidget {
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = AppServices.of(context).db;
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, db, null),
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: StreamBuilder<List<Catalogue>>(
        stream: db.watchCatalogues(),
        builder: (context, snap) {
          final cats = snap.data ?? const <Catalogue>[];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.folder_open,
                        size: 48, color: AppTheme.muted),
                    const SizedBox(height: 12),
                    Text('No categories yet.',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.ink)),
                    const SizedBox(height: 4),
                    Text('Tap “New category” to create your own.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: AppTheme.muted)),
                  ],
                ),
              ),
            );
          }
          return StreamBuilder<Map<int, int>>(
            stream: db.watchCatalogueCounts(),
            builder: (context, countSnap) {
              final counts = countSnap.data ?? const <int, int>{};
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: cats.length,
                itemBuilder: (context, i) {
                  final c = cats[i];
                  final n = counts[c.id] ?? 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Text(
                          c.icon != null && c.icon!.isNotEmpty ? c.icon! : '📁',
                          style: const TextStyle(fontSize: 24)),
                      title: Text(c.name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      subtitle: Text('$n ${n == 1 ? 'card' : 'cards'}',
                          style: const TextStyle(color: AppTheme.muted)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Rename',
                            onPressed: () => _edit(context, db, c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                            onPressed: () => _delete(context, db, c, n),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static const _emojis = [
    '📁', '📚', '🎓', '✈️', '🩺', '⚖️', '💼', '🧠', '💬', '🗣️',
    '🌍', '🍎', '🔬', '🎬', '🎵', '⚽', '🐾', '🍳', '💰', '❤️',
    '⭐', '🔥', '🚀', '🧩', '📝', '🏛️', '🌱', '⚙️'
  ];

  Future<void> _edit(
      BuildContext context, AppDatabase db, Catalogue? existing) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    String? icon = existing?.icon;
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(hintText: 'e.g. Medical, Travel…'),
                ),
                const SizedBox(height: 14),
                Text('Icon', style: TextStyle(color: AppTheme.muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in _emojis)
                      InkWell(
                        onTap: () => setLocal(() => icon = e),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: icon == e
                                ? AppTheme.coral.withValues(alpha: 0.2)
                                : null,
                            border: Border.all(
                                color: icon == e
                                    ? AppTheme.coral
                                    : AppTheme.border),
                          ),
                          child:
                              Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, (ctrl.text.trim(), icon)),
                child: Text(existing == null ? 'Create' : 'Save')),
          ],
        ),
      ),
    );
    if (result == null || result.$1.isEmpty) return;
    final (name, chosenIcon) = result;
    if (existing == null) {
      await db.createCatalogue(name, icon: chosenIcon);
    } else {
      await db.renameCatalogue(existing.id, name);
      await db.setCatalogueIcon(existing.id, chosenIcon);
    }
  }

  Future<void> _delete(
      BuildContext context, AppDatabase db, Catalogue c, int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${c.name}”?'),
        content: Text(n == 0
            ? 'This category is empty.'
            : 'The $n ${n == 1 ? 'card' : 'cards'} in it will become '
                'uncategorized (they are not deleted).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await db.deleteCatalogue(c.id);
  }
}
