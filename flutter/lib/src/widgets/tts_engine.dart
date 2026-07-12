/// 文字转语音引擎 — 使用 flutter_tts 包调用原生 Windows SAPI。
///
/// 内部使用 Future 链串行化所有 [speak] 调用，避免 Windows SAPI
/// 同步 Speak() 在快速连续调用时丢弃语音。
library;

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../backend/app_settings.dart';

/// 文字转语音引擎。
class TtsEngine {
  TtsEngine._();

  static FlutterTts? _tts;
  static bool _ready = false;

  /// Future 链：确保对 flutter_tts 的 speak 调用始终串行执行，
  /// 前一条播完才播下一条。多个 [unawaited] 调用不会并发冲突。
  static Future<void> _previousSpeak = Future.value();

  /// 初始化 TTS 引擎。
  static Future<void> warmup() async {
    if (_ready) return;
    try {
      _tts = FlutterTts();
      await _tts!.setLanguage('zh-CN');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 播报一段文本。
  ///
  /// 内部通过 Future 链串行化 + 500ms 缓冲确保 Windows SAPI
  /// 不会丢弃连续调用。适合快速连续播报（翻牌）。
  /// 调用方 [await] 此方法会等语音 + 缓冲才返回。
  static Future<void> speak(String text) async {
    if (!AppSettings.soundEnabled || text.isEmpty) return;
    await _ensureReady();
    if (_tts == null) return;
    _previousSpeak = _previousSpeak.then((_) async {
      try {
        await _tts!.speak(text);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }).catchError((_) {});
    await _previousSpeak;
  }

  /// 播报并等待 SAPI 确实播完再返回。适合需要精确等待的孤立播报。
  /// 内部使用 [setCompletionHandler] 回调，超时 3 秒保底。
  static Future<void> speakAndWait(String text) async {
    if (!AppSettings.soundEnabled || text.isEmpty) return;
    await _ensureReady();
    if (_tts == null) return;
    _previousSpeak = _previousSpeak.then((_) async {
      try {
        final completer = Completer<void>();
        _tts!.setCompletionHandler(() {
          if (!completer.isCompleted) completer.complete();
        });
        await _tts!.speak(text);
        await completer.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }).catchError((_) {});
    await _previousSpeak;
  }

  /// 依次播报多段文本。
  static Future<void> speakMany(List<String> texts, {int gapMs = 0}) async {
    if (!AppSettings.soundEnabled || texts.isEmpty) return;
    await _ensureReady();
    if (_tts == null) return;
    for (final t in texts) {
      if (t.trim().isEmpty) continue;
      await speak(t);
      if (gapMs > 0) await Future.delayed(Duration(milliseconds: gapMs));
    }
  }

  /// 分离模式播报（退化到普通 [speak]）。
  static Future<void> speakDetached(String text) async {
    await speak(text);
  }

  /// 重置 TTS 引擎：停止当前语音并清空等待链。
  /// 在长段语音播报后调用，防止内部状态堆积导致后续 speak 无声。
  static Future<void> stop() async {
    _previousSpeak = Future.value();
    if (_tts != null) {
      try {
        await _tts!.stop();
      } catch (_) {}
    }
  }

  /// 彻底重建 TTS 引擎，丢弃旧实例创建全新的。
  /// 用于长段语音后需要继续播报的场景。
  static Future<void> recreate() async {
    _previousSpeak = Future.value();
    _ready = false;
    if (_tts != null) {
      try { await _tts!.stop(); } catch (_) {}
    }
    _tts = null;
    await warmup();
  }

  static Future<void> _ensureReady() async {
    if (_ready) return;
    await warmup();
  }
}
