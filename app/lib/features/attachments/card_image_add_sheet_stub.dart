import 'package:flutter/material.dart';

import 'card_image_add_source.dart';

Future<CardImageAddSource?> showCardImageAddSourceSheet(
  BuildContext context,
) {
  return showModalBottomSheet<CardImageAddSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(CardImageAddSource.gallery.icon),
            title: Text(CardImageAddSource.gallery.label),
            onTap: () => Navigator.pop(ctx, CardImageAddSource.gallery),
          ),
        ],
      ),
    ),
  );
}
