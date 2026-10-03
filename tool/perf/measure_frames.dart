// Frame pacing of the Android app from SurfaceFlinger present timestamps.
//
// Works on release builds, so the installed app and its data stay untouched.
// See tool/perf/README.md for scenarios and how to read the numbers.
//
//   dart run tool/perf/measure_frames.dart <scenario> [label]
//   dart run tool/perf/measure_frames.dart watch <seconds> [label]
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _package = 'com.cssrs2662.aaalicepocket';
final _resultsFile = File('tool/.tmp/perf/results.jsonl');

/// Intervals above this end a continuous run (idle gaps are not jank).
const _runBreakMs = 60.0;

/// SurfaceFlinger keeps only the last 128 frames per layer; at 120 Hz that is
/// about one second, so long captures poll and merge.
const _pollInterval = Duration(milliseconds: 400);

Future<void> main(List<String> args) async {
  if (args.isEmpty || !_scenarios.containsKey(args.first)) {
    stderr.writeln(
      'Usage: dart run tool/perf/measure_frames.dart '
      '<${_scenarios.keys.join('|')}> [label]\n'
      '       dart run tool/perf/measure_frames.dart watch <seconds> [label]',
    );
    exitCode = 64;
    return;
  }
  final device = await _Device.connect();
  await _scenarios[args.first]!(device, args.skip(1).toList());
}

typedef _Scenario = Future<void> Function(_Device device, List<String> args);

final Map<String, _Scenario> _scenarios = {
  'tabs': (device, args) async {
    await device.tapNav('generate');
    await device.tapTab('image', wait: 1000);
    await device.measure('tab_swipe', label: _label(args), repeat: 4, () async {
      await device.swipeHorizontal(toLeft: true);
      await device.swipeHorizontal(toLeft: true);
      await device.swipeHorizontal(toLeft: false);
      await device.swipeHorizontal(toLeft: false);
    });
  },
  'history': (device, args) async {
    await device.tapNav('generate');
    await device.tapTab('history', wait: 1500);
    await device.measure(
      'history_fling_down',
      label: _label(args),
      repeat: 4,
      () => device.fling(up: true),
    );
    await device.measure(
      'history_fling_up',
      label: _label(args),
      repeat: 4,
      () => device.fling(up: false),
    );
  },
  'gallery': (device, args) async {
    await device.tapNav('gallery', wait: 2000);
    await device.measure(
      'gallery_fling_down',
      label: _label(args),
      repeat: 6,
      () => device.fling(up: true),
    );
    await device.measure(
      'gallery_fling_up',
      label: _label(args),
      repeat: 3,
      () => device.fling(up: false),
    );
  },
  'online': (device, args) async {
    await device.tapNav('online', wait: 3000);
    await device.measure(
      'online_fling_down',
      label: _label(args),
      repeat: 5,
      () => device.fling(up: true),
    );
  },
  'watch': (device, args) async {
    final seconds = args.isEmpty ? null : int.tryParse(args.first);
    if (seconds == null || seconds <= 0) {
      stderr.writeln('watch needs a duration in seconds');
      exitCode = 64;
      return;
    }
    stdout.writeln('Recording $seconds s — operate the phone now.');
    await device.measure(
      'watch_${seconds}s',
      label: _label(args.skip(1)),
      () => Future<void>.delayed(Duration(seconds: seconds)),
    );
  },
};

String _label(Iterable<String> args) => args.isEmpty ? 'run' : args.first;

class _Device {
  _Device._(this._layer, this._width, this._height);

  final String _layer;
  final int _width;
  final int _height;

  // Fractions calibrated on a 1440x3168 OnePlus 12; other devices may need
  // their own values.
  static const _tabY = 466 / 3168;
  static const _navY = 3050 / 3168;
  static const _tabX = {
    'image': 182 / 1440,
    'prompt': 450 / 1440,
    'params': 719 / 1440,
    'refs': 983 / 1440,
    'history': 1251 / 1440,
  };
  static const _navX = {
    'generate': 142 / 1440,
    'gallery': 430 / 1440,
    'online': 719 / 1440,
    'library': 1005 / 1440,
    'more': 1292 / 1440,
  };

