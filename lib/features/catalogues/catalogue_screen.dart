import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../data/db/database.dart';
import '../../services/media/image_import_service.dart';
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
                      leading: c.iconBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(c.iconBytes!,
                                  width: 32, height: 32, fit: BoxFit.cover))
                          : Text(
                              c.icon != null && c.icon!.isNotEmpty
                                  ? c.icon!
                                  : '📁',
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
    Uint8List? iconBytes = existing?.iconBytes;
    final importer = ImageImportService();

    final result = await showDialog<(String, String?, Uint8List?)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget preview() {
            if (iconBytes != null) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(iconBytes!,
                    width: 44, height: 44, fit: BoxFit.cover),
              );
            }
            return Text(icon?.isNotEmpty == true ? icon! : '📁',
                style: const TextStyle(fontSize: 30));
          }

          return AlertDialog(
            title: Text(existing == null ? 'New category' : 'Edit category'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          hintText: 'e.g. Medical, Travel…'),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(width: 44, height: 44, child: Center(child: preview())),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('Choose image…'),
                          onPressed: () async {
                            final r = await importer.pickFromFile();
                            if (!r.ok) return;
                            final capped = await _capIcon(r.bytes!);
                            setLocal(() {
                              iconBytes = capped;
                              icon = null;
                            });
                          },
                        ),
                        if (iconBytes != null)
                          IconButton(
                            tooltip: 'Remove image',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () =>
                                setLocal(() => iconBytes = null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('…or pick an emoji',
                        style: TextStyle(color: AppTheme.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in _emojis)
                          InkWell(
                            onTap: () => setLocal(() {
                              icon = e;
                              iconBytes = null;
                            }),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: (icon == e && iconBytes == null)
                                    ? AppTheme.coral.withValues(alpha: 0.2)
                                    : null,
                                border: Border.all(
                                    color: (icon == e && iconBytes == null)
                                        ? AppTheme.coral
                                        : AppTheme.border),
                              ),
                              child: Text(e,
                                  style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, (ctrl.text.trim(), icon, iconBytes)),
                  child: Text(existing == null ? 'Create' : 'Save')),
            ],
          );
        },
      ),
    );
    if (result == null || result.$1.isEmpty) return;
    final (name, chosenIcon, chosenBytes) = result;
    final id = existing?.id ?? await db.createCatalogue(name);
    if (existing != null) await db.renameCatalogue(id, name);
    if (chosenBytes != null) {
      await db.setCatalogueIconBytes(id, chosenBytes);
    } else {
      await db.setCatalogueIconBytes(id, null);
      await db.setCatalogueIcon(id, chosenIcon);
    }
  }

  /// Downscale a picked image hard — it's only ever shown as a tiny chip icon,
  /// so we keep the stored bytes very small.
  Future<Uint8List> _capIcon(Uint8List input, {int maxDim = 96}) async {
    try {
      final codec = await ui.instantiateImageCodec(input);
      final img = (await codec.getNextFrame()).image;
      final longest = img.width > img.height ? img.width : img.height;
      if (longest <= maxDim) {
        img.dispose();
        return input;
      }
      final scale = maxDim / longest;
      final tw = (img.width * scale).round().clamp(1, maxDim);
      final th = (img.height * scale).round().clamp(1, maxDim);
      img.dispose();
      final scaled = await ui.instantiateImageCodec(input,
          targetWidth: tw, targetHeight: th);
      final frame = (await scaled.getNextFrame()).image;
      final data = await frame.toByteData(format: ui.ImageByteFormat.png);
      frame.dispose();
      return data?.buffer.asUint8List() ?? input;
    } catch (_) {
      return input;
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
