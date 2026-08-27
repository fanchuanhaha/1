import '../api/base_drive.dart';
import '../api/drive_type.dart';
import '../api/quark_client.dart';
import '../core/gopeed/gopeed_boot.dart';
import '../state/app_state.dart';

class DownloadService {
  /// 百度网盘下载直链使用的 PC 网页 UA（与登录请求一致，避免被风控）
  static const String _baiduUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 把直链加入 Gopeed 下载队列，返回错误信息（null 表示成功）
  ///
  /// [referer] / [userAgent] 供不同网盘传入专属请求头（百度等需要，否则容易 403）。
  static Future<String?> addDirectUrl({
    required String url,
    required String fileName,
    required String cookie,
    String referer = 'https://pan.quark.cn/',
    String userAgent = QuarkClient.uaPc,
    int connections = 16,
  }) async {
    try {
      final dir = await AppState.I.effectiveDownloadDir();
      final client = await GopeedEngine.ensureStarted();
      await client.create(
        url: url,
        path: dir,
        name: fileName,
        headers: {
          if (cookie.isNotEmpty) 'Cookie': cookie,
          'Referer': referer,
          'User-Agent': userAgent,
        },
        connections: connections,
      );
      return null;
    } catch (e) {
      return '创建下载任务失败: $e';
    }
  }

  /// 按网盘类型解析下载直链的专属请求头（Referer / UA / Cookie）
  static ({String referer, String ua}) _httpFor(DriveType type) {
    switch (type) {
      case DriveType.baidu:
        return (referer: 'https://pan.baidu.com/', ua: _baiduUa);
      case DriveType.quark:
      case DriveType.guangya:
        return (referer: 'https://pan.quark.cn/', ua: QuarkClient.uaPc);
      default:
        return (
          referer: 'https://pan.baidu.com/',
          ua: _baiduUa,
        );
    }
  }

  /// 通用下载：根据驱动器类型把其直链加入下载队列，返回错误信息（null 表示已入队）
  static Future<String?> addDriveUrl(
    BaseDrive drive,
    DriveDownloadInfo info, {
    int connections = 16,
  }) async {
    final http = _httpFor(drive.type);
    return addDirectUrl(
      url: info.url,
      fileName: info.fileName,
      cookie: drive.loginCookie ?? '',
      referer: http.referer,
      userAgent: http.ua,
      connections: connections,
    );
  }

  /// 根据 fid 直接下载网盘文件，返回错误信息（null 表示已加入队列）
  static Future<String?> downloadQuarkFile(String fid,
      {String? fileName}) async {
    try {
      final app = AppState.I;
      final (infos, cookie) = await app.quark.getDownloadInfo([fid]);
      if (infos.isEmpty) return '未获取到下载地址';
      final info = infos.first;
      return addDirectUrl(
        url: info.url,
        fileName:
            info.fileName.isNotEmpty ? info.fileName : (fileName ?? ''),
        cookie: cookie,
        connections: app.connections,
      );
    } catch (e) {
      return '下载失败: $e';
    }
  }

  /// 把 magnet 链接加入下载队列
  static Future<String?> addMagnet({
    required String url,
    String? name,
  }) async {
    try {
      final dir = await AppState.I.effectiveDownloadDir();
      final client = await GopeedEngine.ensureStarted();
      await client.create(
        url: url,
        path: dir,
        name: name ?? '',
      );
      return null;
    } catch (e) {
      return '创建 BT 任务失败: $e';
    }
  }
}