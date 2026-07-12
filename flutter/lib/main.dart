import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/cards_app.dart';
import 'src/app/game_module.dart';
import 'src/backend/app_settings.dart';
import 'src/backend/stats_tracker.dart';
import 'src/models/card_model.dart';
import 'src/games/thirteen/thirteen_page.dart';
import 'src/games/thirteen/widgets/thirteen_lobby.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android：锁定横屏，禁用竖屏
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  await AppSettings.loadFromDisk();
  StatsTracker.instance.init();

  // Android：预加载 ONNX Runtime 原生库（先加载运行时，再加载封装层）
  if (Platform.isAndroid) {
    try {
      DynamicLibrary.open('libonnxruntime.so');
      DynamicLibrary.open('libonnx_thirteen.so');
      debugPrint('onnx: native libs pre-loaded on Android');
    } catch (e) {
      debugPrint('onnx: pre-load failed, will use native fallback: $e');
    }
  }

  final module = GameModule(
    id: 'thirteen',
    title: '十三水',
    subtitle: '四人十三水，本地理牌',
    previewCards: [
      PlayingCard.standard(51),
      PlayingCard.standard(50),
      PlayingCard.standard(47),
      PlayingCard.standard(42),
    ],
    playerCountOptions: [4],
    defaultPlayerCount: 4,
    builder: (_, pc) => ThirteenPage(playerCount: pc),
  );

  runApp(CardsApp(home: ThirteenLobby(module: module)));
}
