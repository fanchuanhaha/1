import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 百度网盘 API 异常
class BaiduException implements Exception {
  final int code;
  final String message;

  BaiduException(this.code, this.message);

  @override
  String toString() => message;
}

/// 百度网盘 API 客户端
///
/// 认证方式：BDUSS + STOKEN Cookie。
/// 大部分 API 需要 bdstoken 参数，通过 gettemplatevariable 接口获取。
class BaiduClient extends BaseDrive {
  static const String _baseUrl = 'https://pan.baidu.com';
  static const String _yunBaseUrl = 'https://yun.baidu.com';
  static const String _pcsBaseUrl = 'http://d.pcs.baidu.com';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
// ---- 内部状态 ----
  final Dio _dio;
  String _bduss = '';
  String _stoken = '';
  String _bdstoken = '';
  /// 网页登录时捕获的完整 cookie 字符串（含 BAIDUID 等辅助 cookie），
  /// 发送请求时优先使用完整 cookie 而非仅 BDUSS+STOKEN。
  String _rawCookie = '';
  DriveUserInfo? _userInfo;

  BaiduClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  DriveType get type => DriveType.baidu;

  @override
  String get label => '百度网盘';

  @override
  bool get hasLogin => _bduss.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie =>
      _bduss.isEmpty ? null : (_rawCookie.isNotEmpty ? _rawCookie : 'BDUSS=$_bduss; STOKEN=$_stoken');

  /// 设置 BDUSS（持久化恢复用）
  void setBduss(String bduss) {
    _bduss = bduss.trim();
  }

  /// 设置 STOKEN（持久化恢复用）
  void setStoken(String stoken) {
    _stoken = stoken.trim();
  }

  @override
  void restoreSession(String credential) {
    // 持久化格式: BDUSS=xxx;_stoken=yyy 或 BDUSS=xxx; STOKEN=yyy
    _rawCookie = credential;
    final bduss = RegExp(r'BDUSS=([^;]+)').firstMatch(credential)?.group(1) ?? '';
    final stoken =
        RegExp(r'_?STOKEN=([^;]+)', caseSensitive: false)
            .firstMatch(credential)
            ?.group(1) ??
        '';
    if (bduss.isNotEmpty) setBduss(bduss);
    if (stoken.isNotEmpty) setStoken(stoken);
    if (_bduss.isNotEmpty) _userInfo = DriveUserInfo(
      nickname: '',
      avatar: '',
      userId: _bduss,
    );
  }

  /// 获取 BDUSS
  String get bduss => _bduss;

  /// 获取 STOKEN
  String get stoken => _stoken;

  /// 获取 bdstoken
  String get bdstoken => _bdstoken;

  // ──────────────────── HTTP 请求基础设施 ────────────────────

  String get _cookie => 'BDUSS=$_bduss; STOKEN=$_stoken';

