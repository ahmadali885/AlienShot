import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// "Recording saved" with the file's name and folder, and buttons to play it
/// or show it in Explorer.
Future<void> showRecordingSavedDialog(BuildContext context, String path) {
  final separator = path.lastIndexOf(Platform.pathSeparator);
  final name = path.substring(separator + 1);
  final folder = separator > 0 ? path.substring(0, separator) : '';
  return showDialog<void>(
    context: context,
    builder: (context) {
      final palette = AlienPalette.of(context);
      return AlertDialog(
        title: const Text('Recording saved'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(color: palette.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(folder, style: TextStyle(color: palette.textSoft, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Process.start('explorer.exe', ['/select,', path]);
            },
            child: const Text('Show in folder'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(Uri.file(path));
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Play'),
          ),
        ],
      );
    },
  );
}
