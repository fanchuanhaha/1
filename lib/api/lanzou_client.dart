import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'base_drive.dart';
import 'drive_type.dart';

/// 蓝奏云客户端（参考反编译参考APK的 LanzouApi 接口）
///
/// 登录：pc.woozooo.com/mydisk.php（task=3 + formhash）
/// 文件列表：pc.woozooo.com/doupload.php（task=5 文件 / task=47 文件夹）
/// 下载直链：share 信息(task=22) -> 分享页 -> ajaxm.php(downprocess) -> 304 直链
/// 反爬：遇到 acw_sc__v2 封禁页时按算法计算 acw_sc__v2 cookie 后重试
class LanzouClient implements BaseDrive {
  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const String uaMobile =
      'Mozilla/5.0 (Linux; Android 5.0; SM-G900P Build/LRX21T) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/82.0.4051.0 Mobile Safari/537.36';

  static const String accountUrl = 'https://pc.woozooo.com/account.php';
  static const String mydiskUrl = 'https://pc.woozooo.com/mydisk.php';
  static const String douploadUrl = 'https://pc.woozooo.com/doupload.php';
  static const String hostUrl = 'https://pan.lanzouo.com';

  final Dio _dio;
  String _cookie = '';
  String _uid = '0';
  String _username = '';
  DriveUserInfo? _userInfo;

  LanzouClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  @override
  DriveType get type => DriveType.lanzou;

  @override
  String get label => '蓝奏云';

  @override
  bool get hasLogin => _cookie.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie => _cookie.isEmpty ? null : _cookie;

  Map<String, String> _pcHeaders({Map<String, String>? extra}) => {
        'User-Agent': uaPc,
        'Referer': mydiskUrl,
        'Accept-Language': 'zh-CN,zh;q=0.9',
        if (extra != null) ...extra,
        if (_cookie.isNotEmpty) 'Cookie': _cookie,
      };

  /// 解析 set-cookie，合并进 _cookie，并尝试提取 uid(ylogin)
  void _mergeSetCookie(Response resp) {
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
    final uid = entries['ylogin'];
    if (uid != null && uid.isNotEmpty) _uid = uid;
  }

  // ═════════════════════ acw_sc__v2 反爬算法 ═════════════════════

  String _calcAcwV2(String html) {
    final m = RegExp(r"arg1='([0-9A-Z]+)'").firstMatch(html);
    final arg1 = m?.group(1) ?? '';
    if (arg1.isEmpty) return '';
    final key = '3000176000856006061501533003690027800375';
    return _hexXor(_unsbox(arg1), key);
  }

  String _unsbox(String s) {
    const v1 = [
      15, 35, 29, 24, 33, 16, 1, 38, 10, 9, 19, 31, 40, 27, 22, 23, 25, 13, 6,
      11, 39, 18, 20, 8, 14, 21, 32, 26, 2, 30, 7, 4, 17, 5, 3, 28, 34, 37,
      12, 36
    ];
    final v2 = List<String>.filled(v1.length, '');
    for (var idx = 0; idx < s.length; idx++) {
      final ch = s[idx];
      for (var j = 0; j < v1.length; j++) {
        if (v1[j] == idx + 1) {
          v2[j] = ch;
        }
      }
    }
    return v2.join();
  }

  String _hexXor(String a, String b) {
    final len = a.length < b.length ? a.length : b.length;
    final sb = StringBuffer();
    for (var i = 0; i + 1 < len; i += 2) {
      final v1 = int.parse(a.substring(i, i + 2), radix: 16);
      final v2 = int.parse(b.substring(i, i + 2), radix: 16);
      var v3 = (v1 ^ v2).toRadixString(16);
      if (v3.length == 1) v3 = '0$v3';
      sb.write(v3);
    }
    return sb.toString();
  }

  /// 去除 html 注释
  String _removeNotes(String html) =>
      html.replaceAll(RegExp(r'<!--.+?-->', dotAll: true), '');

  // ═════════════════════ 登录 ═════════════════════

  @override
  Future<void> init() async {}