  Map<String, dynamic> _buildHeaders() {
    final cookie = _rawCookie.isNotEmpty ? _rawCookie : _cookie;
    return {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': _ua,
      'Referer': 'https://pan.baidu.com/',
      if (_bduss.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    bool isJson = false,
  }) async {
    final headers = Map<String, dynamic>.from(_buildHeaders());
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }

    Response<dynamic> resp;
    try {
      resp = await _dio.request(
        url,
        data: data,
        queryParameters: params,
        options: Options(
          method: method,
          headers: headers,
          validateStatus: (_) => true,
        ),
      );
    } catch (e) {
      AppLogger.I.e('baidu', 'HTTP请求失败: $method $url, 错误: $e');
      rethrow;
    }
    _mergeSetCookie(resp);
    AppLogger.I.http(
      'baidu',
      method,
      url,
      status: resp.statusCode ?? -1,
      cred: _cookie,
      body: resp.data,
    );
    return _parseBody(resp);
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

  void _mergeSetCookie(Response<dynamic> resp) {
    final setCookies = resp.headers['set-cookie'];
    if (setCookies == null || setCookies.isEmpty) return;
    for (final raw in setCookies) {
      final seg = raw.split(';').first.trim();
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      final key = seg.substring(0, eq).trim();
      final value = seg.substring(eq + 1).trim();
      if (key == 'BDUSS') _bduss = value;
      if (key == 'STOKEN') _stoken = value;
    }
  }

  void _check(Map<String, dynamic> body) {
    final errno = body['errno'];
    if (errno != null) {
      final code = toInt(errno, fallback: 0);
      if (code != 0) {
        // errno 为 0 表示成功，非 0 表示错误
        throw BaiduException(
            code, body['errmsg']?.toString() ?? body['show_msg']?.toString() ?? '请求失败');
      }
    }
    // 检查 error_code（某些百度 API 使用此字段）
    final errorCode = body['error_code'];
    if (errorCode != null) {
      final code = toInt(errorCode, fallback: 0);
      if (code != 0) {
        throw BaiduException(
            code, body['error_msg']?.toString() ?? '请求失败');
      }
    }
  }

  /// 检查 errno 并返回 data
  Map<String, dynamic> _checkAndReturn(Map<String, dynamic> body) {
    _check(body);
    return body;
  }

  Future<Map<String, dynamic>> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    bool isJson = false,
  }) async {
    final body = await _request('POST', url, params: params, data: data, isJson: isJson);
    return _checkAndReturn(body);
  }

  Future<Map<String, dynamic>> _get(
    String url, {
    Map<String, dynamic>? params,
  }) async {
    final body = await _request('GET', url, params: params);
    return _checkAndReturn(body);
  }

  // ──────────────────── 认证 / Token ────────────────────

  /// 从服务端获取 bdstoken
  Future<void> _refreshBdstoken() async {
    AppLogger.I.i('baidu', '刷新 bdstoken: BDUSS长度=${_bduss.length} STOKEN长度=${_stoken.length}');
    try {
      final body = await _get('$_baseUrl/api/gettemplatevariable', params: {
        'clienttype': 0,
        'app_id': 250528,
        'web': 1,
        'fields': jsonEncode(['bdstoken']),
      });
      final result = body['result'];
      if (result is Map) {
        final bdstokenVal = result['bdstoken'];
        // API 返回格式: {"result":{"bdstoken":"xxx"}} 或 {"result":{"bdstoken":{"bdstoken":"xxx"}}}
        if (bdstokenVal is String) {
          _bdstoken = bdstokenVal;
          AppLogger.I.i('baidu', 'bdstoken 获取成功(字符串), 长度=${_bdstoken.length}');
        } else if (bdstokenVal is Map) {
          _bdstoken = bdstokenVal['bdstoken']?.toString() ?? '';
          AppLogger.I.i('baidu', 'bdstoken 获取成功(对象), 长度=${_bdstoken.length}');
        } else {
          AppLogger.I.w('baidu', 'bdstoken 字段格式异常: $bdstokenVal');
        }
      } else {
        AppLogger.I.w('baidu', 'gettemplatevariable 返回无 result 字段, 完整响应: $body');
      }
    } catch (e) {
      AppLogger.I.e('baidu', '刷新 bdstoken 失败: $e, BDUSS长度=${_bduss.length} STOKEN长度=${_stoken.length}');
    }
  }

  /// 通过 BDUSS + STOKEN 登录
  Future<String?> loginByCredentials(String bduss, String stoken) async {
    AppLogger.I.i('baidu', 'loginByCredentials: BDUSS长度=${bduss.length} STOKEN长度=${stoken.length}');
    _bduss = bduss.trim();
    _stoken = stoken.trim();
    try {
      await _refreshBdstoken();
      if (_bdstoken.isEmpty) {
        AppLogger.I.e('baidu', 'bdstoken 获取失败, BDUSS已设=${_bduss.isNotEmpty} STOKEN已设=${_stoken.isNotEmpty}');
        throw BaiduException(-1, '无法获取 bdstoken');
      }
      await refreshUser();
      AppLogger.I.i('baidu', '登录成功, 用户名=${_userInfo?.nickname ?? "未知"}');
      return null;
    } on BaiduException catch (e) {
      AppLogger.I.e('baidu', '百度登录失败: ${e.message} (code=${e.code})');
      _bduss = '';
      _stoken = '';
      _bdstoken = '';
      return e.message;
    } catch (e) {
      AppLogger.I.e('baidu', '百度登录异常: $e');
      _bduss = '';
      _stoken = '';
      _bdstoken = '';
      return e.toString();
    }
  }

  @override
  Future<String?> login(dynamic credential) async {
    if (credential == null) return '缺少凭证';
    AppLogger.I.i('baidu', 'login 开始, credential类型=${credential.runtimeType}');
    if (credential is String) {
      AppLogger.I.i('baidu', 'login 原始凭证前100字: ${credential.length > 100 ? "${credential.substring(0, 100)}..." : credential}');
      // 保存完整 cookie 字符串（含 BAIDUID 等辅助 cookie），发送请求时优先使用
      _rawCookie = credential;
      // 可能是完整 cookie（BDUSS=xxx; STOKEN=yyy），也可能是纯 BDUSS。
      // 从 cookie 中解析出 BDUSS / STOKEN，避免整体当 BDUSS 用导致鉴权失败。
      // 注意：需精确区分 BDUSS 与 BDUSS_BFESS 等变体，故按分号拆分后精确比对 key。
      String cookieValue(String keyName) {
        for (final seg in credential.split(';')) {
          final t = seg.trim();
          final eq = t.indexOf('=');
          if (eq <= 0) continue;
          final k = t.substring(0, eq).trim();
          if (k.toLowerCase() == keyName.toLowerCase()) {
            final v = t.substring(eq + 1).trim();
            if (v.isNotEmpty) return v;
          }
        }
        return '';
      }
      final bduss = cookieValue('BDUSS');
      final stoken = cookieValue('STOKEN');
      AppLogger.I.i('baidu', 'login 解析: BDUSS找到=${bduss.isNotEmpty} len=${bduss.length} STOKEN找到=${stoken.isNotEmpty} len=${stoken.length}');
      if (bduss.isNotEmpty) {
        return loginByCredentials(bduss, stoken);
      }
      // 没有可识别的 BDUSS= 前缀，视为纯 BDUSS
      AppLogger.I.w('baidu', 'login 未找到BDUSS=前缀, 将整个凭证作为BDUSS尝试');
      return loginByCredentials(credential, '');
    }
    if (credential is Map) {
      final bduss = credential['bduss']?.toString() ?? credential['BDUSS']?.toString() ?? '';
      final stoken = credential['stoken']?.toString() ?? credential['STOKEN']?.toString() ?? '';
      AppLogger.I.i('baidu', 'login Map: BDUSS找到=${bduss.isNotEmpty} STOKEN找到=${stoken.isNotEmpty}');
      if (bduss.isNotEmpty) {
        return loginByCredentials(bduss, stoken);
      }
    }
    return '不支持的登录凭证类型';
  }

  @override
  Future<void> logout() async {
    _bduss = '';
    _stoken = '';
    _bdstoken = '';
    _rawCookie = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    try {
      final body = await _get('$_yunBaseUrl/api/quota', params: {
        'bdstoken': _bdstoken,
        'clienttype': 0,
        'app_id': 250528,
        'web': 1,
      });
      // 百度网盘 quota 接口返回容量信息，不含用户名
      final name = body['username']?.toString() ?? body['name']?.toString() ?? '';
      final avatar = body['avatar']?.toString() ?? '';
      final uid = body['uk']?.toString() ?? body['user_id']?.toString() ?? _bduss;
      final total = toInt(body['total'], fallback: 0);
      final used = toInt(body['used'], fallback: 0);
      _userInfo = DriveUserInfo(
        nickname: name,
        avatar: avatar,
        userId: uid,
        totalSpace: total,
        usedSpace: used,
      );
    } catch (_) {
      // 刷新用户信息失败时保持旧值
    }
  }

  @override
  Future<void> init() async {
    if (_bduss.isNotEmpty && _bdstoken.isEmpty) {
      try {
        await _refreshBdstoken();
      } catch (_) {
        // 静默失败
      }
    }
  }

  // ──────────────────── 文件列表 ────────────────────

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    // 实测 pan.baidu.com/api/list 返回 errno=0，yun.baidu.com 返回 errno=-7
    // 通用前端以 '0' 表示根目录，必须映射为 '/'
    final body = await _get('$_baseUrl/api/list', params: {
      'dir': (pdirFid.isEmpty || pdirFid == '0') ? '/' : pdirFid,
      'page': page,
      'num': size,
      'order': 'name',
      'desc': 0,
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
      'showempty': 0,
    });

    final list = body['list'];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseDriveFile(e))
        .toList();
  }

  DriveFile _parseDriveFile(Map<String, dynamic> json) {
    final isDir = json['isdir'] == 1 || json['isdir'] == true;
    final serverFilename = json['server_filename']?.toString() ?? '';
    final filename = json['filename']?.toString() ?? json['server_filename']?.toString() ?? '';
    final path = json['path']?.toString() ?? '';
    final ext = filename.contains('.')
        ? filename.substring(filename.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return DriveFile(
      fid: json['fs_id']?.toString() ?? json['uk']?.toString() ?? '',
      fileName: filename.isNotEmpty ? filename : serverFilename,
      fileType: isDir ? 'folder' : ext,
      isDir: isDir,
      size: toInt(json['size']),
      pdirFid: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '/',
      fileExt: ext,
      updatedAt: toInt(json['mtime'] ?? json['server_mtime']),
      thumbnail: json['thumbs']?['url']?.toString() ?? json['thumb']?.toString() ?? '',
      previewUrl: '',
    );
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    // 与文件列表同域名，pan.baidu.com/api/list 支持 key 参数搜索
    final body = await _get('$_baseUrl/api/list', params: {
      'key': keyword,
      'page': page,
      'num': size,
      'recursion': 1,
      'bdstoken': _bdstoken,
      'app_id': 250528,
      'clienttype': 0,
      'web': 1,
      'showempty': 0,
    });

    final list = body['list'];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseDriveFile(e))
        .toList();
  }

  // ──────────────────── 下载 ────────────────────

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    if (fids.isEmpty) return [];
    final results = <DriveDownloadInfo>[];

    // 先获取文件元数据，得到文件名和路径
    String fileMetasJson = jsonEncode(fids.map((f) => toInt(f, fallback: 0)).toList());
    Map<String, dynamic> metaBody;
    try {
      metaBody = await _get('$_baseUrl/api/filemetas', params: {
        'bdstoken': _bdstoken,
        'target': fileMetasJson,
        'dlink': 1,
        'clienttype': 0,
        'app_id': 250528,
        'web': 1,
      });
    } catch (_) {
      metaBody = {};
    }

    // 如果有 dlink 直接使用
    final infoList = metaBody['info'];
    if (infoList is List) {
      for (final item in infoList) {
        if (item is Map) {
          final dlink = item['dlink']?.toString() ?? '';
          final filename = item['filename']?.toString() ?? item['server_filename']?.toString() ?? '';
          final fsId = item['fs_id']?.toString() ?? '';
          if (dlink.isNotEmpty) {
            // dlink 需要拼接 bdstoken 和用户代理
            final downloadUrl = '$dlink&bdstoken=$_bdstoken&type=1';
            results.add(DriveDownloadInfo(
              url: downloadUrl,
              fileName: filename,
              size: toInt(item['size']),
              fid: fsId,
            ));
          }
        }
      }
    }

    // 如果 dlink 方式未获取到，尝试 PCS 下载
    if (results.isEmpty) {
      for (final fid in fids) {
        try {
          final body = await _get('$_pcsBaseUrl/rest/2.0/pcs/file', params: {
            'method': 'download',
            'app_id': 250528,
            'bdstoken': _bdstoken,
            'fs_id': fid,
          });
          // PCS 下载接口返回重定向 URL
          final url = body['url']?.toString() ?? body['dlink']?.toString() ?? '';
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
      // 百度分享链接格式: https://pan.baidu.com/s/1sXXX 或 /share/init?surl=XXX
      final path = uri.path;
      final idx = path.lastIndexOf('/s/');
      if (idx >= 0) {
        pwdId = path.substring(idx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      } else {
        // 也可能 surl 作为 query 参数
        pwdId = uri.queryParameters['surl'] ?? '';
      }
      passcode = uri.queryParameters['pwd'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    final body = await _post('$_baseUrl/share/verify', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    }, data: {
      'shareid': pwdId,
      'pwd': passcode,
      'vcode': '',
      'vcode_str': '',
    });

    // 验证成功返回 errno=0
    final stoken = body['randsk']?.toString() ?? '';
    if (stoken.isEmpty) {
      // 如果 randsk 为空，尝试从 logid 判断
      if (body['errno']?.toString() != '0') {
        throw BaiduException(
          toInt(body['errno'], fallback: -1),
          body['errmsg']?.toString() ?? '分享链接已失效或提取码错误',
        );
      }
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
    final body = await _get('$_baseUrl/rest/2.0/xpan/share', params: {
      'method': 'list',
      'app_id': 250528,
      'web': 1,
      'bdstoken': _bdstoken,
      'shareid': session.shareId,
      'randsk': session.stoken,
      'dir': pdirFid.isEmpty ? '/' : pdirFid,
      'start': (page - 1) * size,
      'limit': size,
      'order': 'time',
      'desc': 1,
    });

    final list = body['list'];
    if (list is! List) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => _parseShareFile(e))
        .toList();
  }

  DriveShareFile _parseShareFile(Map<String, dynamic> json) {
    final isDir = json['isdir'] == 1 || json['isdir'] == true;
    final filename = json['server_filename']?.toString() ?? json['filename']?.toString() ?? '';
    return DriveShareFile(
      fid: json['fs_id']?.toString() ?? '',
      fileName: filename,
      fileType: isDir ? 'folder' : '',
      isDir: isDir,
      size: toInt(json['size']),
      pdirFid: '',
      shareFidToken: json['shareuk']?.toString() ?? '',
    );
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    if (fidList.isEmpty) return [];
    final results = <DriveDownloadInfo>[];

    for (final fid in fidList) {
      try {
        final body = await _get('$_pcsBaseUrl/rest/2.0/pcs/file', params: {
          'method': 'download',
          'app_id': 250528,
          'bdstoken': _bdstoken,
          'fs_id': fid,
          'shareid': session.shareId,
          'randsk': session.stoken,
        });
        final url = body['url']?.toString() ?? body['dlink']?.toString() ?? '';
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
    final fidList = files.map((f) => f.fid).toList();
    final body = await _post('$_baseUrl/share/transfer', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    }, data: {
      'shareid': session.shareId,
      'from': fidList,
      'ondup': 'newcopy',
      'async': 1,
      'filelist': jsonEncode(fidList),
    });

    // 检查转存结果
    final errno = body['errno'];
    if (errno != null && toInt(errno, fallback: 0) != 0) {
      throw BaiduException(
        toInt(errno, fallback: -1),
        body['errmsg']?.toString() ?? '转存失败',
      );
    }
  }

  // ──────────────────── 其他 API ────────────────────

  /// 获取文件元数据（支持批量）
  Future<List<Map<String, dynamic>>> getFileMetas(List<String> fsIds) async {
    final target = jsonEncode(fsIds.map((e) => toInt(e, fallback: 0)).toList());
    final body = await _get('$_baseUrl/api/filemetas', params: {
      'bdstoken': _bdstoken,
      'target': target,
      'dlink': 1,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    });
    final info = body['info'];
    if (info is! List) return [];
    return info.whereType<Map<String, dynamic>>().toList();
  }

  /// 文件管理操作（重命名、移动、复制、删除）
  Future<Map<String, dynamic>> fileManager(
      String operation, List<String> filePaths, String newPath) async {
    final body = await _post('$_baseUrl/api/filemanager', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    }, data: {
      'opera': operation,
      'async': 0,
      'ondup': 'newcopy',
      'filelist': jsonEncode(filePaths.map((p) => {
        'path': p,
        if (operation == 'rename' || operation == 'move') 'newname': newPath,
        if (operation == 'move') 'newdir': newPath,
      }).toList()),
    });
    return body;
  }

  /// 创建文件夹
  Future<Map<String, dynamic>> createFolder(String path) async {
    final body = await _post('$_baseUrl/api/create', params: {
      'a': 'commit',
      'channel': 'chunlei',
      'web': 1,
      'app_id': 250528,
      'clienttype': 0,
    }, data: {
      'path': path,
      'isdir': 1,
      'block_list': jsonEncode([]),
      'bdstoken': _bdstoken,
    });
    return body;
  }

  /// 创建分享链接
  Future<Map<String, dynamic>> createShareLink(
      List<String> paths, {String pwd = ''}) async {
    final body = await _post('$_baseUrl/share/set', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    }, data: {
      'period': 0,
      'schannel': 0,
      'pwd': pwd,
      'cancel': 0,
      'product': 0,
      'plus': 0,
      'second': 0,
      'fid_list': jsonEncode(paths),
    });
    return body;
  }

  /// 获取媒体信息（视频时长、分辨率等）
  Future<Map<String, dynamic>> getMediaInfo(String fsId) async {
    final body = await _get('$_baseUrl/api/mediainfo', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
      'fsids': jsonEncode([toInt(fsId, fallback: 0)]),
    });
    return body;
  }

  /// 获取配额（空间使用情况）
  Future<Map<String, dynamic>> getQuota() async {
    final body = await _get('$_yunBaseUrl/api/quota', params: {
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    });
    return body;
  }

  @override
  void dispose() {
    _dio.close(force: true);
  }
}