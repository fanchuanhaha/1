import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 移动云盘（139 / 和彩云）自定义异常
class YiDongException implements Exception {
  final int code;
  final String message;

  YiDongException(this.code, this.message);

  @override
  String toString() => message;
}

/// 移动云盘（139 / 和彩云）客户端
///
/// API 端点基于 APK 反编译提取。移动云盘与天翼云盘（cloud.189.cn）属于同一集团
/// 但不同系统，部分文件管理接口设计相似，使用 cookie 认证。
///
/// 核心端点:
/// - 门户: https://caiyun.139.com
/// - 登录页: https://e.dlife.cn/wap/mine/showIndex.do
/// - 文件管理: 与 cloud.189.cn 类似
class YiDongClient implements BaseDrive {
  // ---------------- 常量 ----------------

  static const String portalUrl = 'https://caiyun.139.com';
  static const String loginPageUrl =
      'https://e.dlife.cn/wap/mine/showIndex.do';
  static const String apiUrl = 'https://caiyun.139.com';

  static const String uaMobile =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // ---------------- 内部状态 ----------------

  final Dio _dio;
  String _cookie = '';
  bool _isLoggedIn = false;
  DriveUserInfo? _userInfo;

  YiDongClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---------------- BaseDrive 接口 ----------------

  @override
  DriveType get type => DriveType.yidong;

  @override
  String get label => '移动云盘';

  @override
  bool get hasLogin => _isLoggedIn && _cookie.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie => _cookie.isEmpty ? null : _cookie;

  @override
  Future<void> init() async {
    // 从持久化缓存加载凭证（由上层调用方实现存储）
  }

  /// 使用密码登录移动云盘。
  ///
  /// [credential] 为 Map，需包含:
  /// - 'account': 手机号
  /// - 'password': 密码
  /// - 可选 'smsCode': 短信验证码
  ///
  /// 返回用户标识字符串，登录失败时返回 null。
  @override
  Future<String?> login(dynamic credential) async {
    if (credential is! Map) return null;
    final account = credential['account']?.toString() ?? '';
    final password = credential['password']?.toString() ?? '';
    if (account.isEmpty || password.isEmpty) return null;

    try {
      // 1. 访问登录页面获取初始 cookie
      await _request(
        'GET',
        loginPageUrl,
        referer: portalUrl,
      );

      // 2. 提交登录表单
      final loginResp = await _request(
        'POST',
        '$portalUrl/api/login',
        data: {
          'account': account,
          'password': password,
          'rememberMe': true,
        },
        referer: loginPageUrl,
        contentType: 'application/x-www-form-urlencoded',
      );
      final body = _parseBody(loginResp);
      final resultCode = body['resultCode']?.toInt() ?? body['code']?.toInt() ?? -1;

      if (resultCode != 0) {
        final msg = body['message']?.toString() ?? body['msg']?.toString() ?? '登录失败';
        if (resultCode == 1 || resultCode == 1001) {
          // 需要短信验证码
          if (credential['smsCode'] != null) {
            return await _submitSmsCode(
                account, credential['smsCode'].toString());
          }
          await _sendSmsCode(account);
          return 'sms_required';
        }
        throw YiDongException(resultCode, msg);
      }

      // 3. 登录成功
      _isLoggedIn = true;

      // 4. 刷新用户信息
      await refreshUser();

      return account;
    } on YiDongException {
      rethrow;
    } catch (e) {
      throw YiDongException(-1, '登录失败: $e');
    }
  }

  /// 提交短信验证码完成登录
  Future<String> _submitSmsCode(String account, String smsCode) async {
    final resp = await _request(
      'POST',
      '$portalUrl/api/login/sms',
      data: {
        'account': account,
        'smsCode': smsCode,
      },
      referer: loginPageUrl,
      contentType: 'application/x-www-form-urlencoded',
    );
    final body = _parseBody(resp);
    final resultCode = body['resultCode']?.toInt() ?? body['code']?.toInt() ?? -1;
    if (resultCode != 0) {
      throw YiDongException(resultCode, '短信验证失败: ${body['message']}');
    }
    _isLoggedIn = true;
    await refreshUser();
    return account;
  }

