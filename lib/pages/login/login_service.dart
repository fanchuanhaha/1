import 'dart:convert';

import 'package:dio/dio.dart';

import '../../api/drive_type.dart';

/// 参考APK的 UA 字符串
const String _uaPc = 
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const String _uaQuarkPc =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) quark-cloud-drive/2.5.20 Chrome/100.0.4896.160 Electron/18.3.5.12-a038f7b798 Safari/537.36 Channel/pckk_other_ch';
const String _uaUcPc =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) uc-cloud-drive/1.6.1 Chrome/100.0.4896.160 Electron/18.3.5.16-b62cf9c50d Safari/537.36 Channel/ucpan_other_ch';

/// 登录服务：封装各网盘的账号密码/验证码登录 API 调用
class LoginService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // ═══════════════════════════════════════════════════════════════
  // 天翼云盘密码登录（参考APK的 TianyiPasswordLoginDebug）
  // 使用 open.e.189.cn 的 OAuth2 登录流程
  // ═══════════════════════════════════════════════════════════════

  /// 天翼云盘密码登录
  /// 返回 {cookie, sessionKey, sessionSecret, accessToken} 或抛出异常
  static Future<Map<String, dynamic>> tianyiPasswordLogin({
    required String phone,
    required String password,
    String? captchaToken,
    String? captchaCode,
  }) async {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': _uaPc,
      'Referer': 'https://cloud.189.cn/',
    };

    try {
      // 1. 获取 appId 和 returnUrl（参考APK的 appConf.do）
      final appConfResp = await _dio.get(
        'https://open.e.189.cn/api/logbox/oauth2/appConf.do',
        options: Options(headers: {
          ...headers,
          'Content-Type': 'application/x-www-form-urlencoded',
        }, validateStatus: (_) => true),
      );
      final appConf = _decode(appConfResp);
      final appId = appConf['appId']?.toString() ?? '';
      final returnUrl = appConf['returnUrl']?.toString() ?? '';

      // 2. 检查是否需要验证码（参考APK的 needcaptcha.do）
      if (captchaToken == null) {
        final needResp = await _dio.post(
          'https://open.e.189.cn/api/logbox/oauth2/needcaptcha.do',
          data: {'accountType': '1', 'account': phone, 'appId': appId},
          options: Options(headers: headers, validateStatus: (_) => true),
        );
        final needBody = _decode(needResp);
        if (needBody['needCaptcha'] == true || needBody['isNeedCaptcha'] == true) {
          // 获取验证码 token（参考APK的 getCaptcha.do）
          final capResp = await _dio.get(
            'https://open.e.189.cn/api/logbox/oauth2/getCaptcha.do?captchaToken=',
            options: Options(headers: headers, validateStatus: (_) => true),
          );
          final capBody = _decode(capResp);
          final token = capBody['captchaToken']?.toString() ?? '';
          if (token.isNotEmpty) {
            throw CaptchaRequiredException(token);
          }
        }
      }

      // 3. 提交登录（参考APK的 loginSubmit.do）
      final loginData = {
        'accountType': '1',
        'account': phone,
        'password': password,
        'validateCode': captchaCode ?? '',
        'captchaToken': captchaToken ?? '',
        'appId': appId,
        'returnUrl': returnUrl,
      };
      final loginResp = await _dio.post(
        'https://open.e.189.cn/api/logbox/oauth2/loginSubmit.do',
        data: loginData,
        options: Options(headers: headers, validateStatus: (_) => true),
      );
      final loginBody = _decode(loginResp);

      // 4. 处理登录结果
      if (loginBody['result'] == 0) {
        // 获取 SSO 会话
        final toUrl = loginBody['toUrl']?.toString() ?? '';
        final captchaTokenRet = loginBody['captchaToken']?.toString() ?? '';

        // 获取session（参考APK的 getSessionForPC.action）
        final sessionResp = await _dio.get(
          'https://api.cloud.189.cn/getSessionForPC.action',
          options: Options(headers: {
            ...headers,
            'Referer': 'https://cloud.189.cn/',
          }, validateStatus: (_) => true),
        );
        final sessionBody = _decode(sessionResp);
        final sessionKey = sessionBody['sessionKey']?.toString() ?? '';
        final sessionSecret = sessionBody['sessionSecret']?.toString() ?? '';

        // 获取accessToken（参考APK的 getAccessTokenBySsKey.action）
        final tokenResp = await _dio.get(
          'https://api.cloud.189.cn/open/oauth2/getAccessTokenBySsKey.action',
          queryParameters: {'ssKey': sessionKey},
          options: Options(headers: {
            ...headers,
            'Referer': 'https://cloud.189.cn/',
          }, validateStatus: (_) => true),
        );
        final tokenBody = _decode(tokenResp);
        final accessToken = tokenBody['accessToken']?.toString() ?? '';

        // 组装cookie
        final setCookies = loginResp.headers['set-cookie'] ?? [];
        final entries = <String, String>{};
        for (final raw in setCookies) {
          final seg = raw.split(';').first.trim();
          final eq = seg.indexOf('=');
          if (eq <= 0) continue;
          entries[seg.substring(0, eq).trim()] = seg.substring(eq + 1).trim();
        }
        // 如果没有cookie，用sessionKey构造
        final cookie = entries.isNotEmpty
            ? entries.entries.map((e) => '${e.key}=${e.value}').join('; ')
            : 'sessionKey=$sessionKey; sessionSecret=$sessionSecret';

        return {
          'cookie': cookie,
          'sessionKey': sessionKey,
          'sessionSecret': sessionSecret,
          'accessToken': accessToken,
        };
      }

      // 需要二次验证（短信验证码）
      if (loginBody['result'] == 8 || loginBody['result'] == 13) {
        throw CaptchaRequiredException('需要短信验证码');
      }

      final msg = loginBody['msg']?.toString() ?? '登录失败';
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

  // ═══════════════════════════════════════════════════════════════
  // 123云盘密码登录（参考APK的 Pan123LoginDebug）
  // 使用 user.123pan.cn 的 API
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> pan123PasswordLogin({
    required String username,
    required String password,
    String? captcha,
  }) async {
    final headers = {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent': _uaPc,
      'Referer': 'https://yun.123pan.com/',
      'Origin': 'https://yun.123pan.com',
      'Platform': 'web',
      'app-version': '3',
    };
    try {
      // 手机号: {"passport", "password", "remember"}；邮箱: {"mail", "password", "type":2}
      final isEmail = username.contains('@');
      final resp = await _dio.post(
        'https://login.123pan.com/api/user/sign_in',
        data: isEmail
            ? {'mail': username, 'password': password, 'type': 2}
            : {'passport': username, 'password': password, 'remember': true},
        options: Options(headers: headers, validateStatus: (_) => true),
      );
      final res = _decode(resp);
      final code = res['code']?.toInt() ?? -1;
      if (code != 200) {
        final msg = res['message']?.toString() ??
            res['msg']?.toString() ??
            '登录失败';
        if (msg.contains('验证码') ||
            msg.contains('captcha') ||
            code == 40001 ||
            code == 40002 ||
            code == 40003) {
          throw CaptchaRequiredException(msg);
        }
        throw Exception(msg);
      }
      final data = res['data'] is Map ? res['data'] as Map : res;
      final token = data['token']?.toString() ??
          data['accessToken']?.toString() ??
          '';
      if (token.isEmpty) {
        throw Exception('登录失败: 未获取到 token');
      }
      return {'token': token, 'cookie': 'token=$token'};
    } on CaptchaRequiredException {
      rethrow;
    } catch (e) {
      throw Exception('登录请求失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 网页登录地址
  // ═══════════════════════════════════════════════════════════════

  static String getLoginUrl(DriveType type) {
    switch (type) {
      case DriveType.quark:
        return 'https://pan.quark.cn/';
      case DriveType.ali:
        return 'https://www.alipan.com/sign/';
      case DriveType.baidu:
        return 'https://passport.baidu.com/v2/?login&tpl=netdisk&staticpage=https%3A%2F%2Fpan.baidu.com%2F';
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
      case DriveType.lanzou:
        return 'https://up.woozooo.com/mlogin.php';
    }
  }

  static Map<String, dynamic> _decode(Response<dynamic> resp) {
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
}

/// 需要验证码的异常
class CaptchaRequiredException implements Exception {
  final String message;
  CaptchaRequiredException(this.message);

  @override
  String toString() => message;
}