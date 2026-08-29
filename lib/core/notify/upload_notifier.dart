import '../utils/app_logger.dart';

/// 上传完成/失败提醒。
/// 本 fork 未引入 flutter_local_notifications，仅写运行日志；
/// 完成/失败同样会在「上传」页的任务状态中展示。
class UploadNotifier {
  static Future<void> showDone(String fileName) async {
    AppLogger.I.i('upload', '上传完成: $fileName');
  }

  static Future<void> showFailed(String fileName, String error) async {
    AppLogger.I.e('upload', '上传失败 $fileName: $error');
  }
}