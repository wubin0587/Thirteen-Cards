import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'app_paths.dart';
import '../i18n/strings.dart';

/// 全局游戏设置（双牌桌共享）
class AppSettings {
  AppSettings._();

  /// 难度 temperature：0.0=困难, 0.55=中等, 1.0+=简单
  static double difficulty = 0.55;

  static String get difficultyLabel {
    if (difficulty <= 0.1) return '困难';
    if (difficulty >= 0.9) return '简单';
    return '中等';
  }

  /// 玩家昵称
  static String playerName = '玩家';

  /// 音效播报
  static bool soundEnabled = true;

  /// 语言 (zh / en)
  static String locale = 'zh';

  // ----------------------------------------------------------
  // 磁盘持久化
  // ----------------------------------------------------------

  static String get _settingsPath => AppPaths.settingsFile;

  /// 从磁盘加载设置，失败时静默保留默认值。
  static Future<void> loadFromDisk() async {
    try {
      final file = File(_settingsPath);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      if (raw['difficulty'] is num) difficulty = (raw['difficulty'] as num).toDouble();
      if (raw['player_name'] is String) playerName = raw['player_name'] as String;
      if (raw['sound_enabled'] is bool) soundEnabled = raw['sound_enabled'] as bool;
      if (raw['locale'] is String) {
        locale = raw['locale'] as String;
        AppStrings.setLocale(locale);
      }
    } catch (_) {
      // 静默失败
    }
  }

  /// 保存设置到磁盘。
  static Future<void> saveToDisk() async {
    try {
      final file = File(_settingsPath);
      final dir = file.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'difficulty': difficulty,
        'player_name': playerName,
        'sound_enabled': soundEnabled,
        'locale': locale,
      }));
    } catch (_) {
      // 静默失败
    }
  }

  // ----------------------------------------------------------
  // 原有：AI 玩家池
  // ----------------------------------------------------------

  /// 20 个 AI 玩家名，每人附带随机 aggression（每次启动随机）
  static final List<AiProfile> _pool = _generatePool();

  static List<AiProfile> _generatePool() {
    final names = [
      'Alice', 'Bob', 'Charlie', 'Diana', 'Ethan',
      'Fiona', 'George', 'Hannah', 'Ivan', 'Julia',
      'Kevin', 'Lily', 'Mike', 'Nina', 'Oscar',
      'Peter', 'Quinn', 'Rose', 'Sam', 'Tina',
    ];
    final rng = Random();
    return [
      for (final name in names)
        AiProfile(
          name: name,
          aggression: (rng.nextDouble() * 2 - 1).clamp(-1.0, 1.0),
        ),
    ];
  }

  /// 为当前游戏随机选取 [count] 个 AI 玩家
  static List<AiProfile> pickForGame(int count) {
    final shuffled = [..._pool]..shuffle(Random());
    return shuffled.take(count).toList();
  }
}

class AiProfile {
  final String name;
  final double aggression;

  const AiProfile({required this.name, required this.aggression});
}
