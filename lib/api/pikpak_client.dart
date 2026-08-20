import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// PikPak 异常
class PikPakException implements Exception {
  final int code;
  final String message;

  PikPakException(this.code, this.message);

  @override
  String toString() => message;
}

/// PikPak 网盘客户端（基于 APK 反编译提取的 API 端点）
class PikPakClient implements BaseDrive {
  // ---- API 端点 ----
  static const String _shareApi = 'https://api-drive.mypikpak.com/drive/v1/share';
  static const String _shareDetail = 'https://api-drive.mypikpak.com/drive/v1/share/detail';
  static const String _shareFileInfo = 'https://api-drive.mypikpak.com/drive/v1/share/file_info';
  static const String _captchaInit = 'https://user.mypikpak.com/v1/shield/captcha/init';

  static const String defaultUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // ---- BaseDrive ----
  @override
  DriveType get type => DriveType.pikpak;

  @override
  String get label => 'PikPak';

  @override
  bool get hasLogin => _accessToken.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie =>
      _accessToken.isEmpty ? null : 'Bearer $_accessToken';

  // ---- 内部状态 ----
  final Dio _dio;
  String _accessToken = '';
  String _refreshToken = '';
  String _userId = '';
  DriveUserInfo? _userInfo;

  PikPakClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---- 内部请求工具 ----

