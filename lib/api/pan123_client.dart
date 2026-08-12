import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 123云盘自定义异常
class Pan123Exception implements Exception {
  final int code;
  final String message;

  Pan123Exception(this.code, this.message);

  @override
  String toString() => message;
}

/// 123云盘客户端
///
/// 支持二维码登录、文件管理、分享解析与转存。
/// API 端点基于 123云盘官方文档及抓包分析。
class Pan123Client implements BaseDrive {
  // ---------------- 常量 ----------------

  static const String loginUrl = 'https://login.123pan.com';
  static const String apiUrl = 'https://www.123pan.com';
  static const String shareUrl = 'https://share.123pan.cn';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // ---------------- 内部状态 ----------------

  final Dio _dio;
  String _token = '';
  String _cookie = '';
  DriveUserInfo? _userInfo;

  Pan123Client()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---------------- BaseDrive 接口 ----------------

  @override
  DriveType get type => DriveType.pan123;

  @override
  String get label => '123云盘';

  @override
  bool get hasLogin => _token.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  Future<void> init() async {
    // 从持久化缓存加载凭证（由上层调用方实现存储）
  }

  /// 登录 123云盘。
  ///
  /// [credential] 支持多种方式:
  /// - String: 直接作为 cookie/token 登录
  /// - Map 密码登录: {'account': 'xxx', 'password': 'xxx'}
  /// - Map 二维码: {'qrCode': 'qr_code_token'} 或 {'uniID': 'xxx'}
  ///
  /// 返回 token 字符串，登录失败时返回 null。
  @override
  Future<String?> login(dynamic credential) async {
    // 处理 String 类型（cookie/token 直接登录）
    if (credential is String) {
      if (credential.trim().isEmpty) return null;
      // 尝试作为 token 直接使用
      if (credential.startsWith('token=')) {
        _token = credential.substring(6).trim();
      } else {
        _token = credential.trim();
      }
      try {
        await refreshUser();
        if (_userInfo != null) return _token;
      } catch (_) {
        // token 无效，尝试作为 cookie
        _token = '';
        _cookie = credential.trim();
      }
      return _token.isNotEmpty ? _token : null;
    }

    if (credential is! Map) return null;

    try {
      // 分支：二维码登录
      if (credential['qrCode'] != null) {
        return await _qrCodeLogin(credential['qrCode'].toString());
      }
      if (credential['uniID'] != null) {
        return await _pollQrCodeResult(credential['uniID'].toString());
      }

      // 密码登录
      final account = credential['account']?.toString() ?? '';
      final password = credential['password']?.toString() ?? '';
      if (account.isEmpty || password.isEmpty) return null;

      // 先获取配置
      await _getConfig();

      // 登录 - 使用 user.123pan.cn 域名（与 LoginService 保持一致）
      final resp = await _request(
        'POST',
        'https://user.123pan.cn/api/user/sign_in',
        data: {
          'account': account,
          'password': password,
          'type': account.contains('@') ? 2 : 1, // 1=手机, 2=邮箱
        },
        referer: 'https://www.123pan.com/',
      );
      final body = _parseBody(resp);
      final code = body['code']?.toInt() ?? -1;
      if (code != 0 && code != 200) {
        throw Pan123Exception(code, body['message']?.toString() ?? '登录失败');
      }

      // 提取 token（123云盘 token 可能在 data 或直接返回）
      final data = body['data'];
      if (data is Map) {
        _token = data['token']?.toString() ?? data['accessToken']?.toString() ?? '';
      }
      if (_token.isEmpty) {
        _token = body['token']?.toString() ?? body['accessToken']?.toString() ?? '';
      }

      if (_token.isEmpty) {
        throw Pan123Exception(-1, '登录失败: 未获取到 token');
      }

      await refreshUser();
      return _token;
    } on Pan123Exception {
      rethrow;
    } catch (e) {
      throw Pan123Exception(-1, '登录失败: $e');
    }
  }

