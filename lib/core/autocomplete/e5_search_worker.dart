import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import 'e5_tokenizer.dart';
import 'e5_vector_index.dart';

/// Owns model, tokenizer and vector memory away from the Flutter UI isolate.
void e5SearchWorker((SendPort, String) arguments) async {
  final (reply, directory) = arguments;
  OrtSession? session;
  final inbox = ReceivePort();
  try {
    final manifest =
        jsonDecode(File('$directory/manifest.json').readAsStringSync()) as Map;
    final dimension = manifest['dimensions'] as int;
    final tags =
        jsonDecode(File('$directory/tags.json').readAsStringSync()) as List;
    if (dimension != 384 || tags.length != manifest['count']) {
      throw const FormatException('E5 vector pack dimensions do not match');
    }
    final index = _loadVectorIndex(directory, dimension, tags);
    if (index.viewCount != manifest['views']) {
      throw const FormatException('E5 view count does not match the manifest');
    }
    final tokenizer = E5Tokenizer(
      File('$directory/tokenizer.json').readAsStringSync(),
    );
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(2)
      ..setInterOpNumThreads(1);
    try {
      session = Platform.isWindows
          ? OrtSession.fromBuffer(
              File('$directory/model.onnx').readAsBytesSync(),
              options,
            )
          : OrtSession.fromFile(File('$directory/model.onnx'), options);
    } finally {
      options.release();
    }
    reply.send(inbox.sendPort);
    await for (final message in inbox) {
      if (message == null) break;
      final request = message as List;
      final resultPort = request[0] as SendPort;
      try {
        final ids = tokenizer.encodeQuery(request[1] as String);
        final inputs = {
          'token_type_ids': OrtValueTensor.createTensorWithDataList(
            Int64List(ids.length),
            [1, ids.length],
          ),
          'input_ids': OrtValueTensor.createTensorWithDataList(
            Int64List.fromList(ids),
            [1, ids.length],
          ),
          'attention_mask': OrtValueTensor.createTensorWithDataList(
            Int64List.fromList(List.filled(ids.length, 1)),
            [1, ids.length],
          ),
        };
        final runOptions = OrtRunOptions();
        List<OrtValue?>? outputs;
        final embedding = Float32List(dimension);
        try {
          outputs = session.run(runOptions, inputs);
          final hidden = (outputs.first!.value as List).first as List;
          for (final token in hidden) {
            final values = token as List;
            for (var d = 0; d < dimension; d++) {
              embedding[d] += (values[d] as num).toDouble() / ids.length;
            }
          }
        } finally {
          for (final output in outputs ?? <OrtValue?>[]) {
            output?.release();
          }
          for (final input in inputs.values) {
            input.release();
          }
          runOptions.release();
        }
        var norm = 0.0;
        for (final value in embedding) {
          norm += value * value;
        }
        norm = math.sqrt(norm);
        if (!norm.isFinite || norm == 0) {
          throw StateError('Invalid E5 embedding');
        }
        for (var d = 0; d < dimension; d++) {
          embedding[d] /= norm;
        }
        final best = index.search(embedding, (request[2] as int).clamp(1, 50));
        resultPort.send([
          for (final (tag, score) in best)
            [...(tags[tag] as List).take(3), score],
        ]);
      } catch (error) {
        resultPort.send(error.toString());
      }
    }
  } catch (error) {
    reply.send(error.toString());
  } finally {
    inbox.close();
    await session?.release();
  }
}

/// Keeps the raw int8 bytes local to this call so they can be collected as
/// soon as the rows are expanded into the index.
E5VectorIndex _loadVectorIndex(String directory, int dimension, List tags) {
  final scaleBytes = ByteData.sublistView(
    File('$directory/scales.f32').readAsBytesSync(),
  );
  if (scaleBytes.lengthInBytes % 4 != 0) {
    throw const FormatException('E5 scale file is truncated');
  }
  final scales = Float32List(scaleBytes.lengthInBytes ~/ 4);
  for (var row = 0; row < scales.length; row++) {
    scales[row] = scaleBytes.getFloat32(row * 4, Endian.little);
  }
  return E5VectorIndex.fromQuantized(
    dimension: dimension,
    values: Int8List.sublistView(
      File('$directory/vectors.i8').readAsBytesSync(),
    ),
    scales: scales,
    viewCounts: [for (final row in tags) (row as List)[3] as int],
  );
}
