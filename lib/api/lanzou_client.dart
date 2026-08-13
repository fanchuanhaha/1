import 'dart:async';

import 'package:dio/dio.dart';

import 'base_drive.dart';
import 'drive_type.dart';

/// 蓝奏云客户端（参考APK的 LanzouApi）
class LanzouClient implements BaseDrive {
  static const String uaPc =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const String loginUrl = 'https://up.woozooo.com/mlogin.php';
  static const String diskUrl = 'https://pc.woozooo.com/mydisk.php';
  static const String shareUrl = 'https://pan.lanzoui.com';
  static const String apiUrl = 'https://developer.lanzoug.com';

  final Dio _dio;
  String _cookie = '';
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

  @override
  Future<void> init() async {}

  /// 登录蓝奏云
  /// [credential] 可以是 String (cookie) 或 Map {'username','password'}
  @override
  Future<String?> login(dynamic credential) async {
    try {
      if (credential is String) {
        // Cookie 登录
        _cookie = credential;
        _username = '蓝奏云用户';
        _userInfo = DriveUserInfo(
          nickname: _username,
          avatar: '',
          userId: 'lanzou',
        );
        return null;
      }

      if (credential is Map) {
        final username = credential['username']?.toString() ?? credential['account']?.toString() ?? '';
        final password = credential['password']?.toString() ?? '';
        if (username.isEmpty || password.isEmpty) return '请输入账号和密码';

        // 密码登录（参考APK的 mlogin.php）
        final resp = await _dio.post(
          'https://up.woozooo.com/mlogin.php',
          data: {
            'action': 'login',
            'username': username,
            'password': password,
          },
          options: Options(
            headers: {
              'User-Agent': uaPc,
              'Content-Type': 'application/x-www-form-urlencoded',
              'Referer': 'https://up.woozooo.com/',
            },
            validateStatus: (_) => true,
          ),
        );

        // 从 set-cookie 获取登录凭证
        final setCookies = resp.headers['set-cookie'] ?? [];
        final entries = <String, String>{};
        for (final raw in setCookies) {
          final seg = raw.split(';').first.trim();
          final eq = seg.indexOf('=');
          if (eq <= 0) continue;
          entries[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
        }
        if (entries.isNotEmpty) {
          _cookie = entries.entries.map((e) => '${e.key}=${e.value}').join('; ');
          _username = username;
          _userInfo = DriveUserInfo(
            nickname: _username,
            avatar: '',
            userId: 'lanzou',
          );
          return null;
        }

        // 检查响应内容是否包含登录成功标识
        final body = resp.data?.toString() ?? '';
        if (body.contains('success') || body.contains('login')) {
          _username = username;
          _userInfo = DriveUserInfo(
            nickname: _username,
            avatar: '',
            userId: 'lanzou',
          );
          return null;
        }

        return '登录失败：账号或密码错误';
      }

      return '无效的凭证格式';
    } catch (e) {
      return '登录请求失败: $e';
    }
  }

  @override
  Future<void> logout() async {
    _cookie = '';
    _username = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    // 蓝奏云暂不支持获取用户信息
  }

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    return [];
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    return [];
  }

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    return [];
  }

  @override
  Future<DriveShareSession> getShareToken(
      String pwdId, String passcode) async {
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