  static Future<_Device> connect() async {
    final size = RegExp(r'(\d+)x(\d+)').firstMatch(await _shell('wm size'));
    if (size == null) throw StateError('No device: adb shell wm size failed');
    final layers = await _shell('dumpsys SurfaceFlinger --list');
    final layer = RegExp(
      '([0-9a-f]+ SurfaceView\\[${RegExp.escape(_package)}/[^\\]]+\\]'
      '\\(BLAST\\)#\\d+)',
    ).firstMatch(layers);
    if (layer == null) {
      throw StateError('Flutter surface not found; open the app first');
    }
    return _Device._(
      layer.group(1)!,
      int.parse(size.group(1)!),
      int.parse(size.group(2)!),
    );
  }

  Future<void> tapNav(String item, {int wait = 600}) =>
      _tap(_navX[item]!, _navY, wait);

  Future<void> tapTab(String tab, {int wait = 600}) =>
      _tap(_tabX[tab]!, _tabY, wait);

  Future<void> swipeHorizontal({required bool toLeft}) {
    final left = (_width * 0.17).round();
    final right = (_width * 0.8).round();
    final y = (_height * 0.63).round();
    return _swipe(toLeft ? right : left, y, toLeft ? left : right, y, 140, 900);
  }

  Future<void> fling({required bool up}) {
    final x = _width ~/ 2;
    final low = (_height * 0.8).round();
    final high = (_height * 0.27).round();
    return _swipe(x, up ? low : high, x, up ? high : low, 90, 1200);
  }

  Future<void> measure(
    String scenario,
    Future<void> Function() actions, {
    required String label,
    int repeat = 1,
  }) async {
    final runs = <_Stats>[];
    for (var i = 0; i < repeat; i++) {
      await _shell("dumpsys SurfaceFlinger --latency-clear '$_layer'");
      final presents = <int>{};
      var recording = true;
      final poller = () async {
        while (recording) {
          presents.addAll(await _presentTimes());
          await Future<void>.delayed(_pollInterval);
        }
      }();
      await actions();
      recording = false;
      await poller;
      presents.addAll(await _presentTimes());
      final stats = _Stats.of(presents.toList()..sort());
      if (stats == null) continue;
      runs.add(stats);
      stdout.writeln('$scenario#${i + 1}: ${jsonEncode(stats.toJson())}');
    }
    if (runs.isEmpty) {
      stdout.writeln('$scenario: no frames recorded');
      return;
    }
    final summary = {
      'label': label,
      'scenario': scenario,
      'runs': runs.length,
      'base_hz': _mode(runs.map((r) => r.baseHz)),
      'median_ms': _median(runs.map((r) => r.medianMs)),
      'p90_ms': _median(runs.map((r) => r.p90Ms)),
      'worst_ms': runs.map((r) => r.maxMs).reduce(math.max),
      'late_pct': _round(
        runs.map((r) => r.latePct).reduce((a, b) => a + b) / runs.length,
      ),
      'missed_vsyncs': runs.map((r) => r.missedVsyncs).reduce((a, b) => a + b),
      'long_frames_ms': [for (final r in runs) ...r.longFramesMs],
    };
    stdout.writeln('SUMMARY ${jsonEncode(summary)}');
    await _resultsFile.parent.create(recursive: true);
    await _resultsFile.writeAsString(
      '${jsonEncode(summary)}\n',
      mode: FileMode.append,
    );
  }

