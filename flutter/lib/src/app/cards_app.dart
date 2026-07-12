import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/onnx_helper.dart';
import '../backend/onnx_worker_client.dart';
import '../theme/app_theme.dart';

/// 通用 App 壳 — 负责 ONNX 预加载、主题、MediaQuery 钳位。
/// 不依赖任何游戏目录，通过 [home] 接受外部传入的首页。
class CardsApp extends StatefulWidget {
  const CardsApp({
    super.key,
    required this.home,
  });

  final Widget home;

  @override
  State<CardsApp> createState() => _CardsAppState();
}

class _CardsAppState extends State<CardsApp> {
  bool _ready = false;
  Object? _startupError;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    setState(() {
      _ready = false;
      _startupError = null;
    });
    try {
      await OnnxRuntime.instance.init();
      try {
        await OnnxWorkerClient.instance.start();
      } catch (error) {
        debugPrint(
            'ONNX worker preload failed; native fallback remains: $error');
      }
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error) {
      debugPrint('AI preload failed: $error');
      if (!mounted) return;
      setState(() => _startupError = error);
    }
  }

  @override
  void dispose() {
    unawaited(OnnxWorkerClient.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startup = _startupError == null
        ? const _StartupGate()
        : _StartupGate(error: _startupError, onRetry: _preload);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Local Cards',
      theme: buildCardsTheme(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.88,
              maxScaleFactor: 1.08,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _ready ? widget.home : startup,
    );
  }
}

class _StartupGate extends StatelessWidget {
  const _StartupGate({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return Scaffold(
      body: Container(
        color: AppColors.appBg,
        child: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  failed ? '启动失败' : '正在启动',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: AppTextTokens.of(context).lg,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (failed) ...[
                  Text(
                    '$error',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: AppTextTokens.of(context).sm,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  const LinearProgressIndicator(minHeight: 3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
