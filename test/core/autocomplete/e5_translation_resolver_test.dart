import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/e5_translation_resolver.dart';

void main() {
  test(
    'existing labels support English tags and reuse the lightweight cache',
    () async {
      var loads = 0;
      final resolver = E5TranslationResolver(
        loadLabels: () async {
          loads++;
          return '[["no_socks",6326,"未穿袜"],["no-show_socks",127,"船袜"],["empty",0,""]]';
        },
      );
      expect(
        await resolver.resolve([
          'no_socks',
          'no-show_socks',
          'empty',
          'missing',
        ], locale: 'zh-CN'),
        {'no_socks': '未穿袜', 'no-show_socks': '船袜'},
      );
      expect(await resolver.resolve(['no_socks'], locale: 'zh-CN'), {
        'no_socks': '未穿袜',
      });
      expect(loads, 1);
    },
  );

  test('non-Chinese locale and empty requests do not load assets', () async {
    final resolver = E5TranslationResolver(
      loadLabels: () => throw StateError('must not load'),
    );
    expect(await resolver.resolve(['no_socks'], locale: 'en-US'), isEmpty);
    expect(await resolver.resolve([], locale: 'zh-CN'), isEmpty);
  });

  test('failed asset load can be retried', () async {
    var loads = 0;
    final resolver = E5TranslationResolver(
      loadLabels: () async {
        if (++loads == 1) throw StateError('unavailable');
        return '[["no_socks",1,"未穿袜"]]';
      },
    );
    await expectLater(
      resolver.resolve(['no_socks'], locale: 'zh-CN'),
      throwsStateError,
    );
    expect(await resolver.resolve(['no_socks'], locale: 'zh-CN'), {
      'no_socks': '未穿袜',
    });
  });
}
