import 'dart:convert';
import 'dart:typed_data';

/// 在 base64 字符串和 Float32List 之间编解码。
///
/// 用于 ONNX 推理进程与 Flutter 主进程之间的 IPC 数据传递。
/// 两端（onnx_worker_client.dart 和 tool/onnx_worker.dart）共用此实现。

Float32List decodeFloat32(String encoded) {
  final bytes = Uint8List.fromList(base64Decode(encoded));
  return Float32List.view(bytes.buffer, 0, bytes.lengthInBytes ~/ 4);
}

String encodeFloat32(Float32List values) => base64Encode(Uint8List.view(
      values.buffer,
      values.offsetInBytes,
      values.lengthInBytes,
    ));
