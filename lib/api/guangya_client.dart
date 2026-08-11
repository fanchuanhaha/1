import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 光丫网盘自定义异常
class GuangyaException implements Exception {
  final int code;
  final String message;

  GuangyaException(this.code, this.message);

  @override
  String toString() => message;
}

/// 光丫网盘（guangyapan）客户端
///
/// API 端点基于 APK 反编译提取。支持账号密码登录、验证码二次验证、
/// 文件管理、分享解析与转存。
///
/// 认证端点: account.guangyapan.com
/// 资源端点: api.guangyapan.com
///
/// 同时存在两套 API 版本:
/// - /nd.bizuserres.s/v1/ — 主版本
/// - /userres/v1/ — 备选版本
class GuangyaClient implements BaseDrive {
  // ---------------- 常量 ----------------

  static const String accountUrl = 'https://account.guangyapan.com';
  static const String apiUrl = 'https://api.guangyapan.com';

  // 隐藏功能标记
  static const bool guangyaHiddenFeatureEnabled = false;

  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const String uaMobile =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  // ---------------- 内部状态 ----------------

  final Dio _dio;
  String _accessToken = '';
  String _refreshToken = '';
  String _sessionId = '';
  DriveUserInfo? _userInfo;

  GuangyaClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---------------- BaseDrive 接口 ----------------

  @override
  DriveType get type => DriveType.guangya;

  @override
  String get label => '光丫';

  @override
  bool get hasLogin => _accessToken.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  Future<void> init() async {
    // 从持久化缓存加载凭证（由上层调用方实现存储）
  }

  /// 使用密码登录光丫网盘。
  ///
  /// [credential] 为 Map，需包含:
  /// - 'account': 手机号/邮箱
  /// - 'password': 密码
  /// - 可选 'captchaId': 验证码 ID
  /// - 可选 'captchaCode': 验证码
  /// - 可选 'verificationToken': 二次验证 token
  ///
  /// 返回 accessToken 字符串，登录失败时返回 null。
  @override
  Future<String?> login(dynamic credential) async {
    if (credential is! Map) return null;
    final account = credential['account']?.toString() ?? '';
    final password = credential['password']?.toString() ?? '';
    if (account.isEmpty || password.isEmpty) return null;

    try {
      // 1. 检查是否需要验证码
      String? captchaId;
      String? captchaCode;
      if (credential['captchaId'] != null) {
        captchaId = credential['captchaId'].toString();
        captchaCode = credential['captchaCode']?.toString() ?? '';
      } else {
        final captchaInit = await _initCaptcha();
        if (captchaInit['captchaId']?.toString().isNotEmpty == true) {
          captchaId = captchaInit['captchaId'].toString();
          // 返回 captchaId 让上层展示验证码图片
          // 用户输入验证码后通过 credential 传入
          return 'captcha_required:$captchaId';
        }
      }

      // 2. 提交登录
      final loginResp = await _request(
        'POST',
        '$accountUrl/v1/auth/signin',
        data: {
          'account': account,
          'password': password,
          if (captchaId != null) 'captchaId': captchaId,
          if (captchaCode != null) 'captchaCode': captchaCode,
        },
      );
      final loginBody = _parseBody(loginResp);

      // 检查是否需要二次验证
      if (loginBody['verificationRequired'] == true ||
          loginBody['needVerification'] == true) {
        final verificationToken =
            loginBody['verificationToken']?.toString() ?? '';
        if (credential['verificationToken'] != null) {
          return await _submitVerification(
              credential['verificationToken'].toString(),
              credential['verificationCode']?.toString() ?? '');
        }
        // 发起二次验证
        await _sendVerification(verificationToken);
        return 'verification_required:$verificationToken';
      }

      // 3. 登录成功，获取 token
      _accessToken = loginBody['accessToken']?.toString() ?? '';
      _refreshToken = loginBody['refreshToken']?.toString() ?? '';
      _sessionId = loginBody['sessionId']?.toString() ?? '';

      if (_accessToken.isEmpty) {
        throw GuangyaException(-1, '登录失败: 未获取到 accessToken');
      }

      // 4. 获取用户信息
      await refreshUser();

      return _accessToken;
    } on GuangyaException {
      rethrow;
    } catch (e) {
      throw GuangyaException(-1, '登录失败: $e');
    }
  }

  /// 使用 refreshToken 刷新 accessToken
  Future<String?> refreshToken() async {
    if (_refreshToken.isEmpty) return null;
    try {
      final resp = await _request(
        'POST',
        '$accountUrl/v1/auth/token',
        data: {
          'refreshToken': _refreshToken,
          'grantType': 'refresh_token',
        },
      );
      final body = _parseBody(resp);
      _accessToken = body['accessToken']?.toString() ?? '';
      _refreshToken = body['refreshToken']?.toString() ?? _refreshToken;
      return _accessToken.isNotEmpty ? _accessToken : null;
    } catch (_) {
      return null;
    }
  }

