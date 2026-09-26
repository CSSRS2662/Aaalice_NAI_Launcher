import 'dart:convert';
import 'dart:io';

import 'package:nai_launcher/core/autocomplete/e5_tokenizer.dart';

void main() {
  final tokenizer = E5Tokenizer(
    File('tool/.tmp/semantic-search/tokenizer.json').readAsStringSync(),
  );
  final fixtures =
      jsonDecode(
            File(
              'tool/.tmp/semantic-search/e5-tokenizer-fixtures.json',
            ).readAsStringSync(),
          )
          as List;
  var failed = 0;
  for (final fixture in fixtures) {
    final actual = tokenizer.encodeQuery(fixture['query'] as String);
    if (jsonEncode(actual) != jsonEncode(fixture['ids'])) {
      failed++;
      if (failed <= 10) {
        stdout.writeln(
          jsonEncode({
            'query': fixture['query'],
            'expected': fixture['ids'],
            'actual': actual,
          }),
        );
      }
    }
  }
  stdout.writeln(
    'Tokenizer parity: ${fixtures.length - failed}/${fixtures.length}',
  );
  if (failed > 0) exitCode = 1;
}