  Map<String, dynamic> _buildHeaders({
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) {
    return <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent': userAgent ?? defaultUserAgent,
      if (_accessToken.isNotEmpty) 'Authorization': 'Bearer $_accessToken',
      ...?extraHeaders,
    };
  }

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final headers = _buildHeaders(
      userAgent: userAgent,
      extraHeaders: extraHeaders,
    );
    final resp = await _dio.request(
      url,
      data: data,
      queryParameters: params,
      options: Options(
        method: method,
        headers: headers,
        validateStatus: (_) => true,
      ),
    );
    AppLogger.I.http(
      'pikpak',
      method,
      url,
      status: resp.statusCode ?? -1,
      cred: _accessToken,
      body: resp.data,
    );
    return resp;
  }

  Map<String, dynamic> _parseBody(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  dynamic _check(Map<String, dynamic> body) {
    final errorCode = toInt(body['error_code'], fallback: toInt(body['code'], fallback: 0));
    if (errorCode != 0) {
      final msg = body['error_message']?.toString() ??
          body['message']?.toString() ??
          '请求失败';
      throw PikPakException(errorCode, msg);
    }
    return body['data'];
  }

  Future<dynamic> _get(
    String url, {
    Map<String, dynamic>? params,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('GET', url,
        params: params, userAgent: userAgent, extraHeaders: extraHeaders);
    return _check(_parseBody(resp));
  }

  Future<dynamic> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('POST', url,
        params: params, data: data, userAgent: userAgent, extraHeaders: extraHeaders);
    return _check(_parseBody(resp));
  }

  // ---- BaseDrive 接口实现 ----

  @override
  Future<void> init() async {
    // 从持久化存储加载 token（由上层调用方提供）
    // 继承自 BaseDrive 的空实现，由上层调用 setToken 或类似方法注入
  }

  /// 设置访问令牌（由上层调用方注入持久化的凭证）
  void setToken(String accessToken, {String refreshToken = '', String userId = ''}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _userId = userId;
  }

  /// 获取当前访问令牌
  String get accessToken => _accessToken;

  /// 获取当前刷新令牌
  String get refreshToken => _refreshToken;

  @override
  Future<String?> login(dynamic credential) async {
    // credential 预期为 {type: 'captcha'|'token', ...}
    // PikPak 登录需先走 captcha/init 获取凭证，再换取 accessToken
    // 此处由上层调用方传入完整的认证凭据并直接设置 token
    if (credential is Map) {
      final token = credential['access_token']?.toString() ?? '';
      if (token.isNotEmpty) {
        setToken(
          token,
          refreshToken: credential['refresh_token']?.toString() ?? '',
          userId: credential['user_id']?.toString() ?? '',
        );
        return null;
      }
    }
    return '未提供有效的登录凭据';
  }

  @override
  Future<void> logout() async {
    _accessToken = '';
    _refreshToken = '';
    _userId = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (_accessToken.isEmpty) return;
    // 通过文件列表接口获取用户信息（或通过专用接口）
    // PikPak 暂无公开的用户信息 API，暂留空
    _userInfo = DriveUserInfo(
      nickname: _userId,
      avatar: '',
      userId: _userId,
    );
  }

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    // PikPak 文件列表使用 share/file_info 或独立的文件系统接口
    // 此处使用 share 相关 API 的通用模式
    try {
      final data = await _get(
        'https://api-drive.mypikpak.com/drive/v1/files',
        params: {
          'parent_id': pdirFid,
          'page': page,
          'page_size': size,
          'thumbnail_size': 'SIZE_LARGE',
          'type': 'all',
          'trashed': false,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['modified_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '获取文件列表失败: $e');
    }
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    try {
      final data = await _get(
        'https://api-drive.mypikpak.com/drive/v1/files:search',
        params: {
          'query': keyword,
          'page': page,
          'page_size': size,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['modified_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '搜索文件失败: $e');
    }
  }

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    try {
      final data = await _post(
        'https://api-drive.mypikpak.com/drive/v1/files:batchGet',
        data: {
          'ids': fids,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        // 构造下载链接，优先使用 mediainfo 中的链接
        String url = '';
        final mediaInfo = m['media_info'];
        if (mediaInfo is Map) {
          url = mediaInfo['download_url']?.toString() ?? '';
        }
        return DriveDownloadInfo(
          url: url,
          fileName: m['name']?.toString() ?? '',
          size: toInt(m['size']),
          fid: m['id']?.toString() ?? '',
        );
      }).toList();
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '获取下载链接失败: $e');
    }
  }

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      // PikPak 分享链接: https://mypikpak.com/s/xxxx
      final path = uri.path;
      final idx = path.lastIndexOf('/s/');
      if (idx >= 0) {
        pwdId = path.substring(idx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['passcode'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    final data = await _post(
      '$_shareApi:verify',
      data: {
        'share_id': pwdId,
        'passcode': passcode,
      },
    );
    final stoken = data['share_token']?.toString() ?? '';
    final shareId = data['share_id']?.toString() ?? pwdId;
    if (stoken.isEmpty) {
      throw PikPakException(-1, '分享链接已失效或提取码错误');
    }
    return DriveShareSession(
      shareId: shareId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: stoken,
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session, String pdirFid,
      {int page = 1, int size = 50}) async {
    final files = <DriveShareFile>[];
    try {
      final data = await _get(
        _shareFileInfo,
        params: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'parent_id': pdirFid,
          'page': page,
          'page_size': size,
          'thumbnail_size': 'SIZE_LARGE',
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveShareFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          shareFidToken: m['share_fid_token']?.toString() ?? '',
        );
      }).toList();
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '获取分享文件列表失败: $e');
    }
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    try {
      final data = await _post(
        _shareFileInfo,
        data: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'file_ids': fidList,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        String url = '';
        final mediaInfo = m['media_info'];
        if (mediaInfo is Map) {
          url = mediaInfo['download_url']?.toString() ?? '';
        }
        return DriveDownloadInfo(
          url: url,
          fileName: m['name']?.toString() ?? '',
          size: toInt(m['size']),
          fid: m['id']?.toString() ?? '',
        );
      }).toList();
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '获取分享下载链接失败: $e');
    }
  }

  @override
  Future<void> saveShare(
      DriveShareSession session, List<DriveShareFile> files, String toPdirFid) async {
    try {
      await _post(
        '$_shareApi:save',
        data: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'file_ids': files.map((f) => f.fid).toList(),
          'parent_id': toPdirFid,
        },
      );
    } on PikPakException {
      rethrow;
    } catch (e) {
      throw PikPakException(-1, '转存分享文件失败: $e');
    }
  }

  @override
  void dispose() {
    _dio.close();
  }
}