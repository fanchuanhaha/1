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
      // 百度部分接口返回的 gzip 数据 Dart 的 zlib 解码会报 "Filter error, bad data"，
      // 显式要求明文响应以规避解码崩溃（百度会遵守 identity）。
      'Accept-Encoding': 'identity',
      if (_bduss.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    bool isJson = false,
    bool isForm = false,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = Map<String, dynamic>.from(_buildHeaders());
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (isForm) {
      // 百度部分接口（api/filemanager）要求 application/x-www-form-urlencoded
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (extraHeaders != null) headers.addAll(extraHeaders);

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
    // 合并所有 set-cookie。BDUSS/STOKEN 单独留存到字段；
    // 其余辅助 cookie（BAIDUID 等）整体并入 _rawCookie，发送请求时随 Cookie 头带给百度。
    final all = _cookieToMap(_rawCookie);
    // 无论是否从 set-cookie 拿到 BDUSS/STOKEN，都保证字段值在 Cookie 头中
    if (_bduss.isNotEmpty) all['BDUSS'] = _bduss;
    if (_stoken.isNotEmpty) all['STOKEN'] = _stoken;
    for (final raw in setCookies) {
      final seg = raw.split(';').first.trim();
      final eq = seg.indexOf('=');
      if (eq <= 0) continue;
      all[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
    }
    if (all.containsKey('BDUSS')) _bduss = all['BDUSS']!;
    if (all.containsKey('STOKEN')) _stoken = all['STOKEN']!;
    _rawCookie = all.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 把 cookie 字符串解析为 {key: value}
  static Map<String, String> _cookieToMap(String cookie) {
    final map = <String, String>{};
    for (final seg in cookie.split(';')) {
      final t = seg.trim();
      final eq = t.indexOf('=');
      if (eq <= 0) continue;
      final k = t.substring(0, eq).trim();
      final v = t.substring(eq + 1).trim();
      if (v.isNotEmpty) map[k] = v;
    }
    return map;
  }

  /// 补齐 baidu 依赖的基础 cookie（BAIDUID 等）。
  /// 百度分享/解析接口（share/init、share/list、shorturlinfo）无 BAIDUID 时经常
  /// 直接返回 errno=-3/-12；先请求一次首页拿到 set-cookie，行为与 BaiduPCS-Py 一致。
  Future<void> _ensureBaseCookie() async {
    if (_rawCookie.contains('BAIDUID=') || _hasCookieKey('BAIDUID')) return;
    try {
      final resp = await _dio.request(
        '$_baseUrl/',
        options: Options(
          method: 'GET',
          headers: {
            'User-Agent': _ua,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
          validateStatus: (_) => true,
        ),
      );
      _mergeSetCookie(resp);
      AppLogger.I.i('baidu',
          '基础 cookie 补齐 BAIDUID=${_rawCookie.contains("BAIDUID")}');
    } catch (e) {
      AppLogger.I.e('baidu', '补齐基础 cookie 失败: $e');
    }
  }

  bool _hasCookieKey(String key) {
    final lower = key.toLowerCase();
    for (final k in _cookieToMap(_rawCookie).keys) {
      if (k.toLowerCase() == lower) return true;
    }
    return false;
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
    bool isForm = false,
  }) async {
    final body = await _request('POST', url,
        params: params, data: data, isJson: isJson, isForm: isForm);
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
    // 百度接口 isdir 可能是 int 1 或字符串 "1"，统一按字符串判断
    final isDir = json['isdir']?.toString() == '1';
    final serverFilename = json['server_filename']?.toString() ?? '';
    final filename = json['filename']?.toString() ?? json['server_filename']?.toString() ?? '';
    final path = json['path']?.toString() ?? '';
    final ext = filename.contains('.')
        ? filename.substring(filename.lastIndexOf('.') + 1).toLowerCase()
        : '';
    // 注意：百度 filemetas 的 target 必须传文件完整路径，故用 path 作为 fid，
    // 这样目录跳转(listFiles(dir=fid))与下载(getDownloadInfo)都能共用。
    final fid = path.isNotEmpty
        ? path
        : (json['fs_id']?.toString() ?? json['uk']?.toString() ?? '');
    return DriveFile(
      fid: fid,
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

    // filemetas 的 target 必须传文件完整路径（实测 fs_id 返回 errno=12），
    // fids 已在 _parseDriveFile 中定义为 path，故直接序列化即可。
    String fileMetasJson = jsonEncode(fids);
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

    // 如果 dlink 方式未获取到，尝试 PCS 下载（参数用文件路径）
    if (results.isEmpty) {
      for (final fid in fids) {
        try {
          final body = await _get('$_pcsBaseUrl/rest/2.0/pcs/file', params: {
            'method': 'download',
            'app_id': 250528,
            'bdstoken': _bdstoken,
            'path': fid,
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
    // 先确保 BAIDUID 等基础 cookie 就位，否则 shorturlinfo/verify 易返回 errno=-3/-12
    // （该做法与 BaiduPCS-Py 先访问分享首页拿 cookie 一致）。
    await _ensureBaseCookie();
    // 百度分享链接的 pwdId 是 surl 短码（如 1XXXXX）。share/verify 需要的是
    // 真实数字 shareid + 来源 uk，需先解析（否则返回 errno=-12）。
    // 注意：网页端的 /share/init 现返回 404 页面，改走 JSON 接口 api/shorturlinfo 解析。
    var shareId = pwdId;
    var uk = 0;
    final looksSurl = RegExp(r'^1[A-Za-z0-9]{3,}$').hasMatch(pwdId);
    if (looksSurl) {
      // 用 _request（不 auto-throw）而非 _get：对带提取码的私密分享，
      // shorturlinfo 会返回 errno=-9「提取码验证失败」但 body 里仍带有正确的
      // shareid/uk，此时不应直接判失败，而是继续走 verify 去校验提取码。
      final short = await _request('GET', '$_baseUrl/api/shorturlinfo', params: {
        'shorturl': pwdId,
        'clienttype': 0,
        'app_id': 250528,
        'web': 1,
        'channel': 'chunlei',
      });
      // shorturlinfo 返回扁平结构：shareid/uk/errno 都在顶层，没有 data 包裹。
      final errno = toInt(short['errno'], fallback: -1);
      final initShare = short['shareid']?.toString() ?? '';
      if (initShare.isNotEmpty) {
        shareId = initShare;
      }
      uk = toInt(short['uk']);
      AppLogger.I.i('baidu',
          'shorturlinfo 结果 errno=$errno shareid=${short['shareid']} uk=${short['uk']} show_msg=${short['show_msg']}');
      final msg = short['errmsg']?.toString() ??
          short['show_msg']?.toString() ??
          '分享链接解析失败';
      // 只有当 shareid/uk 都没拿到（如 -3=分享已删除）才判失败；
      // -9 需要提取码等情形 shareid/uk 已具备，可继续走 verify。
      if (initShare.isEmpty && uk <= 0) {
        throw BaiduException(errno, msg);
      }
    }

    // 校验提取码：与网页端一致——query 带 t/bioc/surl/shareid/uk，
    // 表单带 pwd/vcode/vcode_str。缺 shareid/uk 或 Referer 会返回 errno 2/105。
    final t = '${DateTime.now().millisecondsSinceEpoch}';
    final verify = await _request('POST', '$_baseUrl/share/verify', params: {
      't': t,
      'bioc': 1,
      'surl': pwdId,
      'shareid': shareId,
      'uk': uk,
    }, data: {
      'pwd': passcode,
      'vcode': '',
      'vcode_str': '',
    }, extraHeaders: {
      'Referer': '$_baseUrl/s/$pwdId${passcode.isNotEmpty ? '?pwd=$passcode' : ''}',
    });
    AppLogger.I.i('baidu',
        'share/verify 结果 errno=${verify['errno']} randsk=${verify['randsk']}');

    final verr = toInt(verify['errno'], fallback: -1);
    var stoken = verify['randsk']?.toString() ?? '';
    if (stoken.isNotEmpty) {
      // randsk 返回 URL 编码（含 %2B/%3D），解码后再交给 list/download 接口使用
      try {
        stoken = Uri.decodeComponent(stoken);
      } catch (_) {}
    }
    if (verr != 0 || stoken.isEmpty) {
      throw BaiduException(
        verr != 0 ? verr : -1,
        verify['errmsg']?.toString() ??
            verify['show_msg']?.toString() ??
            '提取码错误或分享已失效',
      );
    }

    return DriveShareSession(
      shareId: shareId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: stoken,
      uk: uk,
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session,
      String pdirFid,
      {int page = 1, int size = 50}) async {
    final body = await _request('GET', '$_baseUrl/rest/2.0/xpan/share', params: {
      'method': 'list',
      'app_id': 250528,
      'web': 1,
      'shareid': session.shareId,
      'uk': session.uk,
      'randsk': session.stoken,
      // 根目录 root=1 且 dir='/'；子目录 root=0 且 dir 为该目录的分享路径
      'root': (pdirFid.isEmpty || pdirFid == '/' || pdirFid == '0') ? 1 : 0,
      'dir': (pdirFid.isEmpty || pdirFid == '0') ? '/' : pdirFid,
      'page': page,
      'num': size,
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
    // 百度接口 isdir 可能是 int 1 或字符串 "1"，统一按字符串判断
    final isDir = json['isdir']?.toString() == '1';
    final filename = json['server_filename']?.toString() ?? json['filename']?.toString() ?? '';
    final path = json['path']?.toString() ?? '';
    return DriveShareFile(
      fid: json['fs_id']?.toString() ?? '',
      fileName: filename,
      fileType: isDir ? 'folder' : '',
      isDir: isDir,
      size: toInt(json['size']),
      // path 形如 /apps/xxx.apk，父目录用于分割线/子目录跳转；根目录统一为 '/'
      pdirFid: path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '/',
      // 进入该文件夹时，listShare 的 dir 必须是文件夹自身的完整路径（不是 fs_id）。
      dirId: path,
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
    // 百度网页端 share/transfer 的协议（与 BaiduPCS-Go / 浏览器抓包一致）：
    //  query: shareid + from(=分享者 uk) + sekey(=verify 返回的 randsk) + bdstoken + 固定项
    //  form : filelist(选中资源在分享里的路径, JSON 数组) + path(保存到本账号的目标目录) + ondup + async
    // 注意：from 是分享者 uk，不是 fs_id 列表；缺 sekey 私密分享会被拒绝。
    final filelist = files.map((f) {
      final parent = (f.pdirFid ?? '').trim();
      if (parent == '/' || parent.isEmpty) return '/${f.fileName}';
      return parent.endsWith('/')
          ? '$parent${f.fileName}'
          : '$parent/${f.fileName}';
    }).toList();
    final targetDir =
        (toPdirFid == null || toPdirFid.isEmpty || toPdirFid == '0')
            ? '/'
            : toPdirFid;
    final body = await _post('$_baseUrl/share/transfer', params: {
      'shareid': session.shareId,
      'from': session.uk.toString(),
      if (session.stoken.isNotEmpty) 'sekey': session.stoken,
      'bdstoken': _bdstoken,
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
      'channel': 'chunlei',
    }, data: {
      'filelist': jsonEncode(filelist),
      'path': targetDir,
      'ondup': 'newcopy',
      'async': 1,
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
    // 百度 filemetas 的 target 必须传文件完整路径（实测 fs_id 返回 errno=12）
    final target = jsonEncode(fsIds.toList());
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

  /// 创建分享链接（form 编码，fid_list 为 fs_id 的 JSON 字符串）
  /// [period] 有效期：0 永久、1 一天、7 七天、30 三十天。
  Future<Map<String, dynamic>> createShareLink(
      List<String> paths, {String pwd = '', int period = 0}) async {
    final fields = <String, dynamic>{
      'period': period,
      'schannel': 4,
      'channel_list': '[]',
      'fid_list': jsonEncode(paths),
    };
    // 仅在设置了提取码时才传 pwd（空 pwd 会被百度判定为 "pwd length param error"）
    if (pwd.isNotEmpty) {
      fields['pwd'] = pwd;
    }
    final body = await _postForm('$_baseUrl/share/set', params: {
      'bdstoken': _bdstoken,
      'channel': 'chunlei',
      'clienttype': 0,
      'app_id': 250528,
      'web': 1,
    }, fields: fields);
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

  // ──────────────────── 文件管理操作实现（BaseDrive） ────────────────────

  @override
  bool get supportsFileOps => true;

  @override
  bool get supportsShare => true;

  @override
  bool get supportsRename => true;

  @override
  bool get supportsMove => true;

  /// 把 fids（百度下为文件完整路径）统一转成 fs_id 数字列表（供分享等接口使用）。
  Future<List<int>> _fidsToFsIds(List<String> fids) async {
    if (fids.isEmpty) return [];
    final metas = await getFileMetas(fids);
    return metas
        .map((m) => toInt(m['fs_id']))
        .where((v) => v > 0)
        .toList();
  }

  @override
  Future<DriveShareResult> shareFiles(List<String> fids,
      {int? period, String? pwd, bool requirePwd = true}) async {
    if (fids.isEmpty) throw StateError('请先选择文件');
    final fsIds = await _fidsToFsIds(fids);
    if (fsIds.isEmpty) throw StateError('未能获取文件信息，请重试');
    // 私密分享：默认生成 4 位提取码；公开分享易被百度风控判为“账号异常，禁止分享”(errno 115)，
    // 故百度即使 requirePwd=false 也强制私密分享避免封号。
    final finalPwd =
        (pwd != null && pwd.isNotEmpty) ? pwd : _randomSharePwd();
    final body = await createShareLink(
      fsIds.map((e) => e.toString()).toList(),
      pwd: finalPwd,
      period: period ?? 0,
    );
    final errno = toInt(body['errno'], fallback: 0);
    if (body.containsKey('errno') && errno != 0) {
      throw StateError(body['errmsg']?.toString() ??
          body['show_msg']?.toString() ??
          '创建分享链接失败($errno)');
    }
    var link = body['link']?.toString() ?? '';
    // 分享短码：反应字段是 shorturl（注意不是 surl / shortlink），可能返回完整链接或短码。
    var surl = _surlFromShareBody(body, link);
    if (link.isEmpty && surl.isNotEmpty) {
      link = 'https://pan.baidu.com/s/$surl';
    }
    if (link.isEmpty) throw StateError('创建分享链接失败：未返回分享地址');
    // 校验分享是否真的配置了提取码：响应 body 通常不含 pwd，但 qrcodeurl/分享二维码里会带 pwd，
    // 以我们发送的提取码为准。
    final respPwd = (body['pwd']?.toString().isNotEmpty ?? false)
        ? body['pwd'].toString()
        : finalPwd;
    // 注意：这里不把 pwd 拼进 url，避免上层再拼一次导致 “?pwd=xxxx?pwd=xxxx” 双密码。
    return DriveShareResult(url: link, pwd: respPwd, surl: surl);
  }

  /// 生成 4 位随机数字提取码（1000-9999）
  static String _randomSharePwd() {
    final r = DateTime.now().microsecondsSinceEpoch;
    return (1000 + (r % 9000)).toString();
  }

  /// 从分享创建响应体中提取分享短码 surl。
  /// body 的反应字段是 `shorturl`（完整链接），其次是 `surl`/`shortlink`（短码），
  /// 最后可从 `link` 里 `/s/{surl}` 兜底抠出。
  static String _surlFromShareBody(Map<String, dynamic> body, String link) {
    final short =
        body['shorturl']?.toString() ?? body['surl']?.toString() ?? body['shortlink']?.toString() ?? '';
    if (short.isNotEmpty) {
      final sIdx = short.indexOf('/s/');
      if (sIdx >= 0) {
        var seg = short.substring(sIdx + 3);
        final q = seg.indexOf('?');
        if (q >= 0) seg = seg.substring(0, q);
        final slash = seg.indexOf('/');
        if (slash > 0) seg = seg.substring(0, slash);
        if (seg.isNotEmpty) return seg;
      }
      // 已是短码（不含路径分隔）
      if (!short.contains('/') && short.isNotEmpty) return short;
    }
    final m = RegExp(r'/s/([A-Za-z0-9_\-]+)').firstMatch(link);
    return m?.group(1) ?? '';
  }

  /// 统一的 filemanager 调用：entries 形如 {path, newname?}，返回 null 表示成功。
  /// 手写 urlencoded 字符串（百度部分接口必须 form 编码，且不接受 JSON body）
  static String _encodeForm(Map<String, dynamic> fields) {
    final parts = <String>[];
    fields.forEach((k, v) {
      parts.add('$k=${Uri.encodeQueryComponent(v.toString())}');
    });
    return parts.join('&');
  }

  /// 以 application/x-www-form-urlencoded 提交，data 为手写编码字符串
  Future<Map<String, dynamic>> _postForm(
    String url, {
    Map<String, dynamic>? params,
    required Map<String, dynamic> fields,
  }) async {
    final body = await _request('POST', url,
        params: params, data: _encodeForm(fields), isForm: true);
    return _checkAndReturn(body);
  }

  Future<String?> _runManager(String opera, List<Map<String, dynamic>> entries) async {
    try {
      // 百度 api/filemanager 固定：opera/async/ondup/channel 等置于 query，
      // 只有 filelist 放表单 body。误放 body 会返回 errno=2(参数错误)。
      final body = await _postForm('$_baseUrl/api/filemanager', params: {
        'bdstoken': _bdstoken,
        'clienttype': 0,
        'app_id': 250528,
        'web': 1,
        'channel': 'chunlei',
        'opera': opera,
        'async': 2,
        'ondup': 'newcopy',
      }, fields: {
        'filelist': jsonEncode(entries),
      });
      final errno = toInt(body['errno'], fallback: 0);
      if (errno != 0) {
        return body['errmsg']?.toString() ?? body['show_msg']?.toString() ?? '操作失败($errno)';
      }
      // async=2 时仅返回 taskid，任务异步执行成功与否见 errno
      return null;
    } catch (e) {
      return '操作失败: $e';
    }
  }

  @override
  Future<String?> renameFile(String fid, String newName) {
    return _runManager('rename', [
      {'path': fid, 'newname': newName},
    ]);
  }

  @override
  Future<String?> moveFiles(List<String> fids, String toDirFid) {
    final entries = fids
        .map((p) => {
              'path': p,
              // 百度 move：每个条目需 path(源绝对路径) + dest(目标目录) + newname(文件名)，
              // 缺 newname 会返回 errno=2 参数错误。
              'dest': toDirFid,
              'newname': p.split('/').last,
            })
        .toList();
    return _runManager('move', entries);
  }

  @override
  Future<String?> copyFiles(List<String> fids, String toDirFid) {
    final entries = fids
        .map((p) => {
              'path': p,
              'dest': toDirFid,
              'newname': p.split('/').last,
            })
        .toList();
    return _runManager('copy', entries);
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