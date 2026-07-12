import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/src/backend/float32_codec.dart';
import '../lib/src/backend/onnx_helper.dart';

Future<void> main() async {
  try {
    await OnnxRuntime.instance.init();
    stdout.writeln(jsonEncode({'ready': true}));
  } catch (error, stack) {
    stdout.writeln(jsonEncode({'ready': false, 'error': '$error'}));
    stderr.writeln(stack);
    exitCode = 2;
    return;
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    Object? id;
    try {
      final request = jsonDecode(line) as Map<String, dynamic>;
      id = request['id'];
      if (request['command'] == 'shutdown') break;
      final inputs = <String, Float32List>{};
      final shapes = <String, List<int>>{};
      for (final entry in (request['inputs'] as Map<String, dynamic>).entries) {
        final tensor = entry.value as Map<String, dynamic>;
        inputs[entry.key] = decodeFloat32(tensor['data'] as String);
        shapes[entry.key] = (tensor['shape'] as List).cast<int>();
      }
      final outputs = <String, Float32List>{};
      for (final entry
          in (request['outputs'] as Map<String, dynamic>).entries) {
        outputs[entry.key] = Float32List((entry.value as num).toInt());
      }
      OnnxRuntime.instance.run(
        request['model'] as String,
        inputs,
        shapes,
        outputs,
      );
      stdout.writeln(jsonEncode({
        'id': id,
        'outputs': {
          for (final entry in outputs.entries)
            entry.key: encodeFloat32(entry.value),
        },
      }));
    } catch (error, stack) {
      stderr.writeln(stack);
      stdout.writeln(jsonEncode({'id': id, 'error': '$error'}));
    }
  }
  OnnxRuntime.instance.dispose();
}