  /// 发起二次验证（发送验证码到绑定手机/邮箱）
  Future<void> _sendVerification(String verificationToken) async {
    await _request(
      'POST',
      '$accountUrl/v1/auth/verification',
      data: {'verificationToken': verificationToken},
    );
  }

  /// 提交二次验证码
  Future<String> _submitVerification(
      String verificationToken, String code) async {
    final resp = await _request(
      'POST',
      '$accountUrl/v1/auth/verification/verify',
      data: {
        'verificationToken': verificationToken,
        'code': code,
      },
    );
    final body = _parseBody(resp);
    _accessToken = body['accessToken']?.toString() ?? '';
    _refreshToken = body['refreshToken']?.toString() ?? '';
    _sessionId = body['sessionId']?.toString() ?? '';
    if (_accessToken.isEmpty) {
      throw GuangyaException(-1, '二次验证失败');
    }
    await refreshUser();
    return _accessToken;
  }

  /// 初始化验证码
  Future<Map<String, dynamic>> _initCaptcha() async {
    final resp = await _request(
      'GET',
      '$accountUrl/v1/shield/captcha/init',
    );
    return _parseBody(resp);
  }

  @override
  Future<void> logout() async {
    _accessToken = '';
    _refreshToken = '';
    _sessionId = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (!hasLogin) return;
    try {
      final resp = await _request(
        'GET',
        '$accountUrl/v1/user/me',
      );
      final body = _parseBody(resp);
      final data = body['data'] as Map<String, dynamic>? ?? body;
      _userInfo = DriveUserInfo(
        nickname: data['nickname']?.toString() ??
            data['nickName']?.toString() ??
            data['name']?.toString() ??
            '',
        avatar: data['avatar']?.toString() ??
            data['headPic']?.toString() ??
            '',
        userId: data['userId']?.toString() ??
            data['id']?.toString() ??
            data['account']?.toString() ??
            '',
      );
    } catch (_) {
      // 静默失败
    }
  }

