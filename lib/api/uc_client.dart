import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// UC网盘 API 异常
class UcException implements Exception {
  final int code;
  final String message;

  UcException(this.code, this.message);

  @override
  String toString() => message;
}

/// UC网盘 API 客户端
///
/// 认证方式：Cookie（与夸克同属阿里系，使用类似的身份认证机制）。
/// Cookie 通过 set-cookie 响应头自动合并更新，并支持持久化恢复。
class UcClient extends BaseDrive {
  static const String _driveApi = 'https://drive.uc.cn/1/clouddrive';
  static const String _pcApi = 'https://pc-api.uc.cn/1/clouddrive';
  static const String _baseUrl = 'https://drive.uc.cn';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const String _uaDesktopClient =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) quark-cloud-drive/2.5.56 Chrome/100.0.4896.160'
      ' Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch';

  final Dio _dio;

  String _cookie = '';
  DriveUserInfo? _userInfo;
  Timer? _refreshTimer;

  UcClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  DriveType get type => DriveType.uc;

  @override
  String get label => 'UC网盘';

  @override
  bool get hasLogin => _cookie.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  /// 设置 Cookie（用于持久化恢复）
  void setCookie(String cookie) {
    _cookie = cookie.trim();
  }

  /// 获取当前 Cookie 快照（用于持久化保存）
  String get cookie => _cookie;

  /// 获取当前 Cookie 快照（下载时使用）
  String get downloadCookieSnapshot => _cookie;

  // ──────────────────── HTTP 请求基础设施 ────────────────────

  Map<String, dynamic> _buildHeaders({String? userAgent}) {
    return {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Referer': '$_baseUrl/',
      'User-Agent': userAgent ?? _ua,
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
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
    final headers = {
      ..._buildHeaders(userAgent: userAgent),
      ...?extraHeaders,
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
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }

  dynamic _check(Map<String, dynamic> body) {
    final code = toInt(body['code'], fallback: -1);
    if (code != 0) {
      throw UcException(code, body['message']?.toString() ?? '请求失败');
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
    final body = _parseBody(resp);
    return _check(body);
  }

  Future<dynamic> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
  }) async {
    final resp = await _request('POST', url,
        params: params, data: data, userAgent: userAgent);
    final body = _parseBody(resp);
    return _check(body);
  }

  /// 默认的 UC 参数集
  Map<String, dynamic> get _defaultParams => {
        'pr': 'UCBrowser',
        'fr': 'pc',
      };

  // ──────────────────── 会话管理 ────────────────────

  /// 刷新 __puus 会话 cookie（服务端在请求缺失 __puus 时重新下发）
  Future<void> refreshSession() async {
    if (_cookie.isEmpty) return;
    final stripped = _removeCookieKey(_cookie, '__puus');
    try {
      await _request('GET', '$_driveApi/config', extraHeaders: {
        if (stripped.isNotEmpty) 'Cookie': stripped,
      });
    } catch (_) {
      // 忽略刷新失败，保持旧 cookie
    }
  }

  String _removeCookieKey(String c, String key) {
    final kept = <String>[];
    for (final part in c.split(';')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      if (t.split('=').first == key) continue;
      kept.add(t);
    }
    return kept.join('; ');
  }

  /// 每 100 分钟刷新一次会话，避免下载 403
  void startSessionRefresher() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 100), (_) {
      refreshSession();
    });
  }

  @override
  Future<void> init() async {
    // 如果已有 Cookie，尝试刷新会话
    if (_cookie.isNotEmpty) {
      try {
        await refreshSession();
      } catch (_) {
        // 静默失败
      }
    }
  }

  @override
  Future<String?> login(dynamic credential) async {
    if (credential == null) return '缺少凭证';
    if (credential is String) {
      _cookie = credential.trim();
      try {
        await refreshUser();
        return null;
      } on UcException catch (e) {
        _cookie = '';
        return e.message;
      }
    }
    if (credential is Map) {
      final c = credential['cookie']?.toString() ?? credential['Cookie']?.toString() ?? '';
      if (c.isNotEmpty) {
        _cookie = c;
        try {
          await refreshUser();
          return null;
        } on UcException catch (e) {
          _cookie = '';
          return e.message;
        }
      }
    }
    return '不支持的登录凭证类型';
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _userInfo = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  @override
  Future<void> refreshUser() async {
    try {
      final resp = await _request('GET', '$_baseUrl/account/info',
          params: {'fr': 'pc', 'platform': 'pc'});
      final body = _parseBody(resp);
      final data = body['data'];
      if (data is Map) {
        _userInfo = DriveUserInfo(
          nickname: data['nickname']?.toString() ?? data['name']?.toString() ?? '',
          avatar: data['avatar']?.toString() ?? data['avatar_url']?.toString() ?? '',
          userId: data['user_id']?.toString() ?? data['uid']?.toString() ?? '',
        );
      }
    } catch (_) {
      // 刷新用户信息失败时保持旧值
    }
  }

  // ──────────────────── 文件列表 ────────────────────

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    final files = <DriveFile>[];
    var total = -1;
    while (total < 0 || files.length < total) {
      final resp = await _request('GET', '$_pcApi/file/sort', params: {
        ..._defaultParams,
        'pdir_fid': pdirFid,
        '_page': page,
        '_size': size,
        '_fetch_total': 1,
        '_fetch_sub_dirs': 0,
        '_sort': 'file_type:asc,updated_at:desc',
        'fetch_all_file': 1,
        'fetch_risk_file_name': 1,
      });
      final body = _parseBody(resp);
      final data = _check(body);
      if (data is! Map) break;
      final list = data['list'];
      if (list is! List) break;
      files.addAll(list
          .whereType<Map>()
          .map((e) => _parseDriveFile(e.cast<String, dynamic>())));
      total = toInt(body['metadata']?['_total'], fallback: total);
      if (total < 0 && list.length < size) break;
      if (list.isEmpty) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? json['type']?.toString() ?? '';
    final isDir = type == 'folder' || json['dir'] == true || json['isdir'] == 1;
    return DriveFile(
      fid: json['fid']?.toString() ?? json['file_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type,
      isDir: isDir,
      size: toInt(json['size'] ?? json['file_size']),
      pdirFid: json['pdir_fid']?.toString() ?? json['parent_file_id']?.toString() ?? '',
      fileExt: json['file_ext']?.toString() ?? json['file_extension']?.toString() ?? '',
      updatedAt: toInt(json['updated_at'] ?? json['modified_at'] ?? json['mtime']),
      thumbnail: json['thumbnail']?.toString() ?? json['thumb']?.toString() ?? '',
      previewUrl: json['preview_url']?.toString() ?? json['url']?.toString() ?? '',
    );
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    final data = await _get('$_pcApi/file/search', params: {
      ..._defaultParams,
      'q': keyword,
      '_page': page,
      '_size': size,
      '_fetch_total': 1,
      '_sort': 'file_type:asc,updated_at:desc',
      '_is_hl': 1,
    });
    final list = data['list'];
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
    final snapshot = downloadCookieSnapshot;
    dynamic data;
    try {
      data = await _post('$_pcApi/file/download',
          params: _defaultParams, data: {'fids': fids});
    } on UcException catch (e) {
      if (e.code == 23018) {
        data = await _post('$_pcApi/file/download',
            params: _defaultParams,
            data: {'fids': fids},
            userAgent: _uaDesktopClient);
      } else {
        rethrow;
      }
    }
    final list = data;
    if (list is! List) return [];
    return list.whereType<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return DriveDownloadInfo(
        url: m['url']?.toString() ?? m['download_url']?.toString() ?? '',
        fileName: m['file_name']?.toString() ?? m['name']?.toString() ?? '',
        size: toInt(m['size'] ?? m['file_size']),
        fid: m['fid']?.toString() ?? m['file_id']?.toString() ?? '',
      );
    }).toList();
  }

  // ──────────────────── 分享 ────────────────────

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      final path = uri.path;
      final idx = path.lastIndexOf('/s/');
      if (idx >= 0) {
        pwdId = path.substring(idx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['pwd_code'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    final data = await _post('$_pcApi/share/password',
        params: _defaultParams,
        data: {'pwd_id': pwdId, 'passcode': passcode});
    final stoken = data['stoken']?.toString() ?? '';
    final shareId = data['share_id']?.toString() ?? pwdId;
    if (stoken.isEmpty) {
      throw UcException(-1, '分享链接已失效或提取码错误');
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
          'GET', '$_pcApi/share/sharepage/v2/detail',
          params: {
            ..._defaultParams,
            'pwd_id': session.pwdId,
            'stoken': session.stoken,
            'pdir_fid': pdirFid,
            'force': 0,
            '_page': page,
            '_size': size,
            '_fetch_banner': 0,
            '_fetch_share': 0,
            '_fetch_total': 1,
            '_sort': 'file_type:asc,updated_at:desc',
            'ver': 2,
          });
      final body = _parseBody(resp);
      final data = _check(body);
      if (data is! Map) break;
      final list = data['list'];
      if (list is! List) break;
      files.addAll(list
          .whereType<Map>()
          .map((e) => _parseShareFile(e.cast<String, dynamic>())));
      total = toInt(body['metadata']?['_total'], fallback: total);
      if (total < 0 && list.length < size) break;
      if (list.isEmpty) break;
      page++;
      if (page > 500) break;
    }
    return files;
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final type = json['file_type']?.toString() ?? json['type']?.toString() ?? '';
    final isDir = type == 'folder' || json['dir'] == true || json['isdir'] == 1;
    return DriveShareFile(
      fid: json['fid']?.toString() ?? json['file_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? json['name']?.toString() ?? '',
      fileType: type,
      isDir: isDir,
      size: toInt(json['size'] ?? json['file_size']),
      pdirFid: json['pdir_fid']?.toString() ?? json['parent_file_id']?.toString() ?? '',
      shareFidToken: json['share_fid_token']?.toString() ?? json['fid_token']?.toString() ?? '',
    );
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    if (fidList.isEmpty) return [];
    final data = await _post('$_pcApi/share/sharepage/download',
        params: _defaultParams,
        data: {
          'fid_list': fidList,
          'pwd_id': session.pwdId,
          'share_id': session.shareId,
          'passcode': session.passcode,
        });
    if (data is! List) return [];
    return data.whereType<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return DriveDownloadInfo(
        url: m['url']?.toString() ?? m['download_url']?.toString() ?? '',
        fileName: m['file_name']?.toString() ?? m['name']?.toString() ?? '',
        size: toInt(m['size'] ?? m['file_size']),
        fid: m['fid']?.toString() ?? m['file_id']?.toString() ?? '',
      );
    }).toList();
  }

  @override
  Future<void> saveShare(
    DriveShareSession session,
    List<DriveShareFile> files,
    String toPdirFid,
  ) async {
    final taskId = await _saveShareRequest(session, files, toPdirFid);
    if (taskId.isNotEmpty) {
      await _waitTask(taskId);
    }
  }

  Future<String> _saveShareRequest(
    DriveShareSession session,
    List<DriveShareFile> files,
    String toPdirFid,
  ) async {
    final data = await _post('$_pcApi/share/sharepage/save',
        params: {
          ..._defaultParams,
          'app': 'clouddrive',
        },
        data: {
          'fid_list': files.map((f) => f.fid).toList(),
          'fid_token_list': files.map((f) => f.shareFidToken).toList(),
          'to_pdir_fid': toPdirFid,
          'pwd_id': session.pwdId,
          'stoken': session.stoken,
          'pdir_fid': '0',
          'scene': 'link',
        });
    if (data is Map && data['task_id'] != null) {
      return data['task_id'].toString();
    }
    return '';
  }

  Future<void> _waitTask(String taskId, {int maxRetry = 120}) async {
    for (var i = 0; i < maxRetry; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      try {
        final data = await _get('$_pcApi/task', params: {
          ..._defaultParams,
          'task_id': taskId,
          'retry_index': i,
        });
        final status = toInt(data['status'], fallback: -1);
        if (status == 2) return;
        if (status == 3) throw UcException(-1, '转存任务失败');
      } on UcException {
        rethrow;
      } catch (_) {
        // 网络抖动继续等待
      }
    }
    throw UcException(-1, '转存任务超时');
  }

  // ──────────────────── 文件管理 ────────────────────

  /// 排序文件（按字段排序）
  Future<dynamic> sortFiles(String pdirFid,
      {String sort = 'file_type:asc,updated_at:desc',
      int page = 1,
      int size = 100}) async {
    return _get('$_pcApi/file/sort', params: {
      ..._defaultParams,
      'pdir_fid': pdirFid,
      '_page': page,
      '_size': size,
      '_sort': sort,
    });
  }

  /// 删除文件
  Future<void> deleteFiles(List<String> fids) async {
    await _post('$_pcApi/file/delete',
        params: _defaultParams, data: {'fids': fids, 'force': true});
  }

  /// 获取文件下载链接（增强版，返回原始响应）
  Future<dynamic> downloadFile(List<String> fids) async {
    return _post('$_pcApi/file/download',
        params: _defaultParams, data: {'fids': fids});
  }

  /// 移动文件
  Future<void> moveFiles(List<String> fids, String toPdirFid) async {
    await _post('$_pcApi/file/move',
        params: _defaultParams,
        data: {'fids': fids, 'to_pdir_fid': toPdirFid, 'on_dup': 'rename'});
  }

  /// 重命名文件
  Future<void> renameFile(String fid, String newName) async {
    await _post('$_pcApi/file/rename',
        params: _defaultParams, data: {'fid': fid, 'new_name': newName});
  }

  /// 获取会员信息
  Future<Map<String, dynamic>> getMemberInfo() async {
    final data = await _get('$_pcApi/member', params: _defaultParams);
    if (data is Map) return data.cast<String, dynamic>();
    return {};
  }

  /// 获取分享列表
  Future<List<Map<String, dynamic>>> listShares(
      {int page = 1, int size = 50}) async {
    final data = await _get('$_pcApi/share', params: {
      ..._defaultParams,
      '_page': page,
      '_size': size,
    });
    final list = data['list'];
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _dio.close(force: true);
  }
}