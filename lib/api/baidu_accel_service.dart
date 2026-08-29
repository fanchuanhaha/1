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
    } catch (e) {
      AppLogger.I.e('baidu_accel', '请求失败 $path: $e');
      throw BaiduAccelException('网络请求失败: $e');
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
  Future<BaiduAccelFileList> getFileList({
    required String url,
    required String parsePassword,
    String dir = '/',
  }) async {
    final parsed = parseShareUrl(url);
    final surl = parsed.surl.isEmpty ? _surlFromAny(url) : parsed.surl;
    final data = await _post('/user/parse/get_file_list', {
      'url': url,
      'surl': surl,
      'pwd': parsed.pwd,
      'dir': dir,
      'parse_password': parsePassword,
    });
    if (data is! Map) throw BaiduAccelException('未返回文件列表数据');
    return BaiduAccelFileList.fromJson(data.cast<String, dynamic>());
  }

  /// 生成下载直链，返回每个 fs_id 对应的直链列表。
  Future<Map<String, List<String>>> getDownloadLinks({
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
      'fs_id': fsIds,
      'surl': surl,
      'dir': dir,
      'pwd': pwd,
      'token': 'guest',
      'parse_password': parsePassword,
      'vcode_str': '',
      'vcode_input': '',
    });
    final result = <String, List<String>>{};
    if (data is List) {
      for (final item in data) {
        if (item is Map) {
          final fid = item['fs_id']?.toString() ?? '';
          final urls = item['urls'];
          if (fid.isNotEmpty && urls is List) {
            result[fid] =
                urls.map((e) => e.toString()).where((u) => u.isNotEmpty).toList();
          }
        }
      }
    }
    return result;
  }

  /// 兜底从任意字符串里抠出 surl（形如 `/s/XXXX` 的短码）。
  String _surlFromAny(String url) {
    final m = RegExp(r's/([A-Za-z0-9_\-]+)').firstMatch(url);
    return m?.group(1) ?? '';
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

  BaiduAccelFileList({
    required this.uk,
    required this.shareId,
    required this.randsk,
    required this.list,
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
    );
  }
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