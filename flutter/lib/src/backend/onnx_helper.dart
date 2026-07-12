import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void _onnxLog(String message) {
  if (Platform.environment['CARDS_ONNX_LOG'] == '1') stderr.writeln(message);
}

// ============================================================
//  ONNX Runtime C 函数类型定义 (加载 onnx_thirteen.dll)
// ============================================================

typedef _OhInitC = Int32 Function();
typedef _OhInitDart = int Function();

typedef _OhCreateEnvC = Pointer<Void> Function();
typedef _OhCreateEnvDart = Pointer<Void> Function();

typedef _OhReleaseEnvC = Void Function(Pointer<Void>);
typedef _OhReleaseEnvDart = void Function(Pointer<Void>);

typedef _OhLastErrorC = Pointer<Utf8> Function();
typedef _OhLastErrorDart = Pointer<Utf8> Function();

typedef _OhCreateSessionC = Pointer<Void> Function(
    Pointer<Void> env, Pointer<Utf8> modelPath);
typedef _OhCreateSessionDart = Pointer<Void> Function(
    Pointer<Void> env, Pointer<Utf8> modelPath);

typedef _OhReleaseSessionC = Void Function(Pointer<Void>);
typedef _OhReleaseSessionDart = void Function(Pointer<Void>);

typedef _OhRunC = Int32 Function(
    Pointer<Void> session,
    Pointer<Pointer<Utf8>> inputNames,
    Int32 nInputs,
    Pointer<Pointer<Float>> inputData,
    Pointer<Pointer<Int64>> inputShapes,
    Pointer<Int32> inputNdims,
    Pointer<Pointer<Utf8>> outputNames,
    Int32 nOutputs,
    Pointer<Pointer<Float>> outputData,
    Pointer<Int32> outputSizes);
typedef _OhRunDart = int Function(
    Pointer<Void> session,
    Pointer<Pointer<Utf8>> inputNames,
    int nInputs,
    Pointer<Pointer<Float>> inputData,
    Pointer<Pointer<Int64>> inputShapes,
    Pointer<Int32> inputNdims,
    Pointer<Pointer<Utf8>> outputNames,
    int nOutputs,
    Pointer<Pointer<Float>> outputData,
    Pointer<Int32> outputSizes);

// ============================================================
//  十三水编码函数类型定义
// ============================================================

typedef _OhTcEncodeHandC = Int32 Function(
    Pointer<Int32> hand13, Pointer<Float> outTokens);
typedef _OhTcEncodeHandDart = int Function(
    Pointer<Int32> hand13, Pointer<Float> outTokens);

typedef _OhTcEncodeCombosC = Int32 Function(
    Pointer<Int32> hand13,
    Pointer<Void> dfsResult,
    Pointer<Float> outFeatures,
    Pointer<Float> outMask);
typedef _OhTcEncodeCombosDart = int Function(
    Pointer<Int32> hand13,
    Pointer<Void> dfsResult,
    Pointer<Float> outFeatures,
    Pointer<Float> outMask);

typedef _OhTcAttackC = Float Function(Pointer<Void> combo);
typedef _OhTcAttackDart = double Function(Pointer<Void> combo);

typedef _OhTcDefenseC = Float Function(Pointer<Void> combo);
typedef _OhTcDefenseDart = double Function(Pointer<Void> combo);

typedef _OhSampleC = Int32 Function(
    Pointer<Float> logits, Int32 n, Double temperature);
typedef _OhSampleDart = int Function(
    Pointer<Float> logits, int n, double temperature);

typedef _OhTcRecommendC = Int32 Function(
    Pointer<Int32> hand13,
    Pointer<Void> dfsResult,
    Pointer<Void> session,
    Double temperature,
    Double aggression,
    Pointer<Int32> outBestIdx,
    Pointer<Float> outLogits);
typedef _OhTcRecommendDart = int Function(
    Pointer<Int32> hand13,
    Pointer<Void> dfsResult,
    Pointer<Void> session,
    double temperature,
    double aggression,
    Pointer<Int32> outBestIdx,
    Pointer<Float> outLogits);

typedef _OhTcSelectC = Int32 Function(
    Pointer<Void> dfsResult,
    Pointer<Float> logits,
    Double temperature,
    Double aggression,
    Pointer<Int32> outBestIdx);
typedef _OhTcSelectDart = int Function(
    Pointer<Void> dfsResult,
    Pointer<Float> logits,
    double temperature,
    double aggression,
    Pointer<Int32> outBestIdx);

// ============================================================
//  OnnxRuntime — ONNX 推理引擎核心
// ============================================================

class OnnxRuntime {
  static final OnnxRuntime instance = OnnxRuntime._();

  DynamicLibrary? _lib;
  Pointer<Void>? _env;
  bool _initialized = false;

