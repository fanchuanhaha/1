import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 阿里云盘 API 异常
class AliException implements Exception {
  final int code;
  final String message;

  AliException(this.code, this.message);

  @override
  String toString() => message;
}

/// 阿里云盘 API 客户端
///
/// 认证方式：refresh_token -> access_token（Bearer），access_token 过期时自动刷新。
class AliClient extends BaseDrive {
  static const String _baseUrl = 'https://api.aliyundrive.com';
  static const String _authUrl = 'https://auth.aliyundrive.com/v2/account/token';

  static const String _webviewLoginUrl =
      'https://auth.aliyundrive.com/v2/oauth/authorize'
      '?login_type=custom&response_type=code'
      '&redirect_uri=https%3A%2F%2Fwww.aliyundrive.com%2Fsign%2Fcallback'
      '&client_id=25dzX3vbYqktVxyX'
      '&state=%7B%22origin%22%3A%22*%22%7D#/login';

  final Dio _dio;

  String _accessToken = '';
  String _refreshToken = '';
  DriveUserInfo? _userInfo;

  AliClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  DriveType get type => DriveType.ali;

  @override
  String get label => '阿里云盘';

  @override
  bool get hasLogin => _accessToken.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie =>
      _accessToken.isEmpty ? null : 'Bearer $_accessToken';

  /// 设置 refresh_token（用于持久化恢复）
  void setRefreshToken(String token) {
    _refreshToken = token.trim();
  }

  /// 获取 refresh_token
  String get refreshToken => _refreshToken;

  /// 获取 access_token
  String get accessToken => _accessToken;

  /// Webview 登录 URL
  static String get webviewLoginUrl => _webviewLoginUrl;

  // ──────────────────── HTTP 请求基础设施 ────────────────────

