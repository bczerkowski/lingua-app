import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders a card's visual anchor. Prefers local [bytes] (instant, offline),
/// then the Storage [url] (synced from another device), then a placeholder.
class CardImage extends StatelessWidget {
  final Uint8List? bytes;
  final String? url;
  final BoxFit fit;

  /// When true, shows the full "No image yet" hint instead of a bare icon.
  final bool richPlaceholder;

  const CardImage({
    super.key,
    this.bytes,
    this.url,
    this.fit = BoxFit.contain,
    this.richPlaceholder = false,
  });

  bool get hasImage => bytes != null || (url != null && url!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      return Image.memory(bytes!, fit: fit, gaplessPlayback: true);
    }
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: fit,
        gaplessPlayback: true,
        loadingBuilder: (c, child, progress) => progress == null
            ? child
            : const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
        errorBuilder: (c, e, s) => _placeholder(broken: true),
      );
    }
    return _placeholder();
  }

  Widget _placeholder({bool broken = false}) {
    final icon = broken ? Icons.broken_image_outlined : Icons.image_outlined;
    if (!richPlaceholder) {
      return Center(child: Icon(icon, color: AppTheme.muted, size: 26));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.muted, size: 30),
          const SizedBox(height: 6),
          Text(
            broken
                ? 'Image not available offline'
                : 'No image yet — add one in the editor',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