  /// 发送短信验证码
  Future<void> _sendSmsCode(String account) async {
    await _request(
      'POST',
      '$portalUrl/api/login/sendSms',
      data: {'account': account},
      referer: loginPageUrl,
      contentType: 'application/x-www-form-urlencoded',
    );
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _isLoggedIn = false;
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (!hasLogin) return;
    try {
      final resp = await _request(
        'GET',
        '$apiUrl/api/user/info',
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      if (body['resultCode']?.toInt() == 0 ||
          body['code']?.toInt() == 0) {
        final userData = body['data'] as Map<String, dynamic>? ?? body;
        _userInfo = DriveUserInfo(
          nickname: userData['nickname']?.toString() ??
              userData['nickName']?.toString() ??
              '',
          avatar: userData['avatar']?.toString() ??
              userData['headPic']?.toString() ??
              '',
          userId: userData['userId']?.toString() ??
              userData['account']?.toString() ??
              '',
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
        'GET',
        '$apiUrl/api/file/list',
        params: {
          'folderId': pdirFid,
          'pageNum': page,
          'pageSize': size,
          'orderBy': 'lastOpTime',
          'order': 'DESC',
        },
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      final data = body['data'] as Map<String, dynamic>? ?? body;
      final fileList = data['fileList'] as List<dynamic>? ??
          data['list'] as List<dynamic>? ??
          [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseDriveFile(e.cast<String, dynamic>())));
      total = data['recordCount']?.toInt() ?? data['total']?.toInt() ?? -1;
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
      'GET',
      '$apiUrl/api/file/search',
      params: {
        'keyword': keyword,
        'pageNum': page,
        'pageSize': size,
      },
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    final data = body['data'] as Map<String, dynamic>? ?? body;
    final fileList = data['fileList'] as List<dynamic>? ??
        data['list'] as List<dynamic>? ??
        [];
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
        final resp = await _request(
          'GET',
          '$apiUrl/api/file/download',
          params: {'fileId': fid},
          referer: portalUrl,
        );
        final body = _parseBody(resp);
        final data = body['data'] as Map<String, dynamic>? ?? body;
        results.add(DriveDownloadInfo(
          url: data['downloadUrl']?.toString() ??
              data['url']?.toString() ??
              '',
          fileName: data['fileName']?.toString() ??
              data['name']?.toString() ??
              '',
          size: data['fileSize']?.toInt() ?? 0,
          fid: fid,
        ));
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
      // 移动云盘分享链接格式:
      // https://caiyun.139.com/share/xxxxxxxx
      // https://caiyun.139.com/s/xxxxxxxx
      final path = uri.path;
      final shareIdx = path.lastIndexOf('/share/');
      if (shareIdx >= 0) {
        pwdId = path.substring(shareIdx + 7);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      if (pwdId.isEmpty) {
        final sIdx = path.lastIndexOf('/s/');
        if (sIdx >= 0) {
          pwdId = path.substring(sIdx + 3);
          final slash = pwdId.indexOf('/');
          if (slash > 0) pwdId = pwdId.substring(0, slash);
        }
      }
      passcode = uri.queryParameters['code'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(
      String pwdId, String passcode) async {
    // 获取分享信息
    final resp = await _request(
      'GET',
      '$apiUrl/api/share/info',
      params: {'shareCode': pwdId},
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    final data = body['data'] as Map<String, dynamic>? ?? body;
    final shareId = data['shareId']?.toString() ?? '';

    if (shareId.isEmpty) {
      throw YiDongException(-1, '分享链接无效或已过期');
    }

    // 检查是否需要提取码
    if (passcode.isNotEmpty) {
      final verifyResp = await _request(
        'POST',
        '$apiUrl/api/share/verify',
        data: {
          'shareCode': pwdId,
          'accessCode': passcode,
        },
        referer: portalUrl,
        contentType: 'application/x-www-form-urlencoded',
      );
      final verifyBody = _parseBody(verifyResp);
      if (verifyBody['resultCode']?.toInt() != 0 &&
          verifyBody['code']?.toInt() != 0) {
        throw YiDongException(-1, '提取码错误');
      }
    }

    return DriveShareSession(
      shareId: shareId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: '',
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
        'GET',
        '$apiUrl/api/share/list',
        params: {
          'shareCode': session.pwdId,
          'accessCode': session.passcode,
          'folderId': pdirFid,
          'pageNum': page,
          'pageSize': size,
        },
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      final data = body['data'] as Map<String, dynamic>? ?? body;
      final fileList = data['fileList'] as List<dynamic>? ??
          data['list'] as List<dynamic>? ??
          [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseShareFile(e.cast<String, dynamic>())));
      total = data['recordCount']?.toInt() ?? data['total']?.toInt() ?? -1;
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
          'GET',
          '$apiUrl/api/share/download',
          params: {
            'shareCode': session.pwdId,
            'accessCode': session.passcode,
            'fileId': fid,
          },
          referer: portalUrl,
        );
        final body = _parseBody(resp);
        final data = body['data'] as Map<String, dynamic>? ?? body;
        results.add(DriveDownloadInfo(
          url: data['downloadUrl']?.toString() ??
              data['url']?.toString() ??
              '',
          fileName: data['fileName']?.toString() ??
              data['name']?.toString() ??
              '',
          size: data['fileSize']?.toInt() ?? 0,
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
    final fidList = files.map((f) => f.fid).toList();
    final resp = await _request(
      'POST',
      '$apiUrl/api/share/save',
      data: {
        'shareCode': session.pwdId,
        'accessCode': session.passcode,
        'fileIds': fidList.join(','),
        'targetFolderId': toPdirFid,
      },
      referer: portalUrl,
      contentType: 'application/x-www-form-urlencoded',
    );
    final body = _parseBody(resp);
    final resultCode = body['resultCode']?.toInt() ?? body['code']?.toInt() ?? -1;
    if (resultCode != 0) {
      throw YiDongException(
          resultCode, '转存失败: ${body['message'] ?? body['msg']}');
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
    String? contentType,
  }) async {
    final headers = <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': uaMobile,
      'Referer': referer ?? portalUrl,
      if (contentType != null) 'Content-Type': contentType,
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
    };
    if (contentType == null && data != null) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
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
    AppLogger.I.http(
      'yidong',
      method,
      url,
      status: resp.statusCode ?? -1,
      cred: _cookie,
      body: resp.data,
    );
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

  // ---------------- 模型解析 ----------------

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['fileType']?.toString() ?? '';
    final dirFlag = json['isFolder']?.toInt() == 1 ||
        json['isFolder'] == true ||
        json['isDir'] == true;
    return DriveFile(
      fid: json['fileId']?.toString() ??
          json['id']?.toString() ??
          json['fid']?.toString() ??
          '',
      fileName: json['fileName']?.toString() ??
          json['name']?.toString() ??
          '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: json['fileSize']?.toInt() ?? 0,
      pdirFid: json['parentFolderId']?.toString() ??
          json['folderId']?.toString() ??
          json['pdirFid']?.toString() ??
          '',
      fileExt: json['fileExt']?.toString() ?? '',
      updatedAt: json['lastOpTime']?.toInt() ??
          json['createDate']?.toInt() ??
          json['updatedAt']?.toInt() ??
          0,
      thumbnail: json['icon']?.toString() ??
          json['thumbnail']?.toString() ??
          '',
      previewUrl: json['previewUrl']?.toString() ?? '',
    );
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final type = json['fileType']?.toString() ?? '';
    final dirFlag = json['isFolder']?.toInt() == 1 ||
        json['isFolder'] == true ||
        json['isDir'] == true;
    return DriveShareFile(
      fid: json['fileId']?.toString() ??
          json['id']?.toString() ??
          json['fid']?.toString() ??
          '',
      fileName: json['fileName']?.toString() ??
          json['name']?.toString() ??
          '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: json['fileSize']?.toInt() ?? 0,
      pdirFid: json['parentFolderId']?.toString() ??
          json['folderId']?.toString() ??
          '',
      shareFidToken: json['shareFileToken']?.toString() ??
          json['shareFidToken']?.toString() ??
          '',
    );
  }
}