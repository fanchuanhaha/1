import '../api/base_drive.dart';
import '../api/drive_type.dart';
import '../api/quark_client.dart';
import '../core/gopeed/gopeed_boot.dart';
import '../state/app_state.dart';
import '../utils/app_logger.dart';

class DownloadService {
  /// 百度网盘下载直链要求的 UA
  ///
  /// 必须用百度官方客户端 UA，不能用 Chrome UA：实测用 Chrome UA 访问
  /// dlink 会返回 403 hitcode:119（user not authorized）被风控拦截；
  /// 而用 netdisk 客户端 UA 会返回 302 重定向到真实下载 CDN（baidupcs.com），
  /// 跟随该重定向才能完成下载。
  static const String _baiduUa = 'netdisk;android;9.4.0.3';

  /// 把直链加入 Gopeed 下载队列，返回错误信息（null 表示成功）
  ///
  /// [referer] / [userAgent] 供不同网盘传入专属请求头（百度等需要，否则容易 403）。
  /// [path] 可覆盖下载目录；[extraHeaders] 若提供则完全替换默认请求头（用于「自定义下载」）。
  static Future<String?> addDirectUrl({
    required String url,
    required String fileName,
    required String cookie,
    String referer = 'https://pan.quark.cn/',
    String userAgent = QuarkClient.uaPc,
    String? path,
    Map<String, String>? extraHeaders,
    int connections = 16,
  }) async {
    AppLogger.I.i(
        'download',
        'addDirectUrl: name=$fileName urlHost=${_host(url)} '
        'cookieLen=${cookie.length} referer=$referer connections=$connections '
        'path=$path');
    try {
      final dir = (path != null && path.isNotEmpty)
          ? path
          : await AppState.I.effectiveDownloadDir();
      AppLogger.I.i('download', 'addDirectUrl: 下载目录 dir=$dir');
      final client = await GopeedEngine.ensureStarted();
      final headers = extraHeaders ??
          {
            if (cookie.isNotEmpty) 'Cookie': cookie,
            'Referer': referer,
            'User-Agent': userAgent,
          };
      final id = await client.create(
        url: url,
        path: dir,
        name: fileName,
        headers: headers,
        connections: connections,
      );
      AppLogger.I.i('download', 'addDirectUrl: 已创建下载任务 id=$id url=$url');
      return null;
    } catch (e) {
      AppLogger.I.e('download', 'addDirectUrl: 创建下载任务失败 url=$url 错误=$e');
      return '创建下载任务失败: $e';
    }
  }

  /// 从 URL 推断文件名（无显式文件名时用）
  static String inferFileName(String url) {
    try {
      final u = Uri.parse(url);
      final seg = u.pathSegments.isNotEmpty ? u.pathSegments.last : '';
      if (seg.isNotEmpty && (seg.contains('.') || seg.isNotEmpty)) return seg;
    } catch (_) {}
    return '';
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
    String? cookie,
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
    // 外部可覆盖 cookie（如夸克需用其下载专用 cookie）；否则回退到驱动器登录 cookie。
    final effCookie = (cookie != null && cookie.isNotEmpty)
        ? cookie
        : (drive.loginCookie ?? '');
    final err = await addDirectUrl(
      url: info.url,
      fileName: info.fileName,
      // 加速直链属于分享/匿名上下文，不能带本账号个人 cookie（会触发 CDN 拒签）。
      cookie: info.skipCookie ? '' : effCookie,
      referer: http.referer,
      // 直链若指定了专用 UA（如百度加速返回的 netdisk;8.42.0.5;PC）则优先使用。
      userAgent: info.userAgent.isNotEmpty ? info.userAgent : http.ua,
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
        connections: app.connectionsFor(DriveType.quark),
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