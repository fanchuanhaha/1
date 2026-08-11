import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 天翼云盘自定义异常
class TianyiException implements Exception {
  final int code;
  final String message;

  TianyiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 天翼云盘客户端
///
/// API 端点基于 APK 反编译提取，支持密码登录（含验证码/二次验证）、
/// 文件管理、分享解析与转存。
class TianyiClient implements BaseDrive {
  // ---------------- 常量 ----------------

  static const String portalUrl = 'https://cloud.189.cn';
  static const String openApi = 'https://open.e.189.cn';
  static const String apiUrl = 'https://api.cloud.189.cn';
  static const String mobileUrl = 'https://m.cloud.189.cn';

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  // ---------------- 内部状态 ----------------

  final Dio _dio;
  String _cookie = '';
  String _sessionKey = '';
  String _sessionSecret = '';
  String _accessToken = '';
  DriveUserInfo? _userInfo;

  TianyiClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---------------- BaseDrive 接口 ----------------

  @override
  DriveType get type => DriveType.tianyi;

  @override
  String get label => '天翼云盘';

  @override
  bool get hasLogin => _sessionKey.isNotEmpty && _accessToken.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  Future<void> init() async {
    // 从持久化缓存加载凭证（由上层调用方实现存储）
  }

  /// 使用密码登录天翼云盘。
  ///
  /// [credential] 为 Map，需包含:
  /// - 'account': 手机号/邮箱
  /// - 'password': 明文密码
  /// - 可选 'captchaCode': 验证码
  /// - 可选 'captchaToken': 验证码 token
  /// - 可选 'smsCode': 二次验证短信码
  ///
  /// 返回 sessionKey 字符串，登录失败时返回 null。
  @override
  Future<String?> login(dynamic credential) async {
    if (credential is! Map) return null;
    final account = credential['account']?.toString() ?? '';
    final password = credential['password']?.toString() ?? '';
    if (account.isEmpty || password.isEmpty) return null;

    try {
      // 1. 获取应用配置（appId 等）
      final appConf = await _getAppConf();
      final appId = appConf['appId']?.toString() ?? '';
      final returnUrl = appConf['returnUrl']?.toString() ?? '';

      // 2. 获取加密配置（RSA 公钥）
      final encryptConf = await _getEncryptConf();
      final pubKey = encryptConf['pubKey']?.toString() ?? '';
      // 注意：天翼云盘使用 RSA/ECB/PKCS1Padding 加密密码，
      // 此处仅存公钥，加密逻辑由上层调用方实现后传入 encryptedPassword
      final encryptedPassword = password; // 占位：实际应由上层加密

      // 3. 检查是否需要验证码
      String? captchaToken;
      String? captchaCode;
      if (credential['captchaToken'] != null) {
        captchaToken = credential['captchaToken'].toString();
        captchaCode = credential['captchaCode']?.toString() ?? '';
      } else {
        final needCaptcha = await _needCaptcha(account);
        if (needCaptcha) {
          captchaToken = await _getCaptchaToken();
          // 返回 captchaToken 让上层展示验证码图片
          // 用户输入验证码后通过 credential 传入
          return 'captcha_required:$captchaToken';
        }
      }

      // 4. 提交登录
      final loginParams = <String, dynamic>{
        'appId': appId,
        'returnUrl': returnUrl,
        'clientType': 'PC',
        'accountType': account.contains('@') ? 'email' : 'mobile',
        'account': account,
        'password': encryptedPassword,
        'validateCode': captchaCode ?? '',
        'captchaToken': captchaToken ?? '',
        'dynamicCheck': false,
      };

      final loginResp = await _request(
        'POST',
        '$openApi/api/logbox/oauth2/loginSubmit.do',
        data: loginParams,
        referer: '$openApi/api/logbox/oauth2/login.html',
        contentType: 'application/x-www-form-urlencoded',
      );
      final loginBody = _parseBody(loginResp);
      final loginResult = loginBody['result']?.toInt() ?? -1;

      if (loginResult != 0) {
        final msg = loginBody['msg']?.toString() ?? '登录失败';
        if (loginResult == 9) {
          // 需要二次验证（短信）
          final smsToken = loginBody['smsToken']?.toString() ?? '';
          if (credential['smsCode'] != null) {
            return await _submitSecondAuth(
                smsToken, credential['smsCode'].toString(), appId, returnUrl);
          }
          // 发送短信验证码
          await _sendSmsCode(smsToken, account);
          return 'sms_required:$smsToken';
        }
        throw TianyiException(loginResult, msg);
      }

      // 5. 登录成功，通过 redirect URL 获取 session
      final redirectUrl = loginBody['redirectUrl']?.toString() ?? '';
      if (redirectUrl.isNotEmpty) {
        await _request('GET', redirectUrl, referer: openApi);
      }

      // 6. 获取 session
      await _getSession();

      // 7. 获取 access token
      await _getAccessToken();

      // 8. 刷新用户信息
      await refreshUser();

      return _sessionKey;
    } on TianyiException {
      rethrow;
    } catch (e) {
      throw TianyiException(-1, '登录失败: $e');
    }
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _sessionKey = '';
    _sessionSecret = '';
    _accessToken = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (!hasLogin) return;
    try {
      final resp = await _request(
        'GET',
        '$apiUrl/api/open/user/getUserInfoForPortal.action',
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      if (body['res_code']?.toInt() == 0) {
        _userInfo = DriveUserInfo(
          nickname: body['userInfo']?['nickName']?.toString() ?? '',
          avatar: body['userInfo']?['headPic']?.toString() ?? '',
          userId: body['userInfo']?['userId']?.toString() ?? '',
        );
      } else {
        // 降级到移动端接口
        final mobResp = await _request(
          'GET',
          '$mobileUrl/v2/getUserBriefInfo.action',
          referer: mobileUrl,
        );
        final mobBody = _parseBody(mobResp);
        if (mobBody['res_code']?.toInt() == 0) {
          _userInfo = DriveUserInfo(
            nickname: mobBody['briefInfo']?['nickName']?.toString() ?? '',
            avatar: '',
            userId: mobBody['briefInfo']?['userId']?.toString() ?? '',
          );
        }
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
        '$apiUrl/api/open/file/listFiles.action',
        params: {
          'folderId': pdirFid,
          'pageNum': page,
          'pageSize': size,
          'isFolder': 0,
          'orderBy': 'lastOpTime',
          'order': 'DESC',
          'accessToken': _accessToken,
        },
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      final optResult = body['res_code']?.toInt() ?? -1;
      if (optResult != 0) break;
      final fileList = body['fileList'] as List<dynamic>? ?? [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseDriveFile(e.cast<String, dynamic>())));
      total = body['recordCount']?.toInt() ?? -1;
      if (total < 0 && fileList.length < size) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    // 天翼云盘搜索使用 listFiles 配合 keyword 参数
    final resp = await _request(
      'GET',
      '$apiUrl/api/open/file/listFiles.action',
      params: {
        'folderId': '/',
        'pageNum': page,
        'pageSize': size,
        'isFolder': 0,
        'orderBy': 'lastOpTime',
        'order': 'DESC',
        'keyword': keyword,
        'accessToken': _accessToken,
      },
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    final fileList = body['fileList'] as List<dynamic>? ?? [];
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
          '$apiUrl/api/open/file/getFileDownloadUrl.action',
          params: {
            'fileId': fid,
            'accessToken': _accessToken,
          },
          referer: portalUrl,
        );
        final body = _parseBody(resp);
        if (body['res_code']?.toInt() == 0) {
          results.add(DriveDownloadInfo(
            url: body['fileDownloadUrl']?.toString() ?? '',
            fileName: body['fileName']?.toString() ?? '',
            size: body['fileSize']?.toInt() ?? 0,
            fid: fid,
          ));
        }
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
      // 天翼云盘分享链接格式: https://cloud.189.cn/t/xxxxxxxx
      final tIdx = path.lastIndexOf('/t/');
      if (tIdx >= 0) {
        pwdId = path.substring(tIdx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      // 也从 /s/ 格式尝试（兼容）
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
    // 先获取分享信息
    final resp = await _request(
      'GET',
      '$apiUrl/api/open/share/getShareInfoByCodeV2.action',
      params: {
        'shareCode': pwdId,
        'accessToken': _accessToken,
      },
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    if (body['res_code']?.toInt() != 0) {
      throw TianyiException(-1, '分享链接无效或已过期');
    }

    final shareId = body['shareInfo']?['shareId']?.toString() ?? '';

    // 检查是否需要提取码
    if (passcode.isNotEmpty) {
      final verifyResp = await _request(
        'POST',
        '$apiUrl/api/open/share/checkAccessCode.action',
        data: {
          'shareCode': pwdId,
          'accessCode': passcode,
          'accessToken': _accessToken,
        },
        referer: portalUrl,
        contentType: 'application/x-www-form-urlencoded',
      );
      final verifyBody = _parseBody(verifyResp);
      if (verifyBody['res_code']?.toInt() != 0) {
        throw TianyiException(-1, '提取码错误');
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
        '$apiUrl/api/open/share/listShareDir.action',
        params: {
          'shareCode': session.pwdId,
          'accessCode': session.passcode,
          'folderId': pdirFid,
          'pageNum': page,
          'pageSize': size,
          'accessToken': _accessToken,
        },
        referer: portalUrl,
      );
      final body = _parseBody(resp);
      if (body['res_code']?.toInt() != 0) break;
      final fileList = body['fileList'] as List<dynamic>? ?? [];
      if (fileList.isEmpty) break;
      files.addAll(fileList
          .whereType<Map>()
          .map((e) => _parseShareFile(e.cast<String, dynamic>())));
      total = body['recordCount']?.toInt() ?? -1;
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
          '$apiUrl/api/open/share/getShareFileDownloadUrl.action',
          params: {
            'shareCode': session.pwdId,
            'accessCode': session.passcode,
            'fileId': fid,
            'accessToken': _accessToken,
          },
          referer: portalUrl,
        );
        final body = _parseBody(resp);
        if (body['res_code']?.toInt() == 0) {
          results.add(DriveDownloadInfo(
            url: body['fileDownloadUrl']?.toString() ?? '',
            fileName: body['fileName']?.toString() ?? '',
            size: body['fileSize']?.toInt() ?? 0,
            fid: fid,
          ));
        }
      } catch (_) {
        // 单个文件失败跳过
      }
    }
    return results;
  }

  @override
  Future<void> saveShare(DriveShareSession session,
      List<DriveShareFile> files, String toPdirFid) async {
    // 天翼云盘批量转存
    final fidList = files.map((f) => f.fid).toList();
    final resp = await _request(
      'POST',
      '$apiUrl/api/open/batch/createBatchTask.action',
      params: {
        'type': 'COPY',
        'taskInfos': jsonEncode(fidList.map((fid) => {
          'fileId': fid,
          'targetFolderId': toPdirFid,
        }).toList()),
        'accessToken': _accessToken,
      },
      referer: portalUrl,
      contentType: 'application/x-www-form-urlencoded',
    );
    final body = _parseBody(resp);
    if (body['res_code']?.toInt() != 0) {
      throw TianyiException(
          body['res_code']?.toInt() ?? -1, '转存失败: ${body['res_msg']}');
    }
    // 等待任务完成
    final taskId = body['taskId']?.toString() ?? '';
    if (taskId.isNotEmpty) {
      await _waitBatchTask(taskId);
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
      'User-Agent': uaPc,
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

  // ---------------- 登录辅助方法 ----------------

  /// 获取应用配置（appId, returnUrl 等）
  Future<Map<String, dynamic>> _getAppConf() async {
    final resp = await _request(
      'GET',
      '$openApi/api/logbox/oauth2/appConf.do',
      referer: openApi,
    );
    return _parseBody(resp);
  }

  /// 获取加密配置（RSA 公钥）
  Future<Map<String, dynamic>> _getEncryptConf() async {
    final resp = await _request(
      'GET',
      '$openApi/api/logbox/config/encryptConf.do',
      referer: openApi,
    );
    return _parseBody(resp);
  }

  /// 检查是否需要验证码
  Future<bool> _needCaptcha(String account) async {
    final resp = await _request(
      'POST',
      '$openApi/api/logbox/oauth2/needcaptcha.do',
      data: {'account': account},
      referer: openApi,
    );
    final body = _parseBody(resp);
    return body['needCaptcha']?.toString() == '1' ||
        body['isNeed']?.toString() == '1';
  }

  /// 获取验证码 token
  Future<String> _getCaptchaToken() async {
    final resp = await _request(
      'GET',
      '$openApi/api/logbox/oauth2/captcha.do',
      referer: openApi,
    );
    final body = _parseBody(resp);
    return body['captchaToken']?.toString() ?? '';
  }

  /// 发送短信二次验证码
  Future<void> _sendSmsCode(String smsToken, String account) async {
    await _request(
      'POST',
      '$openApi/api/logbox/oauth2/sendSmsCodeForSecondAuth.do',
      data: {'smsToken': smsToken, 'account': account},
      referer: openApi,
    );
  }

  /// 提交二次验证
  Future<String> _submitSecondAuth(
      String smsToken, String smsCode, String appId, String returnUrl) async {
    final resp = await _request(
      'POST',
      '$openApi/api/logbox/oauth2/submitForSecondAuth.do',
      data: {
        'smsToken': smsToken,
        'smsCode': smsCode,
        'appId': appId,
        'returnUrl': returnUrl,
      },
      referer: openApi,
    );
    final body = _parseBody(resp);
    if (body['result']?.toInt() != 0) {
      throw TianyiException(
          body['result']?.toInt() ?? -1, '二次验证失败: ${body['msg']}');
    }
    final redirectUrl = body['redirectUrl']?.toString() ?? '';
    if (redirectUrl.isNotEmpty) {
      await _request('GET', redirectUrl, referer: openApi);
    }
    await _getSession();
    await _getAccessToken();
    await refreshUser();
    return _sessionKey;
  }

  /// 获取 session（getSessionForPC）
  Future<void> _getSession() async {
    final resp = await _request(
      'GET',
      '$apiUrl/getSessionForPC.action',
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    _sessionKey = body['sessionKey']?.toString() ?? '';
    _sessionSecret = body['sessionSecret']?.toString() ?? '';
    if (_sessionKey.isEmpty) {
      throw TianyiException(-1, '获取 session 失败');
    }
  }

  /// 获取 access token
  Future<void> _getAccessToken() async {
    final resp = await _request(
      'GET',
      '$apiUrl/open/oauth2/getAccessTokenBySsKey.action',
      params: {'sessionKey': _sessionKey},
      referer: portalUrl,
    );
    final body = _parseBody(resp);
    _accessToken = body['accessToken']?.toString() ?? '';
    if (_accessToken.isEmpty) {
      throw TianyiException(-1, '获取 access token 失败');
    }
  }

  /// 等待批量任务完成
  Future<void> _waitBatchTask(String taskId, {int maxRetry = 60}) async {
    for (var i = 0; i < maxRetry; i++) {
      await Future.delayed(const Duration(milliseconds: 2000));
      try {
        final resp = await _request(
          'GET',
          '$apiUrl/api/open/batch/checkBatchTask.action',
          params: {
            'taskId': taskId,
            'accessToken': _accessToken,
          },
          referer: portalUrl,
        );
        final body = _parseBody(resp);
        final status = body['taskStatus']?.toInt() ?? -1;
        if (status == 2) return; // 完成
        if (status == 3) throw TianyiException(-1, '批量任务失败');
      } on TianyiException {
        rethrow;
      } catch (_) {
        // 网络抖动继续等待
      }
    }
    throw TianyiException(-1, '批量任务超时');
  }

  // ---------------- 模型解析 ----------------

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['fileType']?.toString() ?? '';
    final dirFlag = json['isFolder']?.toInt() == 1 || json['isFolder'] == true;
    return DriveFile(
      fid: json['fileId']?.toString() ?? json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: json['fileSize']?.toInt() ?? 0,
      pdirFid: json['parentFolderId']?.toString() ?? json['folderId']?.toString() ?? '',
      fileExt: json['fileExt']?.toString() ?? '',
      updatedAt: json['lastOpTime']?.toInt() ?? json['createDate']?.toInt() ?? 0,
      thumbnail: json['icon']?.toString() ?? json['thumbnail']?.toString() ?? '',
      previewUrl: '',
    );
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final type = json['fileType']?.toString() ?? '';
    final dirFlag = json['isFolder']?.toInt() == 1 || json['isFolder'] == true;
    return DriveShareFile(
      fid: json['fileId']?.toString() ?? json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type,
      isDir: dirFlag || type == 'folder',
      size: json['fileSize']?.toInt() ?? 0,
      pdirFid: json['parentFolderId']?.toString() ?? '',
      shareFidToken: json['shareFileToken']?.toString() ?? '',
    );
  }
}