  Future<List<int>> _presentTimes() async {
    final out = await _shell("dumpsys SurfaceFlinger --latency '$_layer'");
    final times = <int>[];
    for (final line in const LineSplitter().convert(out).skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 3) continue;
      final present = int.tryParse(parts[1]);
      // Pending fences report INT64_MAX.
      if (present == null || present == 0 || present > (1 << 62)) continue;
      times.add(present);
    }
    return times;
  }

  Future<void> _tap(double fx, double fy, int waitMs) async {
    await _shell(
      'input tap ${(fx * _width).round()} ${(fy * _height).round()}',
    );
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  }

  Future<void> _swipe(
    int x1,
    int y1,
    int x2,
    int y2,
    int ms,
    int waitMs,
  ) async {
    await _shell('input swipe $x1 $y1 $x2 $y2 $ms');
    await Future<void>.delayed(Duration(milliseconds: waitMs));
  }

  static Future<String> _shell(String command) async {
    final result = await Process.run('adb', ['shell', command]);
    if (result.exitCode != 0) {
      throw ProcessException('adb', ['shell', command], '${result.stderr}');
    }
    return result.stdout as String;
  }
}

class _Stats {
  _Stats({
    required this.frames,
    required this.baseHz,
    required this.medianMs,
    required this.p90Ms,
    required this.maxMs,
    required this.latePct,
    required this.missedVsyncs,
    required this.longFramesMs,
    required this.longFramesAtS,
    required this.rateShare,
  });

  final int frames;
  final int baseHz;
  final double medianMs;
  final double p90Ms;
  final double maxMs;

  /// Share of intervals longer than 1.5 refresh periods.
  final double latePct;
  final int missedVsyncs;

  /// Intervals of 30 ms or more, in order: the stalls worth investigating.
  final List<double> longFramesMs;

  /// Seconds from the first recorded frame to the end of each long interval.
  final List<double> longFramesAtS;

  /// Percentage of intervals at each refresh rate, to tell touch-driven 120 Hz
  /// motion from 60 Hz untouched animation in one recording.
  final Map<String, double> rateShare;

  static _Stats? of(List<int> presents) {
    if (presents.length < 3) return null;
    final run = <double>[];
    final longFramesMs = <double>[];
    final longFramesAtS = <double>[];
    for (var i = 1; i < presents.length; i++) {
      final gap = (presents[i] - presents[i - 1]) / 1e6;
      if (gap >= _runBreakMs) continue;
      run.add(gap);
      if (gap >= 30) {
        longFramesMs.add(_round(gap));
        longFramesAtS.add(_round((presents[i] - presents.first) / 1e9));
      }
    }
    if (run.isEmpty) return null;
    // The refresh period is the most common short interval.
    const periods = [1000 / 120, 1000 / 90, 1000 / 60];
    final base = periods.reduce(
      (best, period) => _near(run, period) > _near(run, best) ? period : best,
    );
    final lateGaps = run.where((gap) => gap > base * 1.5).toList();
    final sorted = [...run]..sort();
    double percentile(double q) =>
        sorted[math.min(sorted.length - 1, (q * sorted.length).floor())];
    return _Stats(
      frames: presents.length,
      baseHz: (1000 / base).round(),
      medianMs: _round(percentile(0.5)),
      p90Ms: _round(percentile(0.9)),
      maxMs: _round(sorted.last),
      latePct: _round(100 * lateGaps.length / run.length),
      missedVsyncs: lateGaps.fold(
        0,
        (sum, gap) => sum + (gap / base).round() - 1,
      ),
      longFramesMs: longFramesMs,
      longFramesAtS: longFramesAtS,
      rateShare: {
        for (final period in periods)
          '${(1000 / period).round()}': _round(
            100 * _near(run, period) / run.length,
          ),
      },
    );
  }

  static int _near(List<double> gaps, double period) =>
      gaps.where((gap) => (gap - period).abs() < 1.2).length;

  Map<String, Object> toJson() => {
    'frames': frames,
    'base_hz': baseHz,
    'median_ms': medianMs,
    'p90_ms': p90Ms,
    'max_ms': maxMs,
    'late_pct': latePct,
    'missed_vsyncs': missedVsyncs,
    'long_frames_ms': longFramesMs,
    'long_frames_at_s': longFramesAtS,
    'rate_share_pct': rateShare,
  };
}

double _round(double value) => (value * 100).round() / 100;

double _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  return sorted[sorted.length ~/ 2];
}

int _mode(Iterable<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