  /// 登录蓝奏云
  /// [credential] 可以是 String (cookie) 或 Map {'username','password'}
  @override
  Future<String?> login(dynamic credential) async {
    try {
      if (credential is String) {
        _cookie = credential;
        _username = '蓝奏云用户';
        _userInfo = DriveUserInfo(
          nickname: _username,
          avatar: '',
          userId: 'lanzou',
        );
        // 尝试从 cookie 提取 uid
        for (final part in _cookie.split(';')) {
          final kv = part.trim();
          final eq = kv.indexOf('=');
          if (eq > 0 && kv.substring(0, eq).trim() == 'ylogin') {
            _uid = kv.substring(eq + 1).trim();
          }
        }
        return null;
      }

      if (credential is Map) {
        final username =
            credential['username']?.toString() ??
            credential['account']?.toString() ??
            '';
        final password = credential['password']?.toString() ?? '';
        if (username.isEmpty || password.isEmpty) return '请输入账号和密码';

        // 第一优先：参考APK的 mydisk.php 登录（task=3 + formhash）
        // 先 GET account.php 获取 formhash
        final accountResp = await _dio.get(
          accountUrl,
          options: Options(
            headers: _pcHeaders(),
            validateStatus: (_) => true,
          ),
        );
        _mergeSetCookie(accountResp);
        final formHash = RegExp(r'name="formhash" value="(.+?)"')
            .firstMatch(accountResp.data?.toString() ?? '')
            ?.group(1);

        if (formHash != null && formHash.isNotEmpty) {
          final resp = await _dio.post(
            mydiskUrl,
            data: {
              'task': '3',
              'setSessionId': '',
              'setToken': '',
              'setSig': '',
              'setScene': '',
              'uid': username,
              'pwd': password,
              'formhash': formHash,
            },
            options: Options(
              headers: _pcHeaders({'User-Agent': uaMobile}),
              contentType: Headers.formUrlEncodedContentType,
              validateStatus: (_) => true,
            ),
          );
          _mergeSetCookie(resp);
          final body = resp.data?.toString() ?? '';
          if (_uid != '0' || body.contains('成功') || body.contains('success')) {
            _finishLogin(username);
            return null;
          }
        }

        // 第二优先：up.woozooo.com/mlogin.php（部分账号可用）
        final resp = await _dio.post(
          'https://up.woozooo.com/mlogin.php',
          data: {'action': 'login', 'username': username, 'password': password},
          options: Options(
            headers: {
              'User-Agent': uaPc,
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': 'https://up.woozooo.com/',
            },
            validateStatus: (_) => true,
          ),
        );
        _mergeSetCookie(resp);
        final body = resp.data?.toString() ?? '';
        if (_cookie.isNotEmpty || body.contains('success') || body.contains('login')) {
          _finishLogin(username);
          return null;
        }
        return '登录失败：账号或密码错误';
      }

      return '无效的凭证格式';
    } catch (e) {
      return '登录请求失败: $e';
    }
  }

