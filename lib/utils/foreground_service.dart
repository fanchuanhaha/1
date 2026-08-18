import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../state/download_manager.dart';
import '../core/gopeed/gopeed_models.dart';

/// 前台服务常驻管理：下载进行时在通知栏显示常驻通知与进度，
/// 防止后台/锁屏时进程被系统回收，保证下载持续进行。
class ForegroundServiceManager {
  static const _serviceId = 20240801;
  static const _channelId = 'quarklite_download';

  static bool _initialized = false;
  static bool _running = false;
  static bool _permissionChecked = false;

  /// 由 main() 调用一次，初始化通信端口与监听下载状态
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 初始化主隔离区与 TaskHandler 通信端口
    FlutterForegroundTask.initCommunicationPort();

    // 配置通知渠道与任务参数
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: '下载进度',
        channelDescription: '下载进行时显示常驻通知与实时进度',
        onlyAlertOnce: true,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // 跟随下载状态启停前台服务
    DownloadManager.I.addListener(_syncWithDownloads);
    _syncWithDownloads();
  }

  /// 是否正在显示前台服务通知
  static bool get running => _running;

  /// 根据当前是否有活跃下载来启停前台服务
  static void _syncWithDownloads() {
    final active = DownloadManager.I.activeTasks();
    final hasActive = active.isNotEmpty;

    if (hasActive && !_running) {
      unawaited(_start(active));
    } else if (!hasActive && _running) {
      unawaited(_stop());
    } else if (hasActive && _running) {
      unawaited(_update(active));
    }
  }

  static Future<void> _ensurePermission() async {
    if (_permissionChecked) return;
    _permissionChecked = true;
    // Android 13+ 需要通知权限才能显示前台服务通知
    final p = await FlutterForegroundTask.checkNotificationPermission();
    if (p != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  static Future<void> _start(List<GopeedTask> active) async {
    await _ensurePermission();
    try {
      // 若服务已在运行（如启动异常后的残留），直接更新而非重复启动
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
        _running = true;
        return;
      }
      final res = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: _title(active),
        notificationText: _text(active),
        notificationIcon: _icon,
        callback: startCallback,
      );
      if (res is ServiceRequestSuccess) {
        _running = true;
      }
    } catch (e) {
      // 前台服务启动失败不影响下载本身
    }
  }

  static Future<void> _update(List<GopeedTask> active) async {
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: _title(active),
        notificationText: _text(active),
      );
    } catch (_) {}
  }

  static Future<void> _stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _running = false;
  }

  static NotificationIcon? get _icon {
    // 使用应用图标作为通知图标
    return null; // 不显式指定，走插件默认（应用图标）
  }

  static String _title(List<GopeedTask> active) {
    final running = active.where((t) => t.status == GopeedStatus.running);
    if (running.isNotEmpty && running.length == 1) {
      final t = running.first;
      return '下载中：${t.name}';
    }
    return '正在下载 ${active.length} 个任务';
  }

  static String _text(List<GopeedTask> active) {
    final buffer = <String>[];
    for (final t in active.where((t) => t.status.isActive).take(2)) {
      final speed = _fmtSpeed(t.speed);
      final pct = (t.progress * 100).toStringAsFixed(0);
      buffer.add('${t.name}  $pct%  $speed');
    }
    if (active.length > 2) {
      buffer.add('等 ${active.length} 个任务');
    }
    return buffer.join('\n');
  }

  static String _fmtSpeed(int bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)}MB/s';
    }
    if (bytesPerSec >= 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
    }
    return '$bytesPerSec B/s';
  }
}

/// 前台服务在后台隔离区启动时的回调（必须是顶层或静态函数）
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_DownloadTaskHandler());
}

class _DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    // 点击通知回到应用
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}