  /// 获取用户资产信息
  Future<Map<String, dynamic>> getUserAssets() async {
    if (!hasLogin) return {};
    try {
      final resp = await _request(
        'GET',
        '$apiUrl/assets/v1/get_assets',
      );
      final body = _parseBody(resp);
      return body['data'] as Map<String, dynamic>? ?? body;
    } catch (_) {
      return {};
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
        '$apiUrl/nd.bizuserres.s/v1/file/get_file_list',
        params: {
          'parentFileId': pdirFid,
          'pageNum': page,
          'pageSize': size,
        },
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
      '$apiUrl/nd.bizuserres.s/v1/file/get_file_list',
      params: {
        'keyword': keyword,
        'pageNum': page,
        'pageSize': size,
      },
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
        final tokenResp = await _request(
          'GET',
          '$apiUrl/nd.bizuserres.s/v1/get_res_center_token',
          params: {'fileId': fid},
        );
        final tokenBody = _parseBody(tokenResp);
        final tokenData =
            tokenBody['data'] as Map<String, dynamic>? ?? tokenBody;
        final resToken = tokenData['resToken']?.toString() ?? '';

        final urlResp = await _request(
          'GET',
          '$apiUrl/nd.bizuserres.s/v1/get_res_download_url',
          params: {
            'fileId': fid,
            if (resToken.isNotEmpty) 'resToken': resToken,
          },
        );
        final urlBody = _parseBody(urlResp);
        final urlData = urlBody['data'] as Map<String, dynamic>? ?? urlBody;
        results.add(DriveDownloadInfo(
          url: urlData['downloadUrl']?.toString() ??
              urlData['url']?.toString() ??
              '',
          fileName: urlData['fileName']?.toString() ??
              urlData['name']?.toString() ??
              '',
          size: urlData['fileSize']?.toInt() ?? 0,
          fid: fid,
        ));
      } catch (_) {
        // 单个文件失败跳过
      }
    }
    return results;
  }

  /// 创建目录
  Future<DriveFile> createDir(String parentFid, String dirName) async {
    final resp = await _request(
      'POST',
      '$apiUrl/nd.bizuserres.s/v1/file/create_dir',
      data: {
        'parentFileId': parentFid,
        'dirName': dirName,
      },
    );
    final body = _parseBody(resp);
    final data = body['data'] as Map<String, dynamic>? ?? body;
    return _parseDriveFile(data);
  }

  /// 删除文件
  Future<bool> deleteFile(List<String> fids) async {
    final resp = await _request(
      'POST',
      '$apiUrl/nd.bizuserres.s/v1/file/delete_file',
      data: {'fileIds': fids},
    );
    final body = _parseBody(resp);
    return body['code']?.toInt() == 0 || body['resultCode']?.toInt() == 0;
  }

  /// 删除上传任务
  Future<bool> deleteUploadTask(String taskId) async {
    final resp = await _request(
      'POST',
      '$apiUrl/nd.bizuserres.s/v1/file/delete_upload_task',
      data: {'taskId': taskId},
    );
    final body = _parseBody(resp);
    return body['code']?.toInt() == 0 || body['resultCode']?.toInt() == 0;
  }

  /// 移动文件
  Future<bool> moveFile(List<String> fids, String toParentFid) async {
    final resp = await _request(
      'POST',
      '$apiUrl/nd.bizuserres.s/v1/file/move_file',
      data: {
        'fileIds': fids,
        'targetParentFileId': toParentFid,
      },
    );
    final body = _parseBody(resp);
    return body['code']?.toInt() == 0 || body['resultCode']?.toInt() == 0;
  }

  /// 重命名文件
  Future<bool> rename(String fid, String newName) async {
    final resp = await _request(
      'POST',
      '$apiUrl/nd.bizuserres.s/v1/file/rename',
      data: {
        'fileId': fid,
        'newName': newName,
      },
    );
    final body = _parseBody(resp);
    return body['code']?.toInt() == 0 || body['resultCode']?.toInt() == 0;
  }

  // ---------------- 分享相关 ----------------

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      // 光丫网盘分享链接格式:
      // https://guangyapan.com/s/xxxxxxxx
      // https://www.guangyapan.com/share/xxxxxxxx
      final path = uri.path;
      final sIdx = path.lastIndexOf('/s/');
      if (sIdx >= 0) {
        pwdId = path.substring(sIdx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      if (pwdId.isEmpty) {
        final shareIdx = path.lastIndexOf('/share/');
        if (shareIdx >= 0) {
          pwdId = path.substring(shareIdx + 7);
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
    // 获取分享访问 token
    final resp = await _request(
      'GET',
      '$apiUrl/nd.bizuserres.s/v1/get_share_access_token',
      params: {
        'shareCode': pwdId,
        if (passcode.isNotEmpty) 'accessCode': passcode,
      },
    );
    final body = _parseBody(resp);
    final data = body['data'] as Map<String, dynamic>? ?? body;
    final shareId = data['shareId']?.toString() ?? '';
    final stoken = data['accessToken']?.toString() ??
        data['stoken']?.toString() ??
        '';

    if (shareId.isEmpty) {
      throw GuangyaException(-1, '分享链接无效或已过期');
    }

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
        'GET',
        '$apiUrl/nd.bizuserres.s/v1/get_share_page_files_list',
        params: {
          'shareCode': session.pwdId,
          'accessToken': session.stoken,
          if (session.passcode.isNotEmpty) 'accessCode': session.passcode,
          'parentFileId': pdirFid,
          'pageNum': page,
          'pageSize': size,
        },
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
          '$apiUrl/nd.bizuserres.s/v1/get_share_download_url',
          params: {
            'shareCode': session.pwdId,
            'accessToken': session.stoken,
            if (session.passcode.isNotEmpty) 'accessCode': session.passcode,
            'fileId': fid,
          },
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
      '$apiUrl/nd.bizuserres.s/v1/restore_share',
      data: {
        'shareCode': session.pwdId,
        'accessToken': session.stoken,
        if (session.passcode.isNotEmpty) 'accessCode': session.passcode,
        'fileIds': fidList,
        'targetParentFileId': toPdirFid,
      },
    );
    final body = _parseBody(resp);
    final code = body['code']?.toInt() ?? body['resultCode']?.toInt() ?? -1;
    if (code != 0) {
      throw GuangyaException(code, '转存失败: ${body['message'] ?? body['msg']}');
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
      if (referer != null) 'Referer': referer,
      if (contentType != null) 'Content-Type': contentType,
      if (_accessToken.isNotEmpty) 'Authorization': 'Bearer $_accessToken',
    };
    if (contentType == null && data != null) {
      headers['Content-Type'] = 'application/json';
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
    return resp;
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
      pdirFid: json['parentFileId']?.toString() ??
          json['parentFolderId']?.toString() ??
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
      pdirFid: json['parentFileId']?.toString() ??
          json['parentFolderId']?.toString() ??
          '',
      shareFidToken: json['shareFileToken']?.toString() ??
          json['shareFidToken']?.toString() ??
          '',
    );
  }
}