  void _finishLogin(String username) {
    _username = username;
    _userInfo = DriveUserInfo(
      nickname: _username,
      avatar: '',
      userId: 'lanzou',
    );
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _uid = '0';
    _username = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {}

  // ═════════════════════ 请求辅助 ═════════════════════

  Future<Response> _post(
    String url,
    Map<String, dynamic> data, {
    bool needUid = false,
  }) async {
    final target = needUid ? '$url?uid=$_uid' : url;
    return _dio.post(
      target,
      data: data,
      options: Options(
        headers: _pcHeaders(),
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (_) => true,
      ),
    );
  }

  Future<Response> _get(String url, {bool followRedirects = true}) async {
    return _dio.get(
      url,
      options: Options(
        headers: _pcHeaders(),
        validateStatus: (_) => true,
        followRedirects: followRedirects,
        if (!followRedirects) maxRedirects: 0,
      ),
    );
  }

  Map<String, dynamic> _jsonBody(Response resp) {
    final data = resp.data;
    if (data is Map) return data.cast<String, dynamic>();
    if (data is String) {
      try {
        final v = jsonDecode(data);
        if (v is Map) return v.cast<String, dynamic>();
      } catch (_) {}
    }
    return {};
  }

  /// 把人类可读大小（如 "1.5 M"）转成字节
  int _parseSize(String s) {
    final m = RegExp(r'([\d.]+)\s*([BKMGT])?', caseSensitive: false)
        .firstMatch(s.trim());
    if (m == null) return 0;
    final num = double.tryParse(m.group(1) ?? '') ?? 0;
    final unit = (m.group(2) ?? 'B').toUpperCase();
    final map = {'B': 1, 'K': 1024, 'M': 1024 * 1024, 'G': 1024 * 1024 * 1024, 'T': 1024 * 1024 * 1024 * 1024};
    return (num * (map[unit] ?? 1)).round();
  }

  String _folderId(String pdirFid) {
    if (pdirFid.isEmpty || pdirFid == '-1' || pdirFid == '0') return '-1';
    return pdirFid;
  }

  // ═════════════════════ 文件列表 ═════════════════════

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    if (_cookie.isEmpty) throw Exception('未登录');
    final folderId = _folderId(pdirFid);
    final files = <DriveFile>[];

    // 文件夹列表（task=47）
    try {
      final dirResp = await _post(
        douploadUrl,
        {'task': 47, 'folder_id': folderId},
        needUid: true,
      );
      final dirBody = _jsonBody(dirResp);
      final text = dirBody['text'];
      if (text is List) {
        for (final f in text.whereType<Map>()) {
          final map = f.cast<String, dynamic>();
          files.add(DriveFile(
            fid: (map['fol_id'] ?? '').toString(),
            fileName: (map['name'] ?? '').toString(),
            fileType: 'folder',
            isDir: true,
            size: 0,
            pdirFid: folderId,
            fileExt: '',
            updatedAt: 0,
          ));
        }
      }
    } catch (_) {}

    // 文件列表（task=5，支持分页）
    var pg = page;
    try {
      while (true) {
        final fileResp = await _post(
          douploadUrl,
          {'task': 5, 'folder_id': folderId, 'pg': pg},
        );
        final body = _jsonBody(fileResp);
        final info = body['info'];
        final text = body['text'];
        if (info != null && info.toString() == '0') {
          break; // 已拿全
        }
        if (text is! List || text.isEmpty) break;
        for (final f in text.whereType<Map>()) {
          final map = f.cast<String, dynamic>();
          final nameAll = (map['name_all'] ?? '').toString().replaceAll('&amp;', '&');
          final ext = nameAll.contains('.')
              ? nameAll.split('.').last
              : '';
          files.add(DriveFile(
            fid: (map['id'] ?? '').toString(),
            fileName: nameAll,
            fileType: ext,
            isDir: false,
            size: _parseSize((map['size'] ?? '').toString()),
            pdirFid: folderId,
            fileExt: ext,
            updatedAt: 0,
          ));
        }
        if (info == null) {
          pg++;
        } else {
          pg++;
        }
        if (pg - page > 50) break; // 防死循环
      }
    } catch (_) {}

    return files;
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    return [];
  }

