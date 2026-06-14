import 'dart:io';

import 'package:flutter/material.dart';

import 'card_image_add_source.dart';

Future<CardImageAddSource?> showCardImageAddSourceSheet(
  BuildContext context,
) {
  final options = <CardImageAddSource>[
    CardImageAddSource.gallery,
    if (Platform.isAndroid) CardImageAddSource.camera,
    if (Platform.isWindows) CardImageAddSource.clipboard,
  ];

  return showModalBottomSheet<CardImageAddSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final source in options)
            ListTile(
              leading: Icon(source.icon),
              title: Text(source.label),
              onTap: () => Navigator.pop(ctx, source),
            ),
        ],
      ),
    ),
  );
}