  @override
  Future<void> logout() async {
    _token = '';
    _cookie = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (!hasLogin) return;
    try {
      final resp = await _request(
        'GET',
        '$apiUrl/a/api/user/info',
        referer: 'https://www.123pan.com/',
      );
      final body = _parseBody(resp);
      final data = body['data'];
      if (data is Map) {
        _userInfo = DriveUserInfo(
          nickname: data['nickname']?.toString() ?? data['name']?.toString() ?? '',
          avatar: data['avatar']?.toString() ?? data['headUrl']?.toString() ?? '',
          userId: data['userId']?.toString() ?? data['id']?.toString() ?? '',
        );
      }
    } catch (_) {
      // 静默失败
    }
  }

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final files = <DriveFile>[];
    var total = -1;
    while (total < 0 || files.length < total) {
      final resp = await _request(
        'POST',
        '$apiUrl/api/file/list/new',
        data: {
          'driveId': 0,
          'parentFileId': int.tryParse(pdirFid) ?? 0,
          'page': page,
          'limit': size,
          'orderBy': 'updatedAt',
          'orderDirection': 'desc',
          'trash': false,
        },
        referer: 'https://www.123pan.com/',
      );
      final body = _parseBody(resp);
      final code = body['code']?.toInt() ?? -1;
      if (code != 0) break;
      final data = body['data'];
      if (data is! Map) break;
      final fileList = data['fileList'] as List<dynamic>? ?? [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseDriveFile(e.cast<String, dynamic>())));
      total = data['total']?.toInt() ?? -1;
      if (total < 0 && fileList.length < size) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    final resp = await _request(
      'POST',
      '$apiUrl/api/search.php',
      data: {
        'driveId': 0,
        'keyword': keyword,
        'page': page,
        'limit': size,
        'orderBy': 'updatedAt',
        'orderDirection': 'desc',
      },
      referer: 'https://www.123pan.com/',
    );
    final body = _parseBody(resp);
    final data = body['data'];
    if (data is! Map) return [];
    final fileList = data['fileList'] as List<dynamic>? ?? [];
    return fileList
        .whereType<Map>()
        .map((e) => _parseDriveFile(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    final results = <DriveDownloadInfo>[];
    for (final fid in fids) {
      try {
        // 先检查流量
        final trafficResp = await _request(
          'GET',
          '$apiUrl/api/file/download/traffic/check',
          params: {'fileId': fid},
          referer: 'https://www.123pan.com/',
        );
        final trafficBody = _parseBody(trafficResp);
        if (trafficBody['code']?.toInt() != 0) {
          throw Pan123Exception(-1, '下载流量不足或已耗尽');
        }

        // 获取文件信息（含下载链接）
        final infoResp = await _request(
          'GET',
          '$apiUrl/b/api/file/info',
          params: {'fileId': fid},
          referer: 'https://www.123pan.com/',
        );
        final infoBody = _parseBody(infoResp);
        final data = infoBody['data'];
        if (data is! Map) continue;

        results.add(DriveDownloadInfo(
          url: data['downloadUrl']?.toString() ?? '',
          fileName: data['fileName']?.toString() ?? data['name']?.toString() ?? '',
          size: data['size']?.toInt() ?? 0,
          fid: fid,
        ));
      } on Pan123Exception {
        rethrow;
      } catch (_) {
        // 单个文件失败跳过
      }
    }
    return results;
  }

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      final path = uri.path;
      // 123云盘分享链接格式:
      // https://www.123pan.cn/s/xxxxxxxx 或
      // https://www.123pan.com/s/xxxxxxxx 或
      // https://www.123pan.com/123pan/xxxxxxxx
      // 正则: /(?:s|123pan)/([A-Za-z0-9_-]+)
      final sMatch = RegExp(r'/(?:s|123pan)/([A-Za-z0-9_-]+)').firstMatch(path);
      if (sMatch != null) {
        pwdId = sMatch.group(1) ?? '';
      }
      passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['code'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(
      String pwdId, String passcode) async {
    // 123云盘分享信息通过 share.123pan.cn 获取
    final resp = await _request(
      'POST',
      '$shareUrl/share/info',
      data: {
        'shareKey': pwdId,
        'shareCode': passcode,
      },
      referer: 'https://www.123pan.com/',
    );
    final body = _parseBody(resp);
    final code = body['code']?.toInt() ?? -1;
    if (code != 0) {
      throw Pan123Exception(code, body['message']?.toString() ?? '分享链接无效或已过期');
    }
    final data = body['data'];
    final shareId = data is Map ? (data['shareId']?.toString() ?? pwdId) : pwdId;
    final stoken = data is Map ? (data['shareToken']?.toString() ?? '') : '';

    return DriveShareSession(
      shareId: shareId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: stoken,
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session,
      String pdirFid,
      {int page = 1, int size = 50}) async {
    final files = <DriveShareFile>[];
    var total = -1;
    while (total < 0 || files.length < total) {
      final resp = await _request(
        'POST',
        '$shareUrl/share/list',
        data: {
          'shareKey': session.pwdId,
          'shareCode': session.passcode,
          'parentFileId': int.tryParse(pdirFid) ?? 0,
          'page': page,
          'limit': size,
          'orderBy': 'updatedAt',
          'orderDirection': 'desc',
        },
        referer: 'https://www.123pan.com/',
      );
      final body = _parseBody(resp);
      if (body['code']?.toInt() != 0) break;
      final data = body['data'];
      if (data is! Map) break;
      final fileList = data['fileList'] as List<dynamic>? ?? [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseShareFile(e.cast<String, dynamic>())));
      total = data['total']?.toInt() ?? -1;
      if (total < 0 && fileList.length < size) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    final results = <DriveDownloadInfo>[];
    for (final fid in fidList) {
      try {
        final resp = await _request(
          'POST',
          '$shareUrl/share/download/info',
          data: {
            'shareKey': session.pwdId,
            'shareCode': session.passcode,
            'fileId': int.tryParse(fid) ?? 0,
          },
          referer: 'https://www.123pan.com/',
        );
        final body = _parseBody(resp);
        if (body['code']?.toInt() != 0) continue;
        final data = body['data'];
        if (data is! Map) continue;

        results.add(DriveDownloadInfo(
          url: data['downloadUrl']?.toString() ?? '',
          fileName: data['fileName']?.toString() ?? data['name']?.toString() ?? '',
          size: data['size']?.toInt() ?? 0,
          fid: fid,
        ));
      } catch (_) {
        // 单个文件失败跳过
      }
    }
    return results;
  }

  @override
  Future<void> saveShare(DriveShareSession session,
      List<DriveShareFile> files, String toPdirFid) async {
    // 123云盘转存
    final resp = await _request(
      'POST',
      '$shareUrl/share/save',
      data: {
        'shareKey': session.pwdId,
        'shareCode': session.passcode,
        'fileIdList': files.map((f) => int.tryParse(f.fid) ?? 0).toList(),
        'targetParentId': int.tryParse(toPdirFid) ?? 0,
      },
      referer: 'https://www.123pan.com/',
    );
    final body = _parseBody(resp);
    if (body['code']?.toInt() != 0) {
      throw Pan123Exception(
          body['code']?.toInt() ?? -1,
          body['message']?.toString() ?? '转存失败');
    }
  }

  @override
  void dispose() {
    _dio.close();
  }

  // ---------------- 内部请求方法 ----------------

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? referer,
  }) async {
    final headers = <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent': uaPc,
      'Referer': referer ?? 'https://www.123pan.com/',
      'Platform': 'web',
      if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
    };
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
    _mergeSetCookie(resp);
    return resp;
  }

