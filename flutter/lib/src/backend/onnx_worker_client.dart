import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'float32_codec.dart';

class OnnxWorkerClient {
  OnnxWorkerClient._();

  static final instance = OnnxWorkerClient._();

  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  final Map<int, Completer<Map<String, Float32List>>> _requests = {};
  Completer<void>? _ready;
  Future<void> _queue = Future.value();
  int _nextId = 0;

  bool get isReady => _process != null && (_ready?.isCompleted ?? false);

  Future<void> start() async {
    // 安卓不支持子进程，ONNX 走直调
    if (Platform.isAndroid) return;
    if (_process != null) return _ready!.future;
    final worker = _workerPath();
    if (!File(worker).existsSync()) {
      throw StateError('ONNX worker not found: $worker');
    }
    _ready = Completer<void>();
    final process = await Process.start(
      worker,
      const [],
      workingDirectory: _workerWorkingDirectory(worker),
      mode: ProcessStartMode.normal,
    );
    _process = process;
    process.stderr.transform(utf8.decoder).listen((message) {
      if (Platform.environment['CARDS_ONNX_LOG'] == '1') {
        stderr.write(message);
      }
    });
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _failAll);
    process.exitCode.then((code) {
      if (_process == process) {
        _failAll(StateError('ONNX worker exited with code $code'));
        _process = null;
      }
    });
    return _ready!.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, Float32List>> run({
    required String model,
    required Map<String, Float32List> inputs,
    required Map<String, List<int>> inputShapes,
    required Map<String, int> outputSizes,
  }) {
    final completer = Completer<Map<String, Float32List>>();
    _queue = _queue.then((_) async {
      try {
        await start();
        final id = ++_nextId;
        _requests[id] = completer;
        _process!.stdin.writeln(jsonEncode({
          'id': id,
          'model': model,
          'inputs': {
            for (final entry in inputs.entries)
              entry.key: {
                'shape': inputShapes[entry.key],
                'data': encodeFloat32(entry.value),
              },
          },
          'outputs': outputSizes,
        }));
        await _process!.stdin.flush();
        await completer.future.timeout(const Duration(seconds: 15));
      } catch (error, stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      }
    }).catchError((_) {/* 确保 _queue 不会因错误而中断后续请求 */});
    return completer.future;
  }

  void _handleLine(String line) {
    final response = jsonDecode(line) as Map<String, dynamic>;
    if (response.containsKey('ready')) {
      if (response['ready'] == true) {
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      } else {
        _ready?.completeError(StateError('${response['error']}'));
      }
      return;
    }
    final id = (response['id'] as num?)?.toInt();
    final completer = id == null ? null : _requests.remove(id);
    if (completer == null) return;
    if (response['error'] case final error?) {
      completer.completeError(StateError('$error'));
      return;
    }
    final outputs = <String, Float32List>{};
    for (final entry in (response['outputs'] as Map<String, dynamic>).entries) {
      outputs[entry.key] = decodeFloat32(entry.value as String);
    }
    completer.complete(outputs);
  }

  void _failAll(Object error, [StackTrace? stack]) {
    if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error, stack);
    for (final completer in _requests.values) {
      if (!completer.isCompleted) completer.completeError(error, stack);
    }
    _requests.clear();
  }

  Future<void> dispose() async {
    final process = _process;
    _process = null;
    if (process != null) {
      process.stdin.writeln(jsonEncode({'command': 'shutdown'}));
      await process.stdin.flush();
      await process.stdin.close();
    }
    await _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _ready = null;
  }

  static String _workerPath() {
    if (Platform.environment['CARDS_ONNX_WORKER'] case final path?) {
      return path;
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final deployed = '$exeDir\\onnx_worker.exe';
    if (File(deployed).existsSync()) return deployed;
    return '${Directory.current.path}\\runtime\\onnx_worker.exe';
  }

  static String _workerWorkingDirectory(String worker) {
    final projectModels = Directory(
      '${Directory.current.path}\\assets\\models',
    );
    if (projectModels.existsSync()) return Directory.current.path;
    return File(worker).parent.path;
  }
}
