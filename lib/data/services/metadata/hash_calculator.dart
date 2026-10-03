import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/isolate_pool.dart';

String _sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();

/// 文件哈希计算器
///
/// 提供文件 SHA256 哈希计算，支持：
/// - 异步文件读取
/// - 并发控制
/// - 去重（相同路径同时只有一个计算任务）
/// - 路径到哈希的映射缓存
class FileHashCalculator {
  static final FileHashCalculator _instance = FileHashCalculator._internal();
  factory FileHashCalculator() => _instance;
  FileHashCalculator._internal();

  /// 小于此大小的缓冲区同步计算，起 isolate 的开销比哈希本身更大。
  static const int backgroundHashThresholdBytes = 64 * 1024;

  final _pathToHashMap = <String, String>{};
  final _hashToPathsMap = <String, Set<String>>{};
  final _pendingHashFutures = <String, Future<String>>{};
  final _bytesHashes = Expando<String>('contentHash');
  final _pendingBytesHashes = Expando<Future<String>>('pendingContentHash');
  final _semaphore = _Semaphore(3);

  int _hashComputeCount = 0;
  int _hashCacheHitCount = 0;

  /// 计算文件哈希（带缓存和并发控制）
  Future<String> calculate(String filePath) async {
    // 检查路径映射缓存
    final cachedHash = _pathToHashMap[filePath];
    if (cachedHash != null) {
      _hashCacheHitCount++;
      return cachedHash;
    }

    // 检查是否有正在进行的计算
    final pendingFuture = _pendingHashFutures[filePath];
    if (pendingFuture != null) {
      return pendingFuture;
    }

    // 创建新的计算任务
    final future = _calculateWithSemaphore(filePath);
    _pendingHashFutures[filePath] = future;

    try {
      final hash = await future;
      return hash;
    } finally {
      _pendingHashFutures.remove(filePath);
    }
  }

  /// 从字节数据计算哈希（同步）
  ///
  /// 结果按缓冲区实例缓存：出图后保存、分区记录和元数据解析拿到的是同一份
  /// 字节，只算一次。调用方不得在取哈希后原地改写缓冲区。
  String calculateFromBytes(Uint8List bytes) {
    final cached = _bytesHashes[bytes];
    if (cached != null) return cached;
    final hash = _sha256Hex(bytes);
    _bytesHashes[bytes] = hash;
    return hash;
  }

  /// 在后台 isolate 计算字节哈希。整张 PNG 的 SHA-256 在手机上要占一到两帧，
  /// 不能放在 UI 线程；小缓冲区直接同步计算。同一缓冲区的并发请求共享一次计算。
  Future<String> calculateFromBytesAsync(Uint8List bytes) {
    final cached = _bytesHashes[bytes];
    if (cached != null) return Future.value(cached);
    if (bytes.length < backgroundHashThresholdBytes) {
      return Future.value(calculateFromBytes(bytes));
    }
    final pending = _pendingBytesHashes[bytes];
    if (pending != null) return pending;
    final future = ComputeGate()
        .runCompute(_sha256Hex, bytes, debugLabel: 'content_hash')
        .then((hash) {
          _bytesHashes[bytes] = hash;
          return hash;
        })
        .whenComplete(() => _pendingBytesHashes[bytes] = null);
    _pendingBytesHashes[bytes] = future;
    return future;
  }

  /// 注册路径到哈希的映射
  ///
  /// 用于在已知哈希的情况下建立映射关系
  void registerPathHash(String filePath, String hash) {
    _pathToHashMap[filePath] = hash;
    _hashToPathsMap.putIfAbsent(hash, () => {}).add(filePath);
  }

  /// 通知路径变更（文件重命名）
  void notifyPathChanged(String oldPath, String newPath) {
    final hash = _pathToHashMap[oldPath];
    if (hash == null) return;

    _pathToHashMap[newPath] = hash;
    _pathToHashMap.remove(oldPath);

    final paths = _hashToPathsMap[hash];
    if (paths != null) {
      paths.remove(oldPath);
      paths.add(newPath);
    }

    AppLogger.d('Hash mapping updated: $oldPath -> $newPath', 'FileHashCalculator');
  }

  /// 获取哈希对应的所有路径
  List<String> getPathsForHash(String hash) {
    return _hashToPathsMap[hash]?.toList() ?? [];
  }

  /// 获取路径对应的哈希
  String? getHashForPath(String path) => _pathToHashMap[path];

  /// 清除所有缓存
  void clearCache() {
    _pathToHashMap.clear();
    _hashToPathsMap.clear();
    _pendingHashFutures.clear();
  }

  // ==================== 统计信息 ====================

  int get hashComputeCount => _hashComputeCount;
  int get hashCacheHitCount => _hashCacheHitCount;

  Map<String, dynamic> getStatistics() => {
    'hashComputeCount': _hashComputeCount,
    'hashCacheHitCount': _hashCacheHitCount,
    'pendingCalculations': _pendingHashFutures.length,
    'pathMappings': _pathToHashMap.length,
  };

  void resetStatistics() {
    _hashComputeCount = 0;
    _hashCacheHitCount = 0;
  }

  // ==================== 私有方法 ====================

  Future<String> _calculateWithSemaphore(String filePath) async {
    await _semaphore.acquire();
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final hash = await calculateFromBytesAsync(bytes);

      // 更新映射
      _pathToHashMap[filePath] = hash;
      _hashToPathsMap.putIfAbsent(hash, () => {}).add(filePath);

      _hashComputeCount++;
      return hash;
    } finally {
      _semaphore.release();
    }
  }
}

/// 信号量（并发控制）
class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _currentCount--;
    }
  }
}