  Map<String, dynamic> _buildHeaders() {
    return {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          ' (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
      if (_accessToken.isNotEmpty) 'Authorization': 'Bearer $_accessToken',
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
  }) async {
    // 非认证请求且未登录时自动尝试刷新 token
    if (!url.contains('account/token') && _accessToken.isEmpty && _refreshToken.isNotEmpty) {
      await _doRefreshToken();
    }

    final resp = await _dio.request(
      url,
      data: data,
      queryParameters: params,
      options: Options(
        method: method,
        headers: _buildHeaders(),
        validateStatus: (_) => true,
      ),
    );
    AppLogger.I.http(
      'ali',
      method,
      url,
      status: resp.statusCode ?? -1,
      cred: _accessToken.isEmpty ? _refreshToken : _accessToken,
      body: resp.data,
    );
    final body = _parseBody(resp);

    // token 过期（401），自动刷新重试
    if (body['code'] == 'AccessTokenExpired' && _refreshToken.isNotEmpty) {
      await _doRefreshToken();
      final retryResp = await _dio.request(
        url,
        data: data,
        queryParameters: params,
        options: Options(
          method: method,
          headers: _buildHeaders(),
          validateStatus: (_) => true,
        ),
      );
      return _parseBody(retryResp);
    }

    return body;
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

  void _check(Map<String, dynamic> body) {
    if (body.containsKey('code') && body['code'] != null && body['code'].toString().isNotEmpty) {
      final code = body['code'].toString();
      final message = body['message']?.toString() ?? '请求失败';
      throw AliException(
        code == 'AccessTokenExpired' ? 401 : toInt(code, fallback: -1),
        message,
      );
    }
  }

  Future<Map<String, dynamic>> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
  }) async {
    final body = await _request('POST', url, params: params, data: data);
    _check(body);
    return body;
  }

  Future<Map<String, dynamic>> _get(
    String url, {
    Map<String, dynamic>? params,
  }) async {
    final body = await _request('GET', url, params: params);
    _check(body);
    return body;
  }

  // ──────────────────── 认证 ────────────────────

  /// 通过 refresh_token 获取新的 access_token
  Future<void> _doRefreshToken() async {
    final resp = await _dio.request(
      _authUrl,
      data: {
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken,
      },
      options: Options(
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (_) => true,
      ),
    );
    AppLogger.I.http(
      'ali',
      'POST',
      _authUrl,
      status: resp.statusCode ?? -1,
      cred: _refreshToken,
      body: resp.data,
    );
    final body = _parseBody(resp);
    if (body['access_token'] == null) {
      throw AliException(-1, 'refresh_token 已失效，请重新登录');
    }
    _accessToken = body['access_token'].toString();
    _refreshToken = body['refresh_token']?.toString() ?? _refreshToken;
  }

  /// 使用 code + client_id 登录（从 webview OAuth 回调获取）
  ///
  /// 阿里云盘的 authorization_code 换接口为
  /// https://api.aliyundrive.com/oauth/access_token，
  /// 而 auth.aliyundrive.com/v2/account/token 只接受 refresh_token 类型。
  Future<String?> loginByCode(String code) async {
    final tokenUrl = 'https://api.aliyundrive.com/oauth/access_token';
    final resp = await _dio.request(
      tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': '25dzX3vbYqktVxyX',
      },
      options: Options(
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        },
        validateStatus: (_) => true,
      ),
    );
    AppLogger.I.http(
      'ali',
      'POST',
      tokenUrl,
      status: resp.statusCode ?? -1,
      cred: 'code',
      body: resp.data,
    );
    final body = _parseBody(resp);
    if (body['access_token'] == null) {
      return body['message']?.toString() ?? '登录失败';
    }
    _accessToken = body['access_token'].toString();
    _refreshToken = body['refresh_token']?.toString() ?? '';
    await refreshUser();
    return null;
  }

  /// 使用 refresh_token 直接登录
  Future<String?> loginByRefreshToken(String token) async {
    _refreshToken = token.trim();
    try {
      await _doRefreshToken();
      await refreshUser();
      return null;
    } on AliException catch (e) {
      _accessToken = '';
      _refreshToken = '';
      return e.message;
    }
  }

  @override
  Future<String?> login(dynamic credential) async {
    if (credential == null) return '缺少凭证';
    if (credential is String) {
      // 尝试作为 refresh_token 登录
      return loginByRefreshToken(credential);
    }
    if (credential is Map) {
      final code = credential['code']?.toString();
      if (code != null) {
        return loginByCode(code);
      }
      final rt = credential['refresh_token']?.toString();
      if (rt != null) {
        return loginByRefreshToken(rt);
      }
    }
    return '不支持的登录凭证类型';
  }

  @override
  Future<void> logout() async {
    _accessToken = '';
    _refreshToken = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    try {
      final body = await _post('$_baseUrl/adrive/v1/user/getUserCapacityInfo');
      final name = body['name']?.toString() ?? body['nickname']?.toString() ?? '';
      final avatar = body['avatar']?.toString() ?? '';
      final uid = body['user_id']?.toString() ?? body['domain_id']?.toString() ?? '';
      _userInfo = DriveUserInfo(
        nickname: name,
        avatar: avatar,
        userId: uid,
      );
    } catch (_) {
      // 刷新用户信息失败时保持旧值
    }
  }

  @override
  Future<void> init() async {
    // 子类调用方在设置 refresh_token 后调用此方法
    if (_refreshToken.isNotEmpty && _accessToken.isEmpty) {
      try {
        await _doRefreshToken();
      } catch (_) {
        // 静默失败，等待用户主动登录
      }
    }
  }

  // ──────────────────── 文件列表 ────────────────────

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final body = await _post('$_baseUrl/adrive/v3/file/list', data: {
      'drive_id': _driveId,
      'parent_file_id': pdirFid,
      'limit': size,
      'marker': page <= 1 ? '' : page.toString(),
      'all': false,
      'image_thumbnail_process': 'image/resize,w_256/format,jpeg',
      'image_url_process': 'image/resize,w_1920/format,jpeg',
      'video_thumbnail_process': 'video/snapshot,t_0,f_jpg,w_256',
      'fields': '*',
      'order_by': 'updated_at',
      'order_direction': 'DESC',
    });

    final items = body['items'];
    if (items is! List) return [];
    final files = items
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseDriveFile(e))
        .toList();

    // 如果有下一页，递归收集（简单实现，最多 5 页）
    if (body['next_marker'] != null && body['next_marker'].toString().isNotEmpty) {
      final marker = body['next_marker'].toString();
      // 将 marker 作为 page 的 next 标识
      if (page < 5) {
        files.addAll(await _listAll(pdirFid, marker, size));
      }
    }
    return files;
  }

  /// 递归拉取全部文件列表
  Future<List<DriveFile>> _listAll(String pdirFid, String marker, int size,
      {int depth = 0}) async {
    if (depth > 5 || marker.isEmpty) return [];
    final body = await _post('$_baseUrl/adrive/v3/file/list', data: {
      'drive_id': _driveId,
      'parent_file_id': pdirFid,
      'limit': size,
      'marker': marker,
      'all': false,
      'fields': '*',
      'order_by': 'updated_at',
      'order_direction': 'DESC',
    });
    final items = body['items'];
    final files = <DriveFile>[];
    if (items is List) {
      files.addAll(items
          .whereType<Map<String, dynamic>>()
          .map((e) => _parseDriveFile(e)));
    }
    final nextMarker = body['next_marker']?.toString() ?? '';
    if (nextMarker.isNotEmpty) {
      files.addAll(await _listAll(pdirFid, nextMarker, size, depth: depth + 1));
    }
    return files;
  }

  String get _driveId {
    // 从 userInfo 或默认空字符串获取
    return '';
  }

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';
    final isDir = type == 'folder';
    return DriveFile(
      fid: json['file_id']?.toString() ?? '',
      fileName: json['name']?.toString() ?? '',
      fileType: type,
      isDir: isDir,
      size: toInt(json['size']),
      pdirFid: json['parent_file_id']?.toString() ?? '',
      fileExt: json['file_extension']?.toString() ?? '',
      updatedAt: toInt(json['updated_at']),
      thumbnail: json['thumbnail']?.toString() ?? '',
      previewUrl: json['url']?.toString() ?? '',
    );
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    // 阿里云盘无独立搜索API，使用 list 替代：通过 name 关键字过滤
    final body = await _post('$_baseUrl/adrive/v3/file/list', data: {
      'drive_id': _driveId,
      'parent_file_id': 'root',
      'limit': size,
      'marker': page <= 1 ? '' : page.toString(),
      'all': false,
      'fields': '*',
      'order_by': 'updated_at',
      'order_direction': 'DESC',
      'name': keyword,
    });
    final items = body['items'];
    if (items is! List) return [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseDriveFile(e))
        .toList();
  }

  // ──────────────────── 下载 ────────────────────

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    if (fids.isEmpty) return [];
    final results = <DriveDownloadInfo>[];
    for (final fid in fids) {
      try {
        final body = await _post('$_baseUrl/v2/file/download', data: {
          'drive_id': _driveId,
          'file_id': fid,
        });
        final url = body['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          results.add(DriveDownloadInfo(
            url: url,
            fileName: '',
            size: 0,
            fid: fid,
          ));
        }
      } catch (_) {
        // 单个文件下载链接获取失败，跳过
      }
    }
    return results;
  }

  // ──────────────────── 分享 ────────────────────

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    final body = await _post('$_baseUrl/v2/share_link/get_share_token', data: {
      'share_id': pwdId,
      'share_pwd': passcode,
    });
    final stoken = body['share_token']?.toString() ?? '';
    if (stoken.isEmpty) {
      throw AliException(-1, '分享链接已失效或提取码错误');
    }
    return DriveShareSession(
      shareId: pwdId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: stoken,
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session,
      String pdirFid,
      {int page = 1, int size = 50}) async {
    final body = await _get(
      '$_baseUrl/adrive/v3/share_link/get_share_by_anonymous',
      params: {
        'share_id': session.shareId,
        'parent_file_id': pdirFid,
        'limit': size,
        'marker': page <= 1 ? '' : page.toString(),
        'order_by': 'updated_at',
        'order_direction': 'DESC',
        if (session.stoken.isNotEmpty) 'share_token': session.stoken,
      },
    );
    final items = body['items'];
    if (items is! List) return [];
    return items
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseShareFile(e, session))
        .toList();
  }

  DriveShareFile _parseShareFile(
      Map<String, dynamic> json, DriveShareSession session) {
    final type = json['type']?.toString() ?? '';
    final isDir = type == 'folder';
    return DriveShareFile(
      fid: json['file_id']?.toString() ?? '',
      fileName: json['name']?.toString() ?? '',
      fileType: type,
      isDir: isDir,
      size: toInt(json['size']),
      pdirFid: json['parent_file_id']?.toString() ?? '',
      shareFidToken: json['share_id']?.toString() ?? session.shareId,
    );
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    if (fidList.isEmpty) return [];
    final results = <DriveDownloadInfo>[];
    for (final fid in fidList) {
      try {
        final body = await _post('$_baseUrl/v2/file/download', data: {
          'drive_id': _driveId,
          'file_id': fid,
          'share_id': session.shareId,
          'share_token': session.stoken,
        });
        final url = body['url']?.toString() ?? '';
        if (url.isNotEmpty) {
          results.add(DriveDownloadInfo(
            url: url,
            fileName: '',
            size: 0,
            fid: fid,
          ));
        }
      } catch (_) {
        // 跳过失败项
      }
    }
    return results;
  }

  @override
  Future<void> saveShare(
    DriveShareSession session,
    List<DriveShareFile> files,
    String toPdirFid,
  ) async {
    // 使用批量操作转存分享文件
    for (final file in files) {
      final body = await _post('$_baseUrl/adrive/v2/batch', data: {
        'requests': [
          {
            'body': {
              'drive_id': _driveId,
              'file_id': file.fid,
              'to_parent_file_id': toPdirFid,
              'to_drive_id': _driveId,
              'share_id': session.shareId,
              'auto_rename': true,
            },
            'headers': {
              'Content-Type': 'application/json',
            },
            'id': file.fid,
            'method': 'POST',
            'url': '/file/copy',
          }
        ],
        'resource': 'file',
      });
      // 检查异步任务状态
      final responses = body['responses'];
      if (responses is List && responses.isNotEmpty) {
        for (final r in responses) {
          if (r is Map && r['body'] is Map) {
            final taskId = (r['body'] as Map)['async_task_id']?.toString();
            if (taskId != null && taskId.isNotEmpty) {
              await _waitAsyncTask(taskId);
            }
          }
        }
      }
    }
  }

  /// 等待异步任务完成
  Future<void> _waitAsyncTask(String taskId, {int maxRetry = 120}) async {
    for (var i = 0; i < maxRetry; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      try {
        final body = await _post('$_baseUrl/adrive/v2/async_task/get', data: {
          'async_task_id': taskId,
        });
        final status = body['status']?.toString() ?? '';
        if (status == 'succeeded' || status == 'success') return;
        if (status == 'failed' || status == 'cancelled') {
          throw AliException(-1, '转存任务失败: ${body['message']}');
        }
      } on AliException {
        rethrow;
      } catch (_) {
        // 网络抖动继续等待
      }
    }
    throw AliException(-1, '转存任务超时');
  }

  // ──────────────────── 其他 API ────────────────────

  /// 创建文件夹
  Future<DriveFile> createFolder(String parentFileId, String name) async {
    final body = await _post('$_baseUrl/adrive/v2/file/createWithFolders',
        data: {
          'drive_id': _driveId,
          'parent_file_id': parentFileId,
          'name': name,
          'check_name_mode': 'refuse',
          'type': 'folder',
        });
    return _parseDriveFile(body);
  }

  /// 更新文件/文件夹信息（重命名、移动等）
  Future<void> updateFile(String fileId, Map<String, dynamic> updateData) async {
    await _post('$_baseUrl/v3/file/update', data: {
      'drive_id': _driveId,
      'file_id': fileId,
      ...updateData,
    });
  }

  /// 删除文件到回收站
  Future<void> trashFile(List<String> fileIds) async {
    await _post('$_baseUrl/v2/recyclebin/trash', data: {
      'drive_id': _driveId,
      'file_id': fileIds.first,
    });
  }

  /// 创建分享链接
  Future<Map<String, dynamic>> createShareLink(
      List<String> fileIds, {String sharePwd = ''}) async {
    final body = await _post('$_baseUrl/adrive/v2/share_link/create', data: {
      'drive_id': _driveId,
      'file_id_list': fileIds,
      'share_pwd': sharePwd,
      'expiration': '',
      'description': '',
    });
    return body;
  }

  /// 批量操作（通用）
  Future<Map<String, dynamic>> batch(
      List<Map<String, dynamic>> requests, {bool useV4 = false}) async {
    final url = '$_baseUrl/${useV4 ? 'adrive/v4/batch' : 'adrive/v2/batch'}';
    final body = await _post(url, data: {
      'requests': requests,
      'resource': 'file',
    });
    return body;
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}