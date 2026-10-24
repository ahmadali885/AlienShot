import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_window_bar.dart';
import '../widgets/glass_container.dart';
import '../widgets/liquid_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/sign_in_dialog.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.displayName,
    required this.onRename,
    required this.onBack,
  });

  /// Empty until the user picks a name; shown as "Guest" meanwhile.
  final String displayName;
  final ValueChanged<String> onRename;
  final VoidCallback onBack;

  Future<void> _rename(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: displayName),
    );
    if (name != null) onRename(name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    final name = displayName.isEmpty ? 'Guest' : displayName;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppWindowBar(
        title: 'Profile',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, size: 18, color: palette.textSoft),
          onPressed: onBack,
        ),
      ),
      body: LiquidBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, AppWindowBar.height + 12, 28, 12),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Avatar(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Balances the pencil so the name stays centred.
                      const SizedBox(width: 30),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: palette.isLight ? palette.text : Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Edit name',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.edit_rounded, color: palette.accentText),
                        onPressed: () => _rename(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: palette.textSoft, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Text('NOT SIGNED IN', style: palette.eyebrow.copyWith(color: palette.textSoft)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Sign in to keep your uploads and settings\nin one place across devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.4, color: palette.text),
                  ),
                  const SizedBox(height: 20),
                  PillButton(
                    icon: Icons.login_rounded,
                    label: 'Sign in with AlienWave',
                    onPressed: () => showSignInComingSoon(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The AlienWave alien on the brand's deep teal, ringed like the site's
/// avatar chips.
class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.accentGradient,
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.teal, AppColors.ink2],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Image.asset('assets/images/alien_white.png', filterQuality: FilterQuality.medium),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final palette = AlienPalette.of(context);
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 32,
        textCapitalization: TextCapitalization.words,
        cursorColor: palette.accentText,
        decoration: InputDecoration(
          hintText: 'Guest',
          counterText: '',
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.accentText, width: 2)),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
