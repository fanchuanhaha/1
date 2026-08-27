import '../../utils/types.dart';

enum GopeedStatus {
  ready,
  running,
  pause,
  wait,
  error,
  done;

  static GopeedStatus from(String? name) {
    switch (name) {
      case 'ready':
        return GopeedStatus.ready;
      case 'running':
        return GopeedStatus.running;
      case 'pause':
        return GopeedStatus.pause;
      case 'wait':
        return GopeedStatus.wait;
      case 'error':
        return GopeedStatus.error;
      case 'done':
        return GopeedStatus.done;
      default:
        return GopeedStatus.wait;
    }
  }

  String get label {
    switch (this) {
      case GopeedStatus.ready:
        return '等待中';
      case GopeedStatus.running:
        return '下载中';
      case GopeedStatus.pause:
        return '已暂停';
      case GopeedStatus.wait:
        return '排队中';
      case GopeedStatus.error:
        return '失败';
      case GopeedStatus.done:
        return '已完成';
    }
  }

  bool get isActive =>
      this == GopeedStatus.ready ||
      this == GopeedStatus.running ||
      this == GopeedStatus.wait;
}

class GopeedTask {
  final String id;
  final String name;
  final GopeedStatus status;
  final int size;
  final int downloaded;
  final int speed;
  final int createdAt;

  /// 引擎返回的错误描述（尽力解析，可能为空）
  final String error;

  /// 引擎返回的原始 JSON，供失败诊断
  final Map<String, dynamic>? raw;

  GopeedTask({
    required this.id,
    required this.name,
    required this.status,
    required this.size,
    required this.downloaded,
    required this.speed,
    required this.createdAt,
    this.error = '',
    this.raw,
  });

  double get progress =>
      size <= 0 ? 0 : (downloaded / size).clamp(0.0, 1.0);

  factory GopeedTask.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>? ?? const {};
    final res = (json['meta'] as Map<String, dynamic>?)?['res']
            as Map<String, dynamic>? ??
        const {};
    String err = '';
    final e = json['err'] ?? json['error'];
    if (e is String && e.isNotEmpty) {
      err = e;
    } else if (e is Map) {
      err = e['message']?.toString() ?? '';
    }
    return GopeedTask(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      status: GopeedStatus.from(json['status']?.toString()),
      size: toInt(res['size']),
      downloaded: toInt(progress['downloaded']),
      speed: toInt(progress['speed']),
      createdAt: toInt(json['createdAt']),
      error: err,
      raw: json,
    );
  }
}
