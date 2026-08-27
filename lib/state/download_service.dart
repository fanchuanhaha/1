import '../api/base_drive.dart';
import '../api/drive_type.dart';
import '../api/quark_client.dart';
import '../core/gopeed/gopeed_boot.dart';
import '../state/app_state.dart';
import '../utils/app_logger.dart';

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
    AppLogger.I.i(
        'download',
        'addDirectUrl: name=$fileName urlHost=${_host(url)} '
        'cookieLen=${cookie.length} referer=$referer connections=$connections');
    try {
      final dir = await AppState.I.effectiveDownloadDir();
      AppLogger.I.i('download', 'addDirectUrl: 下载目录 dir=$dir');
      final client = await GopeedEngine.ensureStarted();
      final id = await client.create(
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
      AppLogger.I.i('download', 'addDirectUrl: 已创建下载任务 id=$id url=$url');
      return null;
    } catch (e) {
      AppLogger.I.e('download', 'addDirectUrl: 创建下载任务失败 url=$url 错误=$e');
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
    if (info.url.isEmpty) {
      AppLogger.I.w('download', 'addDriveUrl: 下载地址为空，跳过 type=${drive.type} fid=${info.fid}');
      return '未获取到下载地址';
    }
    final http = _httpFor(drive.type);
    AppLogger.I.i(
        'download',
        'addDriveUrl: type=${drive.type.name} fid=${info.fid} '
        'name=${info.fileName} redirectUrl=${_short(info.url)}');
    final err = await addDirectUrl(
      url: info.url,
      fileName: info.fileName,
      cookie: drive.loginCookie ?? '',
      referer: http.referer,
      userAgent: http.ua,
      connections: connections,
    );
    if (err == null) {
      AppLogger.I.i('download', 'addDriveUrl: 入队成功 ${drive.type.name}/${info.fileName}');
    } else {
      AppLogger.I.e('download', 'addDriveUrl: 入队失败 ${drive.type.name}/${info.fileName} 原因=$err');
    }
    return err;
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

  static String _host(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '(无法解析)';
    }
  }

  /// 截短 URL 便于查看（保留主机 + 哈希片段）
  static String _short(String url) {
    final u = url.length > 90 ? '${url.substring(0, 90)}…' : url;
    return u;
  }
}