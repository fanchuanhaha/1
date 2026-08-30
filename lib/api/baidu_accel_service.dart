import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';

/// 「野鸡百度加速」第三方解析接口客户端。
///
/// 站点基址 `https://aa.dgg288.xyz/api/v1`（前后端同源）。
/// 流程：给定百度分享链接（可带提取码）→ `get_file_list` 拿到
/// uk/shareid/randsk 与文件列表 → 按 fs_id 调 `get_download_links`
/// 生成带签名的百度网盘直链。
///
/// 说明：该接口需要站点解析密码 [parsePassword]（应由用户在设置中填写）。
class BaiduAccelService {
  static const String baseUrl = 'https://aa.dgg288.xyz/api/v1';
  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static BaiduAccelService? _instance;
  static BaiduAccelService get I => _instance ??= BaiduAccelService._();

  final Dio _dio;

  BaiduAccelService._()
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        ));

  Map<String, dynamic> _headers() => {
        'User-Agent': ua,
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
      };

  /// 从标准分享链接中提取 surl（短码）与 pwd（提取码）。
  /// 兼容 `https://pan.baidu.com/s/1xxx?pwd=xxxx` 与 `.../s/1xxx`。
  static ({String surl, String pwd}) parseShareUrl(String url) {
    var surl = '';
    var pwd = '';
    final u = url.trim();
    final sIdx = u.indexOf('/s/');
    if (sIdx >= 0) {
      var seg = u.substring(sIdx + 3);
      final q = seg.indexOf('?');
      if (q >= 0) seg = seg.substring(0, q);
      final slash = seg.indexOf('/');
      if (slash > 0) seg = seg.substring(0, slash);
      surl = seg.trim();
    }
    final uri = Uri.tryParse(u);
    pwd = uri?.queryParameters['pwd'] ?? '';
    return (surl: surl, pwd: pwd);
  }

  /// POST JSON 并返回 data 字段，失败抛 [BaiduAccelException]。
  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    AppLogger.I.i('baidu_accel', 'POST $path 字段=${body.keys.toList()}');
    Response<dynamic> resp;
    try {
      resp = await _dio.post(path,
          data: jsonEncode(body), options: Options(headers: _headers()));
    } on DioException catch (e) {
      // 尽量透出服务器实际响应（状态码 + body），便于定位 4xx/5xx 具体原因。
      var detail = e.toString();
      final r = e.response;
      if (r != null) {
        var respBody = r.data;
        if (respBody is Map || respBody is List) respBody = jsonEncode(respBody);
        if (respBody is String && respBody.length > 300) {
          respBody = respBody.substring(0, 300);
        }
        detail = 'HTTP ${r.statusCode} ${respBody ?? ""}'.trim();
      }
      AppLogger.I.e('baidu_accel', '请求失败 $path: $e');
      throw BaiduAccelException('接口请求失败($path): $detail');
    }
    final data = resp.data;
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data);
      } catch (_) {}
    }
    if (data is! Map) {
      throw BaiduAccelException('接口返回格式异常');
    }
    final code = data['code'];
    if (code is num && code != 200) {
      throw BaiduAccelException(
          data['message']?.toString() ?? '接口返回错误(code=$code)');
    }
    return data['data'];
  }

  /// 解析分享链接 → 文件列表。返回 [BaiduAccelFileList]。
  /// [pwd] 分享链接的提取码；若链接本身已带 `?pwd=` 亦可由 [url] 解析出来。
  Future<BaiduAccelFileList> getFileList({
    required String url,
    required String parsePassword,
    String pwd = '',
    String dir = '/',
  }) async {
    final parsed = parseShareUrl(url);
    final finalPwd = (pwd.isNotEmpty ? pwd : parsed.pwd);
    final surl = parsed.surl.isEmpty ? _surlFromAny(url) : parsed.surl;
    final data = await _post('/user/parse/get_file_list', {
      'url': url,
      'surl': surl,
      'pwd': finalPwd,
      'dir': dir,
      'parse_password': parsePassword,
    });
    if (data is! Map) throw BaiduAccelException('未返回文件列表数据');
    return BaiduAccelFileList.fromJson(data.cast<String, dynamic>());
  }

  /// 生成下载直链，返回每个 fs_id 对应的直链结果（含该直链要求的下载 UA）。
  ///
  /// 返回的 [BaiduAccelDownloadLink] 里带 `ua` 字段——这是解析服务为这条
  /// 直链绑定的下载 User-Agent，下载时必须原样带上，且不要附带本账号的个人
  /// cookie（该直链属于分享/匿名上下文，带个人 cookie 会导致 CDN 鉴权失败）。
  Future<Map<String, BaiduAccelDownloadLink>> getDownloadLinks({
    required BaiduAccelFileList fileList,
    required List<String> fsIds,
    required String surl,
    required String pwd,
    required String parsePassword,
    String dir = '/',
  }) async {
    final data = await _post('/user/parse/get_download_links', {
      'randsk': fileList.randsk,
      'uk': fileList.uk,
      'shareid': fileList.shareId,
      // 契约要求 fs_id 恒为数值数组（即使只有一个文件也要 `[fs_id]`），
      // 传单值字符串会被后端判为格式错误。
      'fs_id': fsIds.map((f) => toInt(f, fallback: 0)).toList(),
      'surl': surl,
      'dir': dir,
      'pwd': pwd,
      'token': fileList.token.isNotEmpty ? fileList.token : 'guest',
      'parse_password': parsePassword,
      'vcode_str': '',
      'vcode_input': '',
    });
    final result = <String, BaiduAccelDownloadLink>{};
    void addItem(Map item) {
      final fid = item['fs_id']?.toString() ?? '';
      final urls = item['urls'];
      if (fid.isEmpty || urls is! List) return;
      result[fid] = BaiduAccelDownloadLink(
        urls: urls.map((e) => e.toString()).where((u) => u.isNotEmpty).toList(),
        ua: item['ua']?.toString() ?? '',
      );
    }

    if (data is List) {
      for (final item in data) {
        if (item is Map) addItem(item.cast<String, dynamic>());
      }
    } else if (data is Map) {
      addItem(data.cast<String, dynamic>());
    }
    return result;
  }

  /// 兜底从任意字符串里抠出 surl（形如 `/s/XXXX` 的短码）。
  String _surlFromAny(String url) {
    final m = RegExp(r's/([A-Za-z0-9_\-]+)').firstMatch(url);
    return m?.group(1) ?? '';
  }

  /// 查询当前账号的剩余解析额度。
  ///
  /// 站点口径（`/user/parse/limit?token=guest`）：
  /// - `count` = 剩余可解析文件数（次数）
  /// - `size`  = 剩余可解析大小（流量，字节）
  /// - `expires_at` = 额度到期时间（未使用时为空）
  ///
  /// token 固定用站点默认的 `guest` 会话（未填写卡密时网站前端也是用它），
  /// 与解析直链的会话保持一致。失败抛出 [BaiduAccelException]。
  Future<BaiduAccelQuota> getQuota() async {
    Response<dynamic> resp;
    try {
      resp = await _dio.get(
        '/user/parse/limit',
        queryParameters: {'token': 'guest'},
        options: Options(headers: _headers(), validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      AppLogger.I.e('baidu_accel', '查询剩余额度失败: $e');
      throw BaiduAccelException('查询剩余额度失败: $e');
    }
    final data = resp.data;
    if (data is String && data.isNotEmpty) {
      try {
        return _parseQuota(jsonDecode(data));
      } catch (_) {}
    }
    if (data is! Map) {
      throw BaiduAccelException('剩余额度接口返回格式异常');
    }
    return _parseQuota(data);
  }

  BaiduAccelQuota _parseQuota(Map data) {
    final code = data['code'];
    if (code is num && code != 200) {
      throw BaiduAccelException(
          data['message']?.toString() ?? '剩余额度查询失败(code=$code)');
    }
    final d = data['data'];
    if (d is! Map) throw BaiduAccelException('剩余额度数据异常');
    return BaiduAccelQuota(
      count: toInt(d['count']),
      size: toInt(d['size']),
      expiresAt: d['expires_at']?.toString(),
    );
  }

  void dispose() {
    _dio.close(force: true);
  }
}

/// 接口异常
class BaiduAccelException implements Exception {
  final String message;

  BaiduAccelException(this.message);

  @override
  String toString() => message;
}

/// get_file_list 的解析结果：分享会话参数 + 文件列表。
class BaiduAccelFileList {
  final int uk;
  final int shareId;
  final String randsk;
  final List<BaiduAccelFile> list;

  /// 会话 token（部分接口在 get_file_list 阶段返回，供 get_download_links 复用）。
  final String token;

  BaiduAccelFileList({
    required this.uk,
    required this.shareId,
    required this.randsk,
    required this.list,
    required this.token,
  });

  factory BaiduAccelFileList.fromJson(Map<String, dynamic> json) {
    final listRaw = json['list'];
    final list = <BaiduAccelFile>[];
    if (listRaw is List) {
      for (final e in listRaw) {
        if (e is Map) {
          list.add(BaiduAccelFile.fromJson(e.cast<String, dynamic>()));
        }
      }
    }
    return BaiduAccelFileList(
      uk: toInt(json['uk']),
      shareId: toInt(json['shareid']),
      randsk: json['randsk']?.toString() ?? '',
      list: list,
      token: json['token']?.toString() ?? '',
    );
  }
}

/// 一条加速直链的解析结果：直链列表 + 该链接要求的下载 User-Agent。
class BaiduAccelDownloadLink {
  final List<String> urls;
  final String ua;

  BaiduAccelDownloadLink({required this.urls, required this.ua});

  bool get hasUrl => urls.isNotEmpty;
}

/// 剩余解析额度（`/user/parse/limit` 返回）。
/// `count` = 剩余可解析文件数（次数），`size` = 剩余可解析大小（流量，字节）。
class BaiduAccelQuota {
  final int count;
  final int size;
  final String? expiresAt;

  const BaiduAccelQuota({
    required this.count,
    required this.size,
    this.expiresAt,
  });
}

/// 分享文件列表项
class BaiduAccelFile {
  final String fsId;
  final String serverFilename;
  final int size;
  final bool isDir;

  BaiduAccelFile({
    required this.fsId,
    required this.serverFilename,
    required this.size,
    required this.isDir,
  });

  factory BaiduAccelFile.fromJson(Map<String, dynamic> json) {
    return BaiduAccelFile(
      fsId: json['fs_id']?.toString() ?? '',
      serverFilename:
          json['server_filename']?.toString() ?? json['filename']?.toString() ?? '',
      size: toInt(json['size']),
      isDir: json['is_dir'] == 1 || json['is_dir'] == true,
    );
  }
}