import 'dart:convert';

import 'package:dio/dio.dart';

import '../../api/drive_type.dart';
import '../../api/quark_client.dart';

/// 登录服务：封装各网盘的账号密码/验证码登录 API 调用
class LoginService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static Map<String, dynamic> _headers() => {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'User-Agent': QuarkClient.uaPc,
        'Referer': 'https://pan.quark.cn/',
      };

  /// 夸克账号密码登录
  static Future<String?> quarkPasswordLogin({
    required String username,
    required String password,
    String? captcha,
  }) async {
    try {
      final resp = await _dio.post(
        'https://uop.quark.cn/cas/ajax/login',
        data: {
          'username': username,
          'password': password,
          'captcha': captcha ?? '',
          'client_id': '532',
          'v': '1.2',
        },
        options: Options(
          headers: _headers(),
          validateStatus: (_) => true,
        ),
      );
      final body = _decode(resp);
      final status = body['status'];
      if (status == 2000000) {
        // 登录成功，获取cookie
        final setCookies = resp.headers['set-cookie'] ?? [];
        final entries = <String, String>{};
        for (final raw in setCookies) {
          final seg = raw.split(';').first.trim();
          final eq = seg.indexOf('=');
          if (eq <= 0) continue;
          final k = seg.substring(0, eq).trim();
          if (k == 'push_vurl' || k == 'logout_id') continue;
          entries[k] = seg.substring(eq + 1).trim();
        }
        if (entries.isNotEmpty) {
          return entries.entries.map((e) => '${e.key}=${e.value}').join('; ');
        }
        // 尝试从 response body 中获取 token
        final data = body['data'];
        if (data is Map) {
          final token = data['token']?.toString() ?? '';
          if (token.isNotEmpty) {
            return 'token=$token';
          }
        }
        return null;
      }
      final msg = body['message']?.toString() ?? '登录失败';
      if (msg.contains('验证码') || msg.contains('captcha')) {
        throw CaptchaRequiredException(msg);
      }
      throw Exception(msg);
    } on CaptchaRequiredException {
      rethrow;
    } catch (e) {
      throw Exception('登录请求失败: $e');
    }
  }

  /// 夸克发送验证码
  static Future<String?> quarkSendSms(String phone) async {
    try {
      final resp = await _dio.post(
        'https://uop.quark.cn/cas/ajax/sendSmsCode',
        data: {
          'phone': phone,
          'client_id': '532',
          'v': '1.2',
        },
        options: Options(
          headers: _headers(),
          validateStatus: (_) => true,
        ),
      );
      final body = _decode(resp);
      final status = body['status'];
      if (status == 2000000) {
        return null;
      }
      return body['message']?.toString() ?? '发送验证码失败';
    } catch (e) {
      return '发送请求失败: $e';
    }
  }

  /// 夸克验证码登录
  static Future<String?> quarkSmsLogin({
    required String phone,
    required String code,
  }) async {
    try {
      final resp = await _dio.post(
        'https://uop.quark.cn/cas/ajax/smsLogin',
        data: {
          'phone': phone,
          'code': code,
          'client_id': '532',
          'v': '1.2',
        },
        options: Options(
          headers: _headers(),
          validateStatus: (_) => true,
        ),
      );
      final body = _decode(resp);
      final status = body['status'];
      if (status == 2000000) {
        final setCookies = resp.headers['set-cookie'] ?? [];
        final entries = <String, String>{};
        for (final raw in setCookies) {
          final seg = raw.split(';').first.trim();
          final eq = seg.indexOf('=');
          if (eq <= 0) continue;
          final k = seg.substring(0, eq).trim();
          if (k == 'push_vurl' || k == 'logout_id') continue;
          entries[k] = seg.substring(eq + 1).trim();
        }
        if (entries.isNotEmpty) {
          return entries.entries.map((e) => '${e.key}=${e.value}').join('; ');
        }
        return null;
      }
      throw Exception(body['message']?.toString() ?? '验证码登录失败');
    } catch (e) {
      throw Exception('验证码登录请求失败: $e');
    }
  }

  /// 获取网盘网页登录地址
  static String getLoginUrl(DriveType type) {
    switch (type) {
      case DriveType.quark:
        return 'https://pan.quark.cn/';
      case DriveType.ali:
        return 'https://www.aliyundrive.com/';
      case DriveType.baidu:
        return 'https://pan.baidu.com/';
      case DriveType.pikpak:
        return 'https://mypikpak.com/';
      case DriveType.tianyi:
        return 'https://cloud.189.cn/';
      case DriveType.uc:
        return 'https://drive.uc.cn/';
      case DriveType.weiyun:
        return 'https://share.weiyun.com/';
      case DriveType.xunlei:
        return 'https://pan.xunlei.com/';
      case DriveType.pan123:
        return 'https://www.123pan.com/';
      case DriveType.yidong:
        return 'https://caiyun.139.com/';
      case DriveType.guangya:
        return 'https://guangyapan.com/';
    }
  }

  static Map<String, dynamic> _decode(Response<dynamic> resp) {
    final body = resp.data;
    if (body is String) {
      if (body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    }
    if (body is Map) return body.cast<String, dynamic>();
    return {};
  }
}

/// 需要验证码的异常
class CaptchaRequiredException implements Exception {
  final String message;
  CaptchaRequiredException(this.message);

  @override
  String toString() => message;
}