  // ═════════════════════ 下载 ═════════════════════

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    final results = <DriveDownloadInfo>[];
    for (final fid in fids) {
      try {
        final info = await _fetchDirect(fid);
        if (info != null) results.add(info);
      } catch (_) {
        // 单个文件失败跳过
      }
    }
    return results;
  }

  /// 获取文件信息并解析下载直链
  Future<DriveDownloadInfo?> _fetchDirect(String fid) async {
    // 1. 获取分享链接与提取码（task=22）
    final shareResp = await _post(douploadUrl, {'task': 22, 'file_id': fid});
    final shareBody = _jsonBody(shareResp);
    final info = shareBody['info'];
    if (info is! Map) return null;
    final i = info.cast<String, dynamic>();
    if (i['f_id']?.toString() == 'i') return null;
    final hasPwd = i['onof'].toString() == '1';
    final pwd = hasPwd ? (i['pwd'] ?? '').toString() : '';
    final isNewd = (i['is_newd'] ?? '').toString();
    final fId = i['f_id']?.toString() ?? '';
    if (isNewd.isEmpty || fId.isEmpty) return null;
    final shareUrl = '$isNewd/$fId';

    // 2. 文件名（task=12，text 字段为文件名）
    var name = '';
    try {
      final fi = await _post(douploadUrl, {'task': 12, 'file_id': fid});
      name = _jsonBody(fi)['text']?.toString() ?? '';
    } catch (_) {}

    // 3. 解析直链
    final durl = await _extractDirect(shareUrl, pwd);
    if (durl.isEmpty) return null;
    return DriveDownloadInfo(url: durl, fileName: name.trim(), size: 0, fid: fid);
  }

  /// 从分享页解析下载直链（304 重定向取 Location）
  Future<String> _extractDirect(String url, String pwd) async {
    try {
      var resp = await _get(url);
      var html = resp.data?.toString() ?? '';
      if (html.isEmpty) return '';

      // 反爬 acw_sc__v2
      if (html.contains('acw_sc__v2')) {
        final acw = _calcAcwV2(html);
        if (acw.isNotEmpty) {
          _cookie = (_cookie.split(';')..removeWhere((p) => p.trim().startsWith('acw_sc__v2='))).join('; ');
          _cookie = (_cookie.isEmpty ? '' : '$_cookie; ') + 'acw_sc__v2=$acw';
        }
        resp = await _get(url);
        html = resp.data?.toString() ?? '';
      }
      html = _removeNotes(html);
      if (html.contains('文件取消') || html.contains('文件不存在')) return '';

      Map<String, dynamic> linkInfo;
      if (html.contains('id="pwdload"') || html.contains('id="passwddiv"')) {
        // 有提取码：downprocess 需要带上 p
        if (pwd.isEmpty) return '';
        final sign = RegExp(r'sign=(\w+?)&').firstMatch(html)?.group(1) ?? '';
        if (sign.isEmpty) return '';
        final li = await _dio.post(
          '$hostUrl/ajaxm.php',
          data: {'action': 'downprocess', 'sign': sign, 'p': pwd},
          options: Options(
            headers: _pcHeaders(),
            contentType: Headers.formUrlEncodedContentType,
            validateStatus: (_) => true,
          ),
        );
        linkInfo = _jsonBody(li);
      } else {
        // 无提取码：先取 iframe 下载参数页，再 downprocess
        final para =
            RegExp(r'<iframe.*?src="(.+?)"').firstMatch(html)?.group(1) ?? '';
        if (para.isEmpty) return '';
        final pageResp = await _get('$hostUrl$para');
        final pageHtml = _removeNotes(pageResp.data?.toString() ?? '');
        var sign = RegExp(r"'sign'\s*:\s*'([^']+)'")
                .firstMatch(pageHtml)
                ?.group(1) ??
            '';
        if (sign.isEmpty) return '';
        if (sign.length < 20) {
          final vm = RegExp(r"var $sign\s*=\s*'(.+?)'").firstMatch(pageHtml);
          if (vm != null) sign = vm.group(1)!;
        }
        final li = await _dio.post(
          '$hostUrl/ajaxm.php',
          data: {'action': 'downprocess', 'sign': sign, 'ves': 1},
          options: Options(
            headers: _pcHeaders(),
            contentType: Headers.formUrlEncodedContentType,
            validateStatus: (_) => true,
          ),
        );
        linkInfo = _jsonBody(li);
      }

      if (linkInfo['zt']?.toString() != '1') return '';
      final dom = linkInfo['dom']?.toString() ?? '';
      final fUrl = linkInfo['url']?.toString() ?? '';
      if (dom.isEmpty || fUrl.isEmpty) return '';
      final fakeUrl = '$dom/file/$fUrl';

      final dl = await _get(fakeUrl, followRedirects: false);
      final loc = dl.headers.value('location') ?? dl.headers.value('Location') ?? '';
      if (loc.isNotEmpty) return loc;
      // 个别情况下重定向后的 Location 缺失，尝试从返回体解析 json url
      try {
        final j = jsonDecode(dl.data.toString()) as Map;
        final u = j['url']?.toString() ?? '';
        if (u.isNotEmpty) return u;
      } catch (_) {}
      return '';
    } catch (_) {
      return '';
    }
  }

  // ═════════════════════ 分享（蓝奏云暂不支持转存） ═════════════════════

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    return DriveShareSession(
      shareId: pwdId,
      pwdId: pwdId,
      passcode: passcode,
      stoken: '',
    );
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session,
      String pdirFid,
      {int page = 1, int size = 50}) async {
    return [];
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    return [];
  }

  @override
  Future<void> saveShare(DriveShareSession session,
      List<DriveShareFile> files, String toPdirFid) async {
    // 蓝奏云不支持转存
  }

  @override
  void dispose() {
    _dio.close();
  }
}