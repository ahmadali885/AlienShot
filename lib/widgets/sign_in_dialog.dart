import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// AlienWave accounts don't exist yet; every "Sign in" entry point (tray menu,
/// profile page) shows this instead.
Future<void> showSignInComingSoon(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign in'),
      content: Text(
        'AlienWave accounts are coming soon — you\'ll be able to sign in '
        'and keep every upload in one place.',
        style: TextStyle(color: AlienPalette.of(context).textSoft, height: 1.4),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
      ],
    ),
  );
}
