import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

class ClipboardService {
  Future<bool> copyPng(Uint8List bytes) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;

    final item = DataWriterItem(suggestedName: 'alienshot.png');
    item.add(Formats.png(bytes));
    await clipboard.write([item]);
    return true;
  }
}

final clipboardService = ClipboardService();
