import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_v2/onnxruntime_v2.dart';

import 'e5_tokenizer.dart';

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
    final bytes = File('$directory/vectors.f32').readAsBytesSync();
    final vectors = Float32List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.length ~/ 4,
    );
    if (dimension != 384 ||
        tags.length != manifest['count'] ||
        vectors.length != tags.length * dimension) {
      throw const FormatException('E5 vector pack dimensions do not match');
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
        final best = <(int, double)>[];
        final limit = (request[2] as int).clamp(1, 50);
        for (var row = 0; row < tags.length; row++) {
          var score = 0.0;
          final offset = row * dimension;
          for (var d = 0; d < dimension; d++) {
            score += vectors[offset + d] * embedding[d];
          }
          if (best.length == limit && score <= best.last.$2) continue;
          final position = best.indexWhere((item) => score > item.$2);
          best.insert(position < 0 ? best.length : position, (row, score));
          if (best.length > limit) best.removeLast();
        }
        resultPort.send([
          for (final hit in best) [...tags[hit.$1] as List, hit.$2],
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