  void _mergeSetCookie(Response<dynamic> resp) {
    final setCookies = resp.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    final entries = <String, String>{};
    for (final raw in setCookies) {
      final seg = raw.split(';').first.trim();
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      entries[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
    }
    if (entries.isEmpty) return;
    final kept = <String>[];
    for (final part in _cookie.split(';')) {
      final k = part.trim().split('=').first;
      if (entries.containsKey(k)) continue;
      if (part.trim().isNotEmpty) kept.add(part.trim());
    }
    for (final e in entries.entries) {
      kept.add('${e.key}=${e.value}');
    }
    _cookie = kept.join('; ');
  }

  Map<String, dynamic> _parseBody(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  // ---------------- 二维码登录 ----------------

  /// 生成二维码并返回 uniID，用于后续轮询
  Future<Map<String, dynamic>> generateQrCode() async {
    final resp = await _request(
      'POST',
      '$loginUrl/api/user/qr-code/generate',
      data: {},
      referer: 'https://www.123pan.com/',
    );
    final body = _parseBody(resp);
    final data = body['data'];
    if (data is! Map) {
      throw Pan123Exception(-1, '生成二维码失败');
    }
    return data.cast<String, dynamic>();
  }

  /// 轮询二维码扫码结果（内部使用）
  Future<String?> _pollQrCodeResult(String uniID) async {
    const maxRetry = 120;
    for (var i = 0; i < maxRetry; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      try {
        final resp = await _request(
          'GET',
          '$loginUrl/api/user/qr-code/result',
          params: {'uniID': uniID},
          referer: 'https://www.123pan.com/',
        );
        final body = _parseBody(resp);
        final code = body['code']?.toInt() ?? -1;
        if (code == 0) {
          final data = body['data'];
          if (data is Map) {
            _token = data['token']?.toString() ?? data['accessToken']?.toString() ?? '';
          }
          if (_token.isNotEmpty) {
            await refreshUser();
            return _token;
          }
        }
        // status: 0=等待扫码, 1=已扫码待确认, 2=已过期
        final status = body['status']?.toInt() ?? -1;
        if (status == 2) break;
      } catch (_) {
        // 继续轮询
      }
    }
    return null;
  }

  /// 二维码登录入口（生成并返回二维码信息）
  Future<String?> _qrCodeLogin(String qrCode) async {
    // 如果传入的是二维码数据，先生成 uniID
    final generateResp = await _request(
      'POST',
      '$loginUrl/api/user/qr-code/generate',
      data: {},
      referer: 'https://www.123pan.com/',
    );
    final generateBody = _parseBody(generateResp);
    final data = generateBody['data'];
    if (data is! Map) {
      throw Pan123Exception(-1, '生成二维码失败');
    }
    final uniID = data['uniID']?.toString() ?? '';
    if (uniID.isEmpty) {
      throw Pan123Exception(-1, '获取 uniID 失败');
    }
    return await _pollQrCodeResult(uniID);
  }

  /// 获取配置信息
  Future<Map<String, dynamic>> _getConfig() async {
    final resp = await _request(
      'GET',
      '$apiUrl/api/v1/config',
      referer: 'https://www.123pan.com/',
    );
    final body = _parseBody(resp);
    return body;
  }

  // ---------------- 模型解析 ----------------

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['type']?.toInt() ?? 0;
    final dirFlag = type == 1 || json['isFolder'] == true;
    return DriveFile(
      fid: json['fileId']?.toString() ?? json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type == 1 ? 'folder' : 'file',
      isDir: dirFlag,
      size: json['size']?.toInt() ?? 0,
      pdirFid: json['parentFileId']?.toString() ?? json['parentId']?.toString() ?? '0',
      fileExt: json['fileExt']?.toString() ?? json['ext']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toInt() ?? json['updateTime']?.toInt() ?? 0,
      thumbnail: json['thumbnail']?.toString() ?? json['thumb']?.toString() ?? '',
      previewUrl: json['previewUrl']?.toString() ?? '',
    );
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final type = json['type']?.toInt() ?? 0;
    final dirFlag = type == 1 || json['isFolder'] == true;
    return DriveShareFile(
      fid: json['fileId']?.toString() ?? json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type == 1 ? 'folder' : 'file',
      isDir: dirFlag,
      size: json['size']?.toInt() ?? 0,
      pdirFid: json['parentFileId']?.toString() ?? '',
      shareFidToken: json['shareFidToken']?.toString() ?? json['shareToken']?.toString() ?? '',
    );
  }
}