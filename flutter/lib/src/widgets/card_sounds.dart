/// 卡牌音效系统 — 使用 audioplayers 包播放 MP3。
///
/// MP3 文件（通过 Flutter asset 系统加载）：
///   assets/sounds/card_deal.mp3  发牌 / 入墩 / 出墩（共用）
///   assets/sounds/shoot.mp3      打枪
///   assets/sounds/homerun.mp3    全垒打（棒球击球）
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:audioplayers/audioplayers.dart';

import '../backend/app_settings.dart';

/// 卡牌音效系统。
///
/// 快速触发类（发牌/入墩/出墩）：每次新建 [AudioPlayer]，播完自动释放，
/// 允许多个音效重叠播放，和旧 VBS 多进程行为一致。
///
/// 一次性事件（打枪/全垒打）：复用专用 [AudioPlayer]，正在播放时跳过。
class CardSounds {
  CardSounds._();

  // 一次性事件专用 player
  static final AudioPlayer _shootPlayer = AudioPlayer();
  static final AudioPlayer _homerunPlayer = AudioPlayer();

  /// 预热（预留 hook）。
  static Future<void> warmup() async {}

  // ============================================================
  //  快速触发：每次独立播放，互不打断
  // ============================================================

  static Future<void> playDeal() => _fire('sounds/card_deal.mp3');
  static Future<void> playPlace() => _fire('sounds/card_deal.mp3');
  static Future<void> playRemove() => _fire('sounds/card_deal.mp3');

  /// 创建一个一次性 [AudioPlayer]，播完自动释放。
  static Future<void> _fire(String asset) async {
    if (!AppSettings.soundEnabled) return;
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      unawaited(player.onPlayerComplete.first.then((_) => player?.dispose()));
      await player.play(AssetSource(asset));
    } catch (e) {
      player?.dispose();
      developer.log('CardSounds: $e');
    }
  }

  // ============================================================
  //  一次性事件：同一时间只播一次，跳过重复触发
  // ============================================================

  static Future<void> playShoot() => _playOnce(_shootPlayer, 'sounds/shoot.mp3');
  static Future<void> playHomerun() => _playOnce(_homerunPlayer, 'sounds/homerun.mp3');

  static Future<void> _playOnce(AudioPlayer player, String asset) async {
    if (!AppSettings.soundEnabled) return;
    try {
      if (player.state == PlayerState.playing) return;
      await player.play(AssetSource(asset));
    } catch (e) {
      developer.log('CardSounds: $e');
    }
  }

  /// 播一次 shoot 音效（新 player，可重叠）。
  static void playShootEach() => _fireVoid('sounds/shoot.mp3');
  /// 播一次 homerun 音效（新 player，可重叠）。
  static void playHomerunEach() => _fireVoid('sounds/homerun.mp3');

  static void _fireVoid(String asset) {
    if (!AppSettings.soundEnabled) return;
    final player = AudioPlayer();
    unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
    player.play(AssetSource(asset)).catchError((_) => player.dispose());
  }
}
