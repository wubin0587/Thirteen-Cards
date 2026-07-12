import 'dart:io';

/// 跨平台数据目录路径生成器。
///
/// Windows → %APPDATA%/cards
/// macOS   → ~/Library/Application Support/cards
/// Linux   → ~/.local/share/cards
class AppPaths {
  AppPaths._();

  static String dataDir() {
    final sep = Platform.pathSeparator;
    if (Platform.isWindows) {
      return Platform.environment['APPDATA'] ??
          '${Platform.environment['USERPROFILE'] ?? '.'}$sep'
          'AppData${sep}Roaming${sep}cards';
    }
    final home = Platform.environment['HOME'] ?? '.';
    if (Platform.isMacOS) {
      return '$home${sep}Library${sep}Application Support${sep}cards';
    }
    // Linux / other Unix
    return '$home${sep}.local${sep}share${sep}cards';
  }

  static String get settingsFile => '${dataDir()}${Platform.pathSeparator}settings.json';
  static String get scoresFile => '${dataDir()}${Platform.pathSeparator}thirteen_scores.json';
  static String get achievementsFile => '${dataDir()}${Platform.pathSeparator}thirteen_achievements.json';
}
