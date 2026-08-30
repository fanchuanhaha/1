import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 轻量应用日志：追加写入 <文档目录>/quarklite/logs/app.log，
/// 超过 1MB 环形截断保留尾部，供排查问题（我的 → 日志 → 复制）。
class AppLogger {
  AppLogger._();

  static final AppLogger I = AppLogger._();

  static const int _maxBytes = 1024 * 1024; // 日志文件上限 1MB
  static const int _keepBytes = 512 * 1024; // 截断后保留的尾部大小

  File? _file;
  bool _ready = false;
  bool _initDone = false;

  /// 初始化日志文件（失败时仅控制台输出，不影响主流程）
  Future<void> init() async {
    if (_initDone) return;
    _initDone = true;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/quarklite/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/app.log');
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final bytes = f.readAsBytesSync();
        f.writeAsBytesSync(bytes.sublist(bytes.length - _keepBytes));
      }
      _file = f;
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  void i(String tag, String msg) => _log('INFO', tag, msg);
  void w(String tag, String msg) => _log('WARN', tag, msg);
  void e(String tag, String msg) => _log('ERROR', tag, msg);

  void _log(String level, String tag, String msg) {
    final line = '[${_ts()}] [$level] [$tag] $msg';
    // ignore: avoid_print
    print(line);
    if (!_ready) return;
    try {
      _file!.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // 日志写入失败不影响主流程
    }
  }

  static String _ts() {
    final n = DateTime.now();
    String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)} '
        '${p(n.hour)}:${p(n.minute)}:${p(n.second)}.${p(n.millisecond, 3)}';
  }

  /// 记录一次 HTTP 请求的脱敏日志（各网盘客户端统一调用）
  ///
  /// [cred] 传入会话凭据（cookie/access_token），仅记录长度不记录明文。
  void http(
    String tag,
    String method,
    String url, {
    int? status,
    String? cred,
    Object? body,
  }) {
    final sb = StringBuffer('$method $url');
    if (status != null) sb.write('\n  status=$status');
    if (cred != null) {
      sb.write(' cred=${cred.isEmpty ? 'empty' : 'len=${cred.length}'}');
    }
    if (body != null) {
      String s;
      try {
        s = body is String ? body : jsonEncode(body).toString();
      } catch (_) {
        s = '<无法序列化>';
      }
      if (s.length > 800) s = '${s.substring(0, 800)}…';
      sb.write('\n  body=$s');
    }
    _log('INFO', tag, sb.toString());
  }

  /// 清空日志文件
  Future<void> clear() async {
    final f = _file;
    if (f != null) {
      try {
        f.writeAsStringSync('');
      } catch (_) {}
    }
    // 确保文件存在，便于后续继续写入
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/quarklite/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final nf = File('${dir.path}/app.log');
      if (!nf.existsSync()) nf.writeAsStringSync('');
      _file = nf;
      _ready = true;
    } catch (_) {}
  }

  /// 读取最近 [maxLines] 行日志（供界面复制/展示）
  Future<String> readLog({int maxLines = 500}) async {
    final f = _file;
    if (f == null || !f.existsSync()) return '（暂无日志）';
    try {
      final lines = f.readAsLinesSync();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (_) {
      return '（日志读取失败）';
    }
  }

  /// 导出完整日志到 [path]（如 /sdcard/1.log），返回是否成功与提示信息
  Future<({bool ok, String message})> exportTo(String path) async {
    try {
      final f = _file;
      final content =
          (f != null && f.existsSync()) ? f.readAsStringSync() : '（暂无日志）';
      // 把 /sdcard 符号链接解析为真实外部存储路径，提高写入兼容性
      var target = path;
      if (target == '/sdcard' || target.startsWith('/sdcard/')) {
        target = target.replaceFirst('/sdcard', '/storage/emulated/0');
      }
      final tf = File(target);
      if (!tf.parent.existsSync()) {
        try {
          tf.parent.createSync(recursive: true);
        } catch (_) {}
      }
      tf.writeAsStringSync(content, flush: true);
      return (ok: true, message: target);
    } catch (e) {
      return (ok: false, message: '导出失败：$e');
    }
  }

  /// 日志文件完整路径
  Future<String> logPath() async {
    final f = _file;
    if (f != null) return f.path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/quarklite/logs/app.log';
    } catch (_) {
      return '（未知）';
    }
  }
}