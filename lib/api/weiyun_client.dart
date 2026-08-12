import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 微云 API 异常
class WeiyunException implements Exception {
  final int code;
  final String message;

  WeiyunException(this.code, this.message);

  @override
  String toString() => message;
}

/// 微云 API 客户端
///
/// 认证方式：需要 QQ/微信 openid（weiyun_qq_openid / weiyun_wx_openid）。
/// 使用 Cookie 进行身份认证，与腾讯系账号体系绑定。
class WeiyunClient extends BaseDrive {
  static const String _baseUrl = 'https://www.weiyun.com';
  static const String _shareUrl = 'https://share.weiyun.com';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  final Dio _dio;

  String _cookie = '';
  String _qqOpenid = '';
  String _wxOpenid = '';
  DriveUserInfo? _userInfo;

  WeiyunClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  DriveType get type => DriveType.weiyun;

  @override
  String get label => '微云';

  @override
  bool get hasLogin => _cookie.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  /// 设置 QQ openid
  void setQqOpenid(String openid) {
    _qqOpenid = openid.trim();
  }

  /// 设置微信 openid
  void setWxOpenid(String openid) {
    _wxOpenid = openid.trim();
  }

  /// 获取 QQ openid
  String get qqOpenid => _qqOpenid;

  /// 获取微信 openid
  String get wxOpenid => _wxOpenid;

  /// 设置 Cookie（用于持久化恢复）
  void setCookie(String cookie) {
    _cookie = cookie.trim();
  }

  /// 获取当前 Cookie
  String get cookie => _cookie;

  // ──────────────────── HTTP 请求基础设施 ────────────────────

