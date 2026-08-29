import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/gopeed/gopeed_boot.dart';
import '../core/gopeed/gopeed_models.dart';
import '../utils/app_logger.dart';

class DownloadManager extends ChangeNotifier {
  static DownloadManager? _instance;
  static DownloadManager get I => _instance ??= DownloadManager._();

  final List<GopeedTask> tasks = [];
  Timer? _timer;
  bool _polling = false;
  bool _failed = false;

  /// 已输出过日志的任务 id（避免 1.5s 轮询刷屏：error/done/running 只记一次）
  final Set<String> _reportedError = {};
  final Set<String> _reportedDone = {};
  final Set<String> _reportedRunning = {};

  DownloadManager._();

  void startPolling() {
    if (_polling) return;
    _polling = true;
    _failed = false;
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    _poll();
  }

  void stopPolling() {
    _polling = false;
    _timer?.cancel();
    _timer = null;
  }

  bool get hasEngineError => _failed;

  Future<void> _poll() async {
    if (!GopeedEngine.started) return;
    try {
      final list = await GopeedEngine.client.list();
      for (final t in list) {
        switch (t.status) {
          case GopeedStatus.error:
            if (_reportedError.add(t.id)) {
              var detail = '任务失败 name=${t.name} id=${t.id} '
                  'downloaded=${t.downloaded}/${t.size}';
              if (t.error.isNotEmpty) detail += ' err=${t.error}';
              AppLogger.I.e('download', detail);
              // 打印引擎原始字段，便于定位 403/网络错误
              final raw = t.raw;
              if (raw != null) {
                AppLogger.I.e(
                    'download', '任务失败原始数据: ${_clip(jsonEncode(raw))}');
              }
            }
            break;
          case GopeedStatus.done:
            if (_reportedDone.add(t.id)) {
              AppLogger.I.i('download',
                  '任务完成 name=${t.name} id=${t.id} size=${t.size}');
            }
            break;
          case GopeedStatus.ready:
          case GopeedStatus.wait:
            if (_reportedRunning.add(t.id)) {
              AppLogger.I.i(
                  'download',
                  '任务排队/开始 name=${t.name} id=${t.id} '
                  'size=${t.size} status=${t.status.name}');
            }
            break;
          case GopeedStatus.running:
            if (_reportedRunning.add(t.id)) {
              AppLogger.I.i(
                  'download',
                  '任务开始下载 name=${t.name} id=${t.id} '
                  'size=${t.size} speed=${t.speed}B/s');
            }
            break;
          case GopeedStatus.pause:
            break;
        }
      }
      tasks
        ..clear()
        ..addAll(list);
      _failed = false;
      notifyListeners();
    } catch (e) {
      _failed = true;
      AppLogger.I.e('download', '引擎任务轮询失败: $e');
    }
  }

  static String _clip(String s, [int limit = 1600]) {
    if (s.length <= limit) return s;
    return '${s.substring(0, limit)}…[截断, 共${s.length}字符]';
  }

  List<GopeedTask> byStatus(GopeedStatus status) {
    return tasks.where((t) => t.status == status).toList();
  }

  List<GopeedTask> activeTasks() =>
      tasks.where((t) => t.status.isActive).toList();

  int countOf(GopeedStatus status) => byStatus(status).length;

  Future<void> pauseTask(GopeedTask task) async {
    try {
      await GopeedEngine.client.pause(task.id);
    } catch (e) {
      rethrow;
    } finally {
      await _poll();
    }
  }

  Future<void> resumeTask(GopeedTask task) async {
    try {
      await GopeedEngine.client.resume(task.id);
    } catch (e) {
      rethrow;
    } finally {
      await _poll();
    }
  }

  /// 重试已失败（或已完成/暂停）的任务：让引擎用原参数重新开始下载。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> retryTask(GopeedTask task) async {
    try {
      await GopeedEngine.client.restore(task.id);
      return null;
    } catch (e) {
      AppLogger.I.e('download', '重试任务失败 id=${task.id} name=${task.name} 错误=$e');
      return '重试失败: $e';
    } finally {
      await _poll();
    }
  }

  Future<void> removeTask(GopeedTask task, {bool deleteFile = false}) async {
    try {
      await GopeedEngine.client.remove(task.id, force: deleteFile);
    } finally {
      await _poll();
    }
  }

  Future<void> clearDone() async {
    final doneIds = byStatus(GopeedStatus.done).map((t) => t.id).toList();
    if (doneIds.isEmpty) return;
    try {
      await GopeedEngine.client.removeAll(ids: doneIds, force: false);
    } finally {
      await _poll();
    }
  }

  Future<void> pauseAllActive() async {
    final ids = activeTasks().map((t) => t.id).toList();
    if (ids.isEmpty) return;
    try {
      await GopeedEngine.client.pauseAll(ids: ids);
    } finally {
      await _poll();
    }
  }
}
