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

  Future<void> _edit(
      BuildContext context, AppDatabase db, Catalogue? existing) async {
    final ctrl = TextEditingController(text: existing?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New category' : 'Rename category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Medical, Travel…'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(existing == null ? 'Create' : 'Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (existing == null) {
      await db.createCatalogue(name);
    } else {
      await db.renameCatalogue(existing.id, name);
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