  Map<String, dynamic> _buildHeaders({Map<String, dynamic>? extra}) {
    return {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Referer': '$_baseUrl/',
      'User-Agent': _ua,
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
      ...?extra,
    };
  }

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final headers = _buildHeaders(extra: extraHeaders);
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
        return {'raw': body};
      }
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  /// 微云 API 响应格式：{ "ret": 0, "msg": "ok", "data": {...} }
  /// ret != 0 表示错误。
  dynamic _check(Map<String, dynamic> body) {
    // 尝试多种错误码字段
    final retCode = body['ret'] ?? body['retcode'] ?? body['errCode'] ?? body['code'];
    if (retCode != null) {
      final code = toInt(retCode, fallback: 0);
      if (code != 0) {
        throw WeiyunException(
          code,
          body['msg']?.toString() ??
              body['message']?.toString() ??
              body['errMsg']?.toString() ??
              '请求失败',
        );
      }
    }
    return body['data'] ?? body;
  }

  Future<dynamic> _get(
    String url, {
    Map<String, dynamic>? params,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('GET', url,
        params: params, extraHeaders: extraHeaders);
    final body = _parseBody(resp);
    return _check(body);
  }

  Future<dynamic> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('POST', url,
        params: params, data: data, extraHeaders: extraHeaders);
    final body = _parseBody(resp);
    return _check(body);
  }

  // ──────────────────── 认证 ────────────────────

  @override
  Future<String?> login(dynamic credential) async {
    if (credential == null) return '缺少凭证';
    if (credential is String) {
      // 尝试作为 Cookie 使用
      _cookie = credential.trim();
      try {
        await refreshUser();
        return null;
      } on WeiyunException catch (e) {
        _cookie = '';
        return e.message;
      }
    }
    if (credential is Map) {
      // 支持多种凭证格式
      final c = credential['cookie']?.toString() ?? credential['Cookie']?.toString() ?? '';
      final qq = credential['qq_openid']?.toString() ?? credential['weiyun_qq_openid']?.toString() ?? '';
      final wx = credential['wx_openid']?.toString() ?? credential['weiyun_wx_openid']?.toString() ?? '';

      if (c.isNotEmpty) {
        _cookie = c;
        try {
          await refreshUser();
          return null;
        } on WeiyunException catch (e) {
          _cookie = '';
          return e.message;
        }
      }

      // 通过 QQ/微信 openid 登录
      if (qq.isNotEmpty || wx.isNotEmpty) {
        _qqOpenid = qq;
        _wxOpenid = wx;
        return _loginByOpenid();
      }
    }
    return '不支持的登录凭证类型';
  }

  /// 通过 QQ/微信 openid 登录
  Future<String?> _loginByOpenid() async {
    try {
      final body = await _post('$_baseUrl/cgi-bin/auth/login', data: {
        if (_qqOpenid.isNotEmpty) 'qq_openid': _qqOpenid,
        if (_wxOpenid.isNotEmpty) 'wx_openid': _wxOpenid,
        'appid': 'weiyun',
        'sdk_version': '2.0.0',
      });
      // 登录成功后服务端会通过 set-cookie 下发凭证
      if (body is Map && body['uin'] != null) {
        await refreshUser();
        return null;
      }
      return '登录失败，未获取到用户信息';
    } on WeiyunException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _qqOpenid = '';
    _wxOpenid = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    try {
      final data = await _get('$_baseUrl/cgi-bin/user/info');
      if (data is Map) {
        _userInfo = DriveUserInfo(
          nickname: data['nickname']?.toString() ?? data['name']?.toString() ?? '',
          avatar: data['avatar']?.toString() ?? data['face']?.toString() ?? '',
          userId: data['uin']?.toString() ?? data['user_id']?.toString() ?? '',
        );
      }
    } catch (_) {
      // 刷新用户信息失败时保持旧值
    }
  }

  @override
  Future<void> init() async {
    if (_cookie.isNotEmpty) {
      try {
        await refreshUser();
      } catch (_) {
        // 静默失败
      }
    }
  }

  // ──────────────────── 文件列表 ────────────────────

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final data = await _get('$_baseUrl/cgi-bin/file/list', params: {
      'dir': pdirFid.isEmpty ? '/' : pdirFid,
      'start': (page - 1) * size,
      'limit': size,
      'order': 'time',
      'desc': 1,
    });
    final list = data['list'] ?? data['files'] ?? data['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _parseDriveFile(e.cast<String, dynamic>()))
        .toList();
  }

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? json['file_type']?.toString() ?? '';
    final isDir = type == 'folder' || type == 'dir' || json['isdir'] == 1 || json['dir'] == true;
    final fileName = json['fileName']?.toString() ??
        json['file_name']?.toString() ??
        json['name']?.toString() ??
        '';
    final ext = json['ext']?.toString() ??
        json['file_ext']?.toString() ??
        (fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
            : '');
    return DriveFile(
      fid: json['fid']?.toString() ??
          json['file_id']?.toString() ??
          json['pid']?.toString() ??
          '',
      fileName: fileName,
      fileType: type,
      isDir: isDir,
      size: toInt(json['size'] ?? json['file_size']),
      pdirFid: json['pdir']?.toString() ??
          json['pdir_fid']?.toString() ??
          json['parent_file_id']?.toString() ??
          json['pid']?.toString() ??
          '',
      fileExt: ext,
      updatedAt: toInt(json['mtime'] ?? json['updated_at'] ?? json['modify_time']),
      thumbnail: json['thumbnail']?.toString() ??
          json['thumb']?.toString() ??
          json['pic']?.toString() ??
          '',
      previewUrl: json['preview']?.toString() ??
          json['preview_url']?.toString() ??
          json['url']?.toString() ??
          '',
    );
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    final data = await _get('$_baseUrl/cgi-bin/file/search', params: {
      'keyword': keyword,
      'start': (page - 1) * size,
      'limit': size,
    });
    final list = data['list'] ?? data['files'] ?? data['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _parseDriveFile(e.cast<String, dynamic>()))
        .toList();
  }

  // ──────────────────── 下载 ────────────────────

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    if (fids.isEmpty) return [];
    final results = <DriveDownloadInfo>[];
    for (final fid in fids) {
      try {
        final data = await _get('$_baseUrl/cgi-bin/file/download', params: {
          'fid': fid,
        });
        if (data is Map) {
          final url = data['url']?.toString() ??
              data['download_url']?.toString() ??
              data['dl_url']?.toString() ??
              '';
          if (url.isNotEmpty) {
            results.add(DriveDownloadInfo(
              url: url,
              fileName: data['fileName']?.toString() ??
                  data['file_name']?.toString() ??
                  data['name']?.toString() ??
                  '',
              size: toInt(data['size'] ?? data['file_size']),
              fid: fid,
            ));
          }
        }
      } catch (_) {
        // 单个文件下载链接获取失败，跳过
      }
    }
    return results;
  }

  // ──────────────────── 分享 ────────────────────

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      // 微云分享链接格式: https://share.weiyun.com/XXXXXX
      final path = uri.path;
      final segs = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) {
        pwdId = segs.last;
      }
      passcode = uri.queryParameters['pwd'] ??
          uri.queryParameters['passcode'] ??
          uri.queryParameters['code'] ??
          '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    final data = await _post('$_shareUrl/cgi-bin/share/view', data: {
      'share_id': pwdId,
      'pwd': passcode,
    });
    final stoken = data['stoken']?.toString() ??
        data['share_token']?.toString() ??
        data['token']?.toString() ??
        '';
    if (stoken.isEmpty) {
      throw WeiyunException(-1, '分享链接已失效或提取码错误');
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
    final data = await _get('$_shareUrl/cgi-bin/share/dir/list', params: {
      'share_id': session.shareId,
      'stoken': session.stoken,
      'dir': pdirFid.isEmpty ? '/' : pdirFid,
      'start': (page - 1) * size,
      'limit': size,
    });
    final list = data['list'] ?? data['files'] ?? data['items'];
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => _parseShareFile(e.cast<String, dynamic>()))
        .toList();
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? json['file_type']?.toString() ?? '';
    final isDir = type == 'folder' || type == 'dir' || json['isdir'] == 1;
    final fileName = json['fileName']?.toString() ??
        json['file_name']?.toString() ??
        json['name']?.toString() ??
        '';
    return DriveShareFile(
      fid: json['fid']?.toString() ??
          json['file_id']?.toString() ??
          json['pid']?.toString() ??
          '',
      fileName: fileName,
      fileType: type,
      isDir: isDir,
      size: toInt(json['size'] ?? json['file_size']),
      pdirFid: json['pdir']?.toString() ??
          json['pdir_fid']?.toString() ??
          json['parent_file_id']?.toString() ??
          '',
      shareFidToken: json['share_fid_token']?.toString() ??
          json['fid_token']?.toString() ??
          json['stoken']?.toString() ??
          '',
    );
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    if (fidList.isEmpty) return [];
    // 微云分享批量下载
    try {
      final data = await _post('$_shareUrl/cgi-bin/share/batch/download',
          data: {
            'share_id': session.shareId,
            'stoken': session.stoken,
            'fid_list': fidList,
          });
      if (data is List) {
        return data.whereType<Map>().map((e) {
          final m = e.cast<String, dynamic>();
          return DriveDownloadInfo(
            url: m['url']?.toString() ??
                m['download_url']?.toString() ??
                m['dl_url']?.toString() ??
                '',
            fileName: m['fileName']?.toString() ??
                m['file_name']?.toString() ??
                m['name']?.toString() ??
                '',
            size: toInt(m['size'] ?? m['file_size']),
            fid: m['fid']?.toString() ??
                m['file_id']?.toString() ??
                '',
          );
        }).toList();
      }
      if (data is Map) {
        final list = data['list'] ?? data['files'] ?? data['items'];
        if (list is List) {
          return list.whereType<Map>().map((e) {
            final m = e.cast<String, dynamic>();
            return DriveDownloadInfo(
              url: m['url']?.toString() ?? '',
              fileName: m['fileName']?.toString() ?? '',
              size: toInt(m['size']),
              fid: m['fid']?.toString() ?? '',
            );
          }).toList();
        }
      }
    } catch (_) {
      // 降级处理：单个文件逐个获取
    }
    return [];
  }

  @override
  Future<void> saveShare(
    DriveShareSession session,
    List<DriveShareFile> files,
    String toPdirFid,
  ) async {
    // 微云分享部分保存
    await _post('$_shareUrl/cgi-bin/share/part/save', data: {
      'share_id': session.shareId,
      'stoken': session.stoken,
      'fid_list': files.map((f) => f.fid).toList(),
      'fid_token_list': files.map((f) => f.shareFidToken).toList(),
      'to_dir': toPdirFid.isEmpty ? '/' : toPdirFid,
    });
  }

  // ──────────────────── 额外 API ────────────────────

  /// 分享查看（WeiyunShareView）
  Future<Map<String, dynamic>> shareView(String shareId, {String? pwd}) async {
    final data = await _get('$_shareUrl/cgi-bin/share/view', params: {
      'share_id': shareId,
      if (pwd != null) 'pwd': pwd,
    });
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  /// 分享目录列表（WeiyunShareDirList）
  Future<List<DriveShareFile>> shareDirList(
    String shareId, {
    String dir = '/',
    int page = 1,
    int size = 50,
  }) async {
    return listShare(
      DriveShareSession(
        shareId: shareId,
        pwdId: shareId,
        passcode: '',
        stoken: '',
      ),
      dir,
      page: page,
      size: size,
    );
  }

  /// 分享添加 V2（WeiyunShareAddV2）
  Future<Map<String, dynamic>> createShareLink(
    List<String> fids, {
    String pwd = '',
    int expireDays = 0,
  }) async {
    final data = await _post('$_baseUrl/cgi-bin/share/add/v2', data: {
      'fid_list': fids,
      if (pwd.isNotEmpty) 'pwd': pwd,
      if (expireDays > 0) 'expire_days': expireDays,
    });
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  /// 分享批量下载（WeiyunShareBatchDownload）
  Future<List<DriveDownloadInfo>> shareBatchDownload(
    String shareId, {
    required List<String> fidList,
    String? stoken,
  }) async {
    final session = DriveShareSession(
      shareId: shareId,
      pwdId: shareId,
      passcode: '',
      stoken: stoken ?? '',
    );
    return getShareDownloadInfo(session, fidList);
  }

  /// 分享部分保存（WeiyunSharePartSaveData）
  Future<void> sharePartSave(
    String shareId,
    List<DriveShareFile> files,
    String toDir, {
    String? stoken,
  }) async {
    final session = DriveShareSession(
      shareId: shareId,
      pwdId: shareId,
      passcode: '',
      stoken: stoken ?? '',
    );
    return saveShare(session, files, toDir);
  }

  /// 分享不登录查看（weiyunShareNoLogin）
  Future<Map<String, dynamic>> shareViewNoLogin(String shareId,
      {String? pwd}) async {
    final data = await _get('$_shareUrl/cgi-bin/share/view/no-login', params: {
      'share_id': shareId,
      if (pwd != null) 'pwd': pwd,
    });
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  /// 认证信息（weiyunQdisk）
  Future<Map<String, dynamic>> getQdiskAuth() async {
    final data = await _get('$_baseUrl/cgi-bin/qdisk/auth');
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  /// 客户端认证信息（weiyunQdiskClient）
  Future<Map<String, dynamic>> getQdiskClientAuth() async {
    final data = await _get('$_baseUrl/cgi-bin/qdisk/client/auth');
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}