  // 已加载的模型会话 <modelName, session>
  final Map<String, Pointer<Void>> _sessions = {};

  OnnxRuntime._();

  String get _dllPath {
    // Android：从 jniLibs 加载
    if (Platform.isAndroid) return 'libonnx_thirteen.so';
    // Windows/macOS/Linux
    if (Platform.environment['CARDS_ONNX_HELPER'] case final env?) return env;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exePath = '$exeDir\\onnx_thirteen.dll';
      if (File(exePath).existsSync()) return exePath;
    } catch (_) {}
    final devPath = '${Directory.current.path}\\runtime\\onnx_thirteen.dll';
    if (File(devPath).existsSync()) return devPath;
    return 'onnx_thirteen.dll';
  }

  // 安卓：模型从 assets 解压到缓存目录
  String? _androidModelDir;
  String get _modelDir {
    if (_androidModelDir != null) return _androidModelDir!;
    if (Platform.environment['ONNX_MODEL_DIR'] case final env?) return env;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final deployPath = '$exeDir\\models';
      if (Directory(deployPath).existsSync()) return deployPath;
    } catch (_) {}
    final devPath = '${Directory.current.path}\\assets\\models';
    if (Directory(devPath).existsSync()) return devPath;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return '$exeDir\\runtime\\models';
    } catch (_) {
      return '${Directory.current.path}\\assets\\models';
    }
  }

  /// 初始化 ONNX Runtime 环境，加载所有模型
  Future<void> init() async {
    if (_initialized) return;

    // Android：原生库已在 main() 中预加载，这里只初始化 ORT 和加载模型
    if (Platform.isAndroid) {
      try {
        _lib = DynamicLibrary.open('libonnx_thirteen.so');
        final initFn = _lib!.lookupFunction<_OhInitC, _OhInitDart>('oh_init');
        if (initFn() != 0) throw Exception('oh_init failed');
        final createEnv =
            _lib!.lookupFunction<_OhCreateEnvC, _OhCreateEnvDart>('oh_create_env');
        _env = createEnv();
        if (_env == nullptr) throw Exception('oh_create_env failed');

        final appDocDir = await getApplicationCacheDirectory()
            .timeout(const Duration(seconds: 5));
        final modelDir = Directory('${appDocDir.path}/models');
        if (!await modelDir.exists()) await modelDir.create(recursive: true);
        final modelFile = File('${modelDir.path}/thirteen_ranker.onnx');
        if (!await modelFile.exists()) {
          final data = await rootBundle.load('assets/models/thirteen_ranker.onnx');
          await modelFile.writeAsBytes(data.buffer.asUint8List());
        }
        _androidModelDir = modelDir.path;

        if (await Directory(_androidModelDir!).exists()) {
          final files = Directory(_androidModelDir!).listSync()
              .where((f) => f.path.endsWith('.onnx'));
          for (final f in files) {
            final name = f.path.split('\\').last.split('/').last;
            _loadSession(name, f.path);
          }
          _onnxLog('onnx: loaded ${_sessions.length} models (Android)');
        }
        _initialized = true;
        return;
      } catch (error) {
        _onnxLog('onnx: Android init failed: $error');
        rethrow;
      }
    }

    // Windows/macOS/Linux
    final helperPath = _dllPath;
    final runtimePath = Platform.environment['CARDS_ONNX_RUNTIME'] ??
        '${File(helperPath).parent.path}\\onnxruntime.dll';
    if (File(runtimePath).existsSync()) {
      DynamicLibrary.open(runtimePath);
    }
    _lib = DynamicLibrary.open(helperPath);
    _onnxLog('onnx: loaded onnx_thirteen.dll');

    // init
    final initFn = _lib!.lookupFunction<_OhInitC, _OhInitDart>('oh_init');
    final rc = initFn();
    if (rc != 0) throw Exception('oh_init failed: $rc');
    _onnxLog('onnx: init OK');

    // create env
    final createEnv =
        _lib!.lookupFunction<_OhCreateEnvC, _OhCreateEnvDart>('oh_create_env');
    _env = createEnv();
    if (_env == nullptr) throw Exception('oh_create_env failed');
    _onnxLog('onnx: env created');

    // 加载所有模型
    final modelDir = Directory(_modelDir);
    if (!modelDir.existsSync()) {
      throw Exception('Model directory not found: $_modelDir');
    }

    final files = modelDir.listSync().where((f) => f.path.endsWith('.onnx'));
    for (final f in files) {
      final name = f.path.split('\\').last;
      _loadSession(name, f.path);
    }
    _onnxLog('onnx: loaded ${_sessions.length} models');
    _initialized = true;
  }

  void _loadSession(String name, String path) {
    final createSession = _lib!
        .lookupFunction<_OhCreateSessionC, _OhCreateSessionDart>(
            'oh_create_session');
    final lastError =
        _lib!.lookupFunction<_OhLastErrorC, _OhLastErrorDart>('oh_last_error');
    final modelPath = path.toNativeUtf8();
    final session = createSession(_env!, modelPath);
    calloc.free(modelPath);
    if (session == nullptr) {
      final err = lastError().toDartString();
      throw Exception('Failed to create session for $name: $err');
    }
    _sessions[name] = session;
    _onnxLog('onnx: loaded $name');
  }

  // ============================================================
  //  FFI 内存分配辅助 — 自动跟踪指针，避免重复 allocate/free 模板代码
  // ============================================================

  /// 分配 C 字符串数组。返回 (array, ptrs) 用于调用和清理。
  static ({Pointer<Pointer<Utf8>> array, List<Pointer<Utf8>> ptrs}) _strArray(
      List<String> strs) {
    final ptrs = strs.map((s) => s.toNativeUtf8()).toList();
    final array = calloc<Pointer<Utf8>>(strs.length);
    for (var i = 0; i < strs.length; i++) array[i] = ptrs[i];
    return (array: array, ptrs: ptrs);
  }

  static void _freeStrArray(
      ({Pointer<Pointer<Utf8>> array, List<Pointer<Utf8>> ptrs}) b) {
    for (final p in b.ptrs) calloc.free(p);
    calloc.free(b.array);
  }

  /// 分配 float 数据数组。返回 (array, ptrs)。
  static ({Pointer<Pointer<Float>> array, List<Pointer<Float>> ptrs})
      _floatArray(List<Float32List> datas) {
    final ptrs = <Pointer<Float>>[];
    final array = calloc<Pointer<Float>>(datas.length);
    for (var i = 0; i < datas.length; i++) {
      final ptr = calloc<Float>(datas[i].length);
      ptr.asTypedList(datas[i].length).setAll(0, datas[i]);
      array[i] = ptr;
      ptrs.add(ptr);
    }
    return (array: array, ptrs: ptrs);
  }

  static void _freeFloatArray(
      ({Pointer<Pointer<Float>> array, List<Pointer<Float>> ptrs}) b) {
    for (final p in b.ptrs) calloc.free(p);
    calloc.free(b.array);
  }

  /// 分配 int64 形状数组。返回 (array, ndims, ptrs)。
  static ({
    Pointer<Pointer<Int64>> array,
    Pointer<Int32> ndims,
    List<Pointer<Int64>> ptrs,
  }) _int64Array(List<List<int>> shapes) {
    final ptrs = <Pointer<Int64>>[];
    final array = calloc<Pointer<Int64>>(shapes.length);
    final ndims = calloc<Int32>(shapes.length);
    for (var i = 0; i < shapes.length; i++) {
      ndims[i] = shapes[i].length;
      final shapePtr = calloc<Int64>(shapes[i].length);
      for (var j = 0; j < shapes[i].length; j++) shapePtr[j] = shapes[i][j];
      array[i] = shapePtr;
      ptrs.add(shapePtr);
    }
    return (array: array, ndims: ndims, ptrs: ptrs);
  }

  static void _freeInt64Array(
      ({
        Pointer<Pointer<Int64>> array,
        Pointer<Int32> ndims,
        List<Pointer<Int64>> ptrs,
      }) b) {
    for (final p in b.ptrs) calloc.free(p);
    calloc.free(b.array);
    calloc.free(b.ndims);
  }

  /// 运行推理
  /// [modelName] 模型文件名 (如 thirteen_ranker.onnx)
  /// [inputs] 输入张量: 名称 -> Float32List
  /// [inputShapes] 输入形状: 名称 -> shape
  /// [outputs] 输出定义: 名称 -> Float32List (预分配)
  void run(
    String modelName,
    Map<String, Float32List> inputs,
    Map<String, List<int>> inputShapes,
    Map<String, Float32List> outputs,
  ) {
    final session = _sessions[modelName];
    if (session == null) throw Exception('Model not loaded: $modelName');
    final runFn = _lib!.lookupFunction<_OhRunC, _OhRunDart>('oh_run');

    final inputNames = inputs.keys.toList();
    final outputNames = outputs.keys.toList();
    final nInputs = inputNames.length;
    final nOutputs = outputNames.length;

    // 分配所有 native 内存
    final inNames = _strArray(inputNames);
    final inData = _floatArray(inputNames.map((n) => inputs[n]!).toList());
    final inShapes =
        _int64Array(inputNames.map((n) => inputShapes[n]!).toList());
    final outNames = _strArray(outputNames);
    final outData = _floatArray(outputNames.map((n) => outputs[n]!).toList());
    final outSizes = calloc<Int32>(nOutputs);
    for (var i = 0; i < nOutputs; i++) {
      outSizes[i] = outputs[outputNames[i]]!.length;
    }

    // 调用 oh_run
    final rc = runFn(
      session,
      inNames.array,
      nInputs,
      inData.array,
      inShapes.array,
      inShapes.ndims,
      outNames.array,
      nOutputs,
      outData.array,
      outSizes,
    );

    // 将输出从 native 缓冲区复制回 Dart 的 Float32List
    if (rc == 0) {
      for (var i = 0; i < nOutputs; i++) {
        final data = outputs[outputNames[i]]!;
        data.setAll(0, outData.ptrs[i].asTypedList(data.length));
      }
    }

    // 清理
    _freeStrArray(inNames);
    _freeFloatArray(inData);
    _freeInt64Array(inShapes);
    _freeStrArray(outNames);
    _freeFloatArray(outData);
    calloc.free(outSizes);

    if (rc != 0) throw Exception('oh_run failed: $rc');
  }

  // ============================================================
  //  特征编码 — 十三水 (C 实现，替换 tc_encoder.dart)
  // ============================================================

  static const int tcCardDim = 17;
  static const int tcComboDim = 74;
  static const int tcMaxCombos = 128;

  /// 编码手牌 13 张 → (13, 17) one-hot
  void tcEncodeHand(Pointer<Int32> hand13, Pointer<Float> outTokens) {
    final fn = _lib!.lookupFunction<_OhTcEncodeHandC, _OhTcEncodeHandDart>(
        'oh_tc_encode_hand');
    fn(hand13, outTokens);
  }

  /// 批量编码组合 → (128, 74) + (128,) mask
  int tcEncodeCombos(Pointer<Int32> hand13, Pointer<Void> dfsResult,
      Pointer<Float> outFeatures, Pointer<Float> outMask) {
    final fn = _lib!.lookupFunction<_OhTcEncodeCombosC, _OhTcEncodeCombosDart>(
        'oh_tc_encode_combos');
    return fn(hand13, dfsResult, outFeatures, outMask);
  }

  double tcAttackPotential(Pointer<Void> combo) {
    final fn = _lib!.lookupFunction<_OhTcAttackC, _OhTcAttackDart>(
        'oh_tc_attack_potential');
    return fn(combo);
  }

  double tcDefenseStability(Pointer<Void> combo) {
    final fn = _lib!.lookupFunction<_OhTcDefenseC, _OhTcDefenseDart>(
        'oh_tc_defense_stability');
    return fn(combo);
  }

  int sample(Pointer<Float> logits, int n, double temperature) {
    final fn = _lib!.lookupFunction<_OhSampleC, _OhSampleDart>('oh_sample');
    return fn(logits, n, temperature);
  }

  /// 一键推荐十三水 (内部完成编码+ONNX推理+温度采样)
  /// 返回 0=正常, 1=特殊牌型, <0=错误
  int tcRecommend(
    Pointer<Int32> hand13,
    Pointer<Void> dfsResult,
    String modelName,
    double temperature,
    double aggression,
    Pointer<Int32> outBestIdx,
    Pointer<Float> outLogits,
  ) {
    final session = _sessions[modelName];
    if (session == null) throw Exception('Model not loaded: $modelName');
    final fn = _lib!
        .lookupFunction<_OhTcRecommendC, _OhTcRecommendDart>('oh_tc_recommend');
    return fn(hand13, dfsResult, session, temperature, aggression, outBestIdx,
        outLogits);
  }

  int tcSelect(
    Pointer<Void> dfsResult,
    Pointer<Float> logits,
    double temperature,
    double aggression,
    Pointer<Int32> outBestIdx,
  ) {
    final fn = _lib!.lookupFunction<_OhTcSelectC, _OhTcSelectDart>(
      'oh_tc_select',
    );
    return fn(dfsResult, logits, temperature, aggression, outBestIdx);
  }

  /// 获取指定模型的会话指针 (用于直接操作)
  Pointer<Void>? session(String modelName) => _sessions[modelName];

  /// 检查模型是否已加载
  bool hasModel(String modelName) => _sessions.containsKey(modelName);

  void dispose() {
    final releaseSession =
        _lib?.lookupFunction<_OhReleaseSessionC, _OhReleaseSessionDart>(
            'oh_release_session');
    for (final s in _sessions.values) {
      releaseSession?.call(s);
    }
    _sessions.clear();

    if (_env != null) {
      final releaseEnv = _lib!
          .lookupFunction<_OhReleaseEnvC, _OhReleaseEnvDart>('oh_release_env');
      releaseEnv(_env!);
      _env = nullptr;
    }
    _initialized = false;
    _onnxLog('onnx: disposed');
  }
}
