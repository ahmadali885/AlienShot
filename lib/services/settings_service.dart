import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

class SettingsService {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}${Platform.pathSeparator}settings.json');
  }

  /// Before the rename to AlienShot the Windows build was published as
  /// "com.example / snapgrab", which is where getApplicationSupportDirectory()
  /// pointed. Carry those settings over once so the hotkey isn't reset.
  File? _legacyWindowsFile() {
    final appData = Platform.environment['APPDATA'];
    if (!Platform.isWindows || appData == null) return null;
    final sep = Platform.pathSeparator;
    return File('$appData${sep}com.example${sep}snapgrab${sep}settings.json');
  }

  Future<AppSettings> load() async {
    try {
      final file = await _file();
      final legacy = _legacyWindowsFile();
      if (!file.existsSync() && legacy != null && legacy.existsSync()) {
        await legacy.copy(file.path);
      }
      if (!file.existsSync()) return AppSettings.defaults();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(map);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(settings.toJson()));
  }
}

final settingsService = SettingsService();
