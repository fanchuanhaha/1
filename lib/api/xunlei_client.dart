import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import '../utils/types.dart';
import 'base_drive.dart';
import 'drive_type.dart';

/// 迅雷网盘异常
class XunleiException implements Exception {
  final int code;
  final String message;

  XunleiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 迅雷网盘客户端
class XunleiClient extends BaseDrive {
  // ---- API 端点 ----
  static const String _baseApi = 'https://api-pan.xunlei.com';
  static const String _fileList = '$_baseApi/drive/v1/files';
  static const String _fileInfo = '$_baseApi/drive/v1/about';
  static const String _batchDelete = '$_baseApi/drive/v1/files:batchDelete';
  static const String _batchGet = '$_baseApi/drive/v1/files:batchGet';
  static const String _batchMove = '$_baseApi/drive/v1/files:batchMove';
  static const String _resourceList = '$_baseApi/drive/v1/resource/list';
  static const String _shareApi = '$_baseApi/drive/v1/share';
  static const String _shareDetail = '$_baseApi/drive/v1/share/detail';
  static const String _shareRestore = '$_baseApi/drive/v1/share/restore';
  static const String _taskApi = '$_baseApi/drive/v1/tasks';
  static const String _rewardApi = 'https://api-shoulei-ssl.xunlei.com/activity/v1/reward';
  static const String _subtitleApi = 'https://api-shoulei-ssl.xunlei.com/oracle/subtitle';
  static const String _authSignin = 'https://xluser-ssl.xunlei.com/v1/auth/signin/token';
  static const String _authToken = 'https://xluser-ssl.xunlei.com/v1/auth/token';
  static const String _captchaInit = 'https://xluser-ssl.xunlei.com/v1/shield/captcha/init';
  static const String _smsLogin = 'https://xluser-ssl.xunlei.com/xluser.core.login/v3/login';
  static const String _smsSend = 'https://xluser-ssl.xunlei.com/xluser.core.login/v3/sendsms';
  static const String _smsCodeLogin = 'https://xluser-ssl.xunlei.com/xluser.core.login/v3/smslogin';
  static const String _findPwd = 'https://i.xunlei.com/xluser/validate/findpwd_acc.html';
  static const String _panHome = 'https://pan.xunlei.com';

  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// api-pan 盘接口专用 Android 客户端 UA（OpenList meta.go 默认值，版本 8.31.0.9726，
  /// 与 [_oauthClientId] / [_captchaClientVersion] 配套）。用浏览器 UA 会被识别为网页端，
  /// 进而要求 X-Session-Id/X-LA-UUID 等网页端专用头，导致 Android 会话列表失败。
  static const String _apiUserAgent =
      'ANDROID-com.xunlei.downloadprovider/8.31.0.9726 netWorkType/5G appid/40 '
      'deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 '
      'platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 (Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)';

  // ---- 短信验证码登录（Android 客户端协议，参考参考 APK / 迅雷.hiker） ----
  static const String _sdkAppId = '40';
  static const String _sdkAppName = 'ANDROID-com.xunlei.downloadprovider';
  static const String _sdkClientVersion = '8.03.0.9067';
  static const String _sdkVersion = '231500';
  static const String _sdkProtocolVersion = '301';
  static const String _sdkPlatformVersion = '10';
  static const String _sdkDeviceId = 'b71a923eb0e2239842599a3c016b4098';
  static const String _sdkDeviceSign =
      'div101.b71a923eb0e2239842599a3c016b4098612f6cf6d6e9fd1925845ec59285716c';
  static const String _sdkPeerId = 'c9b076a446517969dff638cd37fa9ff1';
  static const String _sdkDeviceName = 'Xiaomi_22021211Rc';
  static const String _sdkDeviceModel = '22021211RC';
  static const String _sdkOsVersion = '12';

  /// 短信接口专用 UA（迅雷按此识别为官方 Android 客户端）
  static const String _sdkUa =
      'ANDROID-com.xunlei.downloadprovider/$_sdkClientVersion netWorkType/2G '
      'appid/$_sdkAppId deviceName/$_sdkDeviceName deviceModel/$_sdkDeviceModel '
      'OSVersion/$_sdkOsVersion protocolVersion/$_sdkProtocolVersion '
      'platformVersion/$_sdkPlatformVersion sdkVersion/$_sdkVersion '
      'Oauth2Client/0.9 (Linux 4_19_157-perf-g604b910ced3e) (JAVA 0)';

  /// OAuth2 signin/token 用到的官方 client 标识（公共逆向资料公认可用）
  static const String _oauthClientId = 'Xp6vsxz_7IYVw2BB';
  static const String _oauthClientSecret = 'Xp6vsy4tN9toTVdMSpomVdXpRmES';

  // ---- BaseDrive ----
  @override
  DriveType get type => DriveType.xunlei;

  @override
  String get label => '迅雷网盘';

  @override
  bool get hasLogin => _accessToken.isNotEmpty;

  @override
  DriveUserInfo? get userInfo => _userInfo;

  @override
  String? get loginCookie => _accessToken.isNotEmpty ? 'Bearer $_accessToken' : ( _cookie.isEmpty ? null : _cookie);

  // ---- 内部状态 ----
  final Dio _dio;
  String _accessToken = '';
  String _refreshToken = '';
  String _userId = '';
  String _deviceId = '';
  String _cookie = '';
  String _captchaToken = '';

  /// 当前访问令牌所属的客户端 ID。
  /// 必须与 access_token 签发时一致：SMS/Android 登录=Android 客户端 Xp6vsxz_7IYVw2BB；
  /// 网页(Cookie)登录=Web 客户端。api-pan 接口通过 X-Client-Id 头校验，
  /// 与令牌不一致会返回 captcha_invalid/客户端不匹配。
  String _clientId = _oauthClientId;
  DriveUserInfo? _userInfo;

  // ---- 短信验证码流程上下文（sendsms 返回，smslogin 需要） ----
  String _smsCreditKey = '';
  String _smsDeviceId = '';
  String _smsToken = '';

  XunleiClient()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ));

  // ---- 内部请求工具 ----

  Map<String, dynamic> _buildHeaders({
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) {
    return <String, dynamic>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent': userAgent ?? defaultUserAgent,
      'Referer': _panHome,
      if (_accessToken.isNotEmpty) 'Authorization': 'Bearer $_accessToken',
      if (_deviceId.isNotEmpty) 'X-Device-Id': _deviceId,
      if (_cookie.isNotEmpty) 'Cookie': _cookie,
      ...?extraHeaders,
    };
  }

  Future<Response<dynamic>> _request(
    String method,
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
    bool retried = false,
  }) async {
    final headers = _buildHeaders(
      userAgent: userAgent,
      extraHeaders: extraHeaders,
    );
    // api-pan 盘接口要求携带账号/设备/会话上下文，缺省会触发「验证码无效/captcha_token is empty」。
    if (url.contains('api-pan.xunlei.com')) {
      headers['User-Agent'] = _apiUserAgent;
      headers['X-Request-Env'] = '{"client":"xunlei.com","version":"8.31.0.9726"}';
      headers['X-Client-Version'] = _captchaClientVersion;
      headers['Origin'] = 'https://pan.xunlei.com/';
      headers['X-Device-Id'] = _effectiveDeviceId();
      headers['X-Client-Id'] = _clientId;
      if (_userId.isNotEmpty) headers['User-Id'] = _userId;
      if (_captchaToken.isNotEmpty) headers['X-Captcha-Token'] = _captchaToken;
    }
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
    // access_token 过期（401）：用 refresh_token 静默续期后重试一次。
    // 避免「登录后 token 短期过期，后续文件加载全部失败」。
    if (resp.statusCode == 401 &&
        !retried &&
        _refreshToken.isNotEmpty) {
      AppLogger.I.w('xunlei', '收到 401，使用 refresh_token 自动续期');
      final ok = await _refreshByOAuth();
      if (ok) {
        return _request(method, url,
            params: params,
            data: data,
            userAgent: userAgent,
            extraHeaders: extraHeaders,
            retried: true);
      }
    }
    // 盘接口命中验证码（400 captcha_invalid / captcha_token is empty）：
    // 尝试走 captcha/init 获取验证码 token，成功后缓存并重试一次。
    if (resp.statusCode == 400 &&
        !retried &&
        url.contains('api-pan.xunlei.com')) {
      final bodyStr = resp.data?.toString() ?? '';
      if (bodyStr.contains('captcha') || bodyStr.contains('验证码')) {
        AppLogger.I.w('xunlei', '命中验证码，尝试获取 captcha_token');
        final ok = await _tryAcquireCaptcha();
        if (ok) {
          return _request(method, url,
              params: params,
              data: data,
              userAgent: userAgent,
              extraHeaders: extraHeaders,
              retried: true);
        }
      }
    }
    _mergeSetCookie(resp);
    AppLogger.I.http(
      'xunlei',
      method,
      url,
      status: resp.statusCode ?? -1,
      cred: _accessToken.isEmpty ? _cookie : _accessToken,
      body: resp.data,
    );
    return resp;
  }

  /// 用 refresh_token 走 OAuth2 刷新 access_token，成功返回 true。
  /// 接口：POST https://xluser-ssl.xunlei.com/v1/auth/token?client_id=...
  /// 返回扁平结构 {access_token, refresh_token, ...}。
  Future<bool> _refreshByOAuth() async {
    if (_refreshToken.isEmpty) return false;
    try {
      final resp = await _dio.request(
        '$_authToken?client_id=$_clientId',
        data: {
          'client_id': _clientId,
          if (_clientId == _oauthClientId) 'client_secret': _oauthClientSecret,
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        },
        options: Options(
          method: 'POST',
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            // 关键：refresh 走 /v1/auth/token，浏览器 UA 携带 client_secret 会被 403 拒绝
            // ([Danger] Do Not Save client_secret in browser)。改用官方 Android 客户端 UA。
            'User-Agent': _sdkUa,
            'Referer': _panHome,
            if (_userId.isNotEmpty) 'User-Id': _userId,
          },
          validateStatus: (_) => true,
        ),
      );
      AppLogger.I.http(
        'xunlei',
        'POST',
        '$_authToken?client_id=xxx',
        status: resp.statusCode ?? -1,
        cred: _refreshToken,
        body: resp.data,
      );
      final body = _parseBody(resp);
      final token = body['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        AppLogger.I.e('xunlei',
            'token 续期失败：${body['error'] ?? body['error_description']}');
        return false;
      }
      final refresh = body['refresh_token']?.toString() ?? _refreshToken;
      setToken(token,
          refreshToken: refresh,
          userId: _userId,
          deviceId: _deviceId,
          cookie: _cookie);
      AppLogger.I.i('xunlei', 'token 续期成功 accessTokenLen=${token.length}');
      // 续期拿到新凭证后，通知上层立即持久化，保证下次启动可用最新 refresh_token
      unawaited(onTokenRefreshed?.call());
      return true;
    } catch (e) {
      AppLogger.I.e('xunlei', 'token 续期异常: $e');
      return false;
    }
  }

  /// captcha 签名使用的客户端参数（OpenList meta.go 默认值，与 Android 客户端 [_oauthClientId]
  /// 配对）：版本 8.31.0.9726、包名 com.xunlei.downloadprovider。签名与账号令牌必须同属
  /// 一个客户端，否则 captcha/init 会返回 invalid captcha_sign → 文件列表 400。
  static const String _captchaClientVersion = '8.31.0.9726';
  static const String _captchaPackageName = 'com.xunlei.downloadprovider';

  /// 磁盘接口命中验证码时，调用 captcha/init 获取 captcha_token。
  /// init 返回 capture_token 时缓存并复用；失败返回 false，由调用方把错误抛给用户。
  Future<bool> _tryAcquireCaptcha() async {
    // 签名盐值与客户端(包名/版本)绑定：仅 Android 客户端会话的签名算法可用。
    // Web 会话的 captcha 签名参数未知，强行用 Android 签名只会得到非法 token，直接返回 false。
    if (_clientId != _oauthClientId) {
      AppLogger.I.w('xunlei',
          '当前会话客户端 $_clientId 非 Android 客户端，跳过 captcha 自动获取');
      return false;
    }
    if (_captchaToken.isNotEmpty) return true;
    try {
      final ts = '${DateTime.now().millisecondsSinceEpoch}';
      final deviceId = _effectiveDeviceId();
      final sign = _captchaSign(
        clientId: _oauthClientId,
        version: _captchaClientVersion,
        host: _captchaPackageName,
        deviceId: deviceId,
        ts: ts,
      );
      AppLogger.I.i('xunlei',
          'captcha/init 请求 deviceId=$deviceId sign=$sign');
      final resp = await _dio.request(
        _captchaInit,
        data: {
          'action': 'get:/drive/v1/files',
          'client_id': _oauthClientId,
          'device_id': deviceId,
          'captcha_token': '',
          'redirect_uri': 'xlaccsdk01://xunlei.com/callback?state=harbor',
          'meta': {
            'captcha_sign': sign,
            'client_version': _captchaClientVersion,
            'package_name': _captchaPackageName,
            'timestamp': ts,
            'user_id': _userId,
          },
        },
        options: Options(
          method: 'POST',
          headers: {
            'Accept': 'application/json, text/plain, */*',
            'Content-Type': 'application/json',
            'User-Agent': defaultUserAgent,
            'Referer': _panHome,
            'X-Device-Id': deviceId,
            if (_userId.isNotEmpty) 'User-Id': _userId,
          },
          validateStatus: (_) => true,
        ),
      );
      final body = _parseBody(resp);
      // LinkSwift 的响应是扁平结构 {captcha_token, expires_in, ...}，
      // 某些实现会包一层 data，两种情况都兼容。
      dynamic t = body['captcha_token'];
      if (t == null) {
        final data = body['data'];
        if (data is Map) {
          t = data['captcha_token'] ?? data['token'];
        }
      }
      final got = (t == null || t.toString().isEmpty) ? '' : t.toString();
      if (got.isEmpty) {
        AppLogger.I.w('xunlei',
            'captcha/init 未直接返回 token（需交互验证），body=${resp.data}');
        return false;
      }
      _captchaToken = got;
      AppLogger.I.i('xunlei', 'captcha_token 获取成功 len=${got.length}');
      return true;
    } catch (e) {
      AppLogger.I.e('xunlei', 'captcha/init 异常: $e');
      return false;
    }
  }

  String _md5String(String input) {
    try {
      final bytes = Uint8List.fromList(utf8.encode(input));
      final digest = md5.convert(bytes);
      return digest.toString();
    } catch (_) {
      return '';
    }
  }

  /// 当前生效的设备 ID：优先用登录会话保存的，否则用 SDK 内置的设备指纹。
  /// 注意：smslogin 返回的 deviceid 是 devicesign（形如 div101.<32位hex>...），
  /// 而 captcha/init 签名与 api-pan 的 x-device-id 需要的是纯 32 位 hex device_id。
  /// 这里统一清洗：带 div101. 前缀时截取前 32 位 hex，避免 invalid captcha_sign。
  String _effectiveDeviceId() {
    var id = _deviceId.isNotEmpty ? _deviceId : _sdkDeviceId;
    if (id.startsWith('div101.')) {
      final rest = id.substring('div101.'.length);
      if (rest.length >= 32) id = rest.substring(0, 32);
    }
    return id;
  }

  /// 生成迅雷验证码签名。
  /// 算法（OpenList Thunder meta.go 默认值，公共逆向资料一致）：
  ///   str = ClientId + ClientVersion + PackageName + DeviceId + Timestamp
  ///   对 10 个盐值依次执行 str = md5(str + salt)
  ///   CaptchaSign = "1." + str
  String _captchaSign({
    required String clientId,
    required String version,
    required String host,
    required String deviceId,
    required String ts,
  }) {
    var str = '$clientId$version$host$deviceId$ts';
    // 10 层哈希盐值（OpenList meta.go Algorithms 默认值，与 Android 客户端参数配套）
    const salts = <String>[
      '9uJNVj/wLmdwKrJaVj/omlQ',
      'Oz64Lp0GigmChHMf/6TNfxx7O9PyopcczMsnf',
      'Eb+L7Ce+Ej48u',
      'jKY0',
      'ASr0zCl6v8W4aidjPK5KHd1Lq3t+vBFf41dqv5+fnOd',
      'wQlozdg6r1qxh0eRmt3QgNXOvSZO6q/GXK',
      'gmirk+ciAvIgA/cxUUCema47jr/YToixTT+Q6O',
      '5IiCoM9B1/788ntB',
      'P07JH0h6qoM6TSUAK2aL9T5s2QBVeY9JWvalf',
      '+oK0AN',
    ];
    for (final salt in salts) {
      str = _md5String(str + salt);
    }
    return '1.$str';
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
    final errorCode = toInt(body['error_code'], fallback: toInt(body['code'], fallback: 0));
    if (errorCode != 0) {
      final msg = body['error_message']?.toString() ??
          body['message']?.toString() ??
          '请求失败';
      throw XunleiException(errorCode, msg);
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
    return _check(_parseBody(resp));
  }

  Future<dynamic> _post(
    String url, {
    Map<String, dynamic>? params,
    Object? data,
    String? userAgent,
    Map<String, dynamic>? extraHeaders,
  }) async {
    final resp = await _request('POST', url,
        params: params, data: data, userAgent: userAgent, extraHeaders: extraHeaders);
    return _check(_parseBody(resp));
  }

  // ---- 公开的 setter ----

  /// 设置访问令牌（由上层调用方注入持久化的凭证）
  void setToken(String accessToken, {String refreshToken = '', String userId = '', String deviceId = '', String cookie = '', String clientId = ''}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _userId = userId;
    _deviceId = deviceId;
    _cookie = cookie;
    if (clientId.isNotEmpty) _clientId = clientId;
  }

  /// 获取当前访问令牌
  String get accessToken => _accessToken;

  /// 获取当前设备 ID
  String get deviceId => _deviceId;

  /// access_token 自动续期成功后的回调（由上层注入，用于把新凭证重新持久化，
  /// 避免 refresh_token 轮换后下次启动仍用旧的失效 refresh_token）。
  Future<void> Function()? onTokenRefreshed;

  /// 返回可持久化凭证（JSON，含 refresh_token），供 drive_manager 保存到本地。
  /// 重启后 [restoreSession] 可据此恢复 refresh_token 并在过期时自动续期。
  String? persistableCredential() {
    if (_accessToken.isEmpty && _refreshToken.isEmpty && _cookie.isEmpty) {
      return null;
    }
    return jsonEncode({
      'access_token': _accessToken,
      'refresh_token': _refreshToken,
      'user_id': _userId,
      'device_id': _deviceId,
      'cookie': _cookie,
      'client_id': _clientId,
    });
  }

  // ---- BaseDrive 接口实现 ----

  @override
  Future<void> init() async {
    // 从持久化存储加载 token（由上层调用方提供）
  }

  @override
  void restoreSession(String credential) {
    final v = (credential ?? '').trim();
    if (v.isEmpty) return;
    // 兼容 JSON 格式与 Bearer <token> 两种持久化值
    if (v.startsWith('{')) {
      try {
        final m = jsonDecode(v) as Map<String, dynamic>;
        setToken(
          m['access_token']?.toString() ?? '',
          refreshToken: m['refresh_token']?.toString() ?? '',
          userId: m['user_id']?.toString() ?? '',
          deviceId: m['device_id']?.toString() ?? '',
          cookie: m['cookie']?.toString() ?? '',
          clientId: m['client_id']?.toString() ?? '',
        );
        return;
      } catch (_) {}
    }
    if (v.startsWith('Bearer ')) {
      _accessToken = v.substring(7).trim();
    } else {
      _cookie = v;
    }
  }

  @override
  Future<String?> login(dynamic credential) async {
    // 兼容直接传入 JSON 字符串凭证（网页登录返回的 {access_token, refresh_token, client_id, ...} 字符串）
    if (credential is String && credential.trimLeft().startsWith('{')) {
      try {
        credential = jsonDecode(credential);
      } catch (_) {}
    }
    // credential 支持多种登录方式：
    //   {type: 'token', access_token, refresh_token, user_id, device_id}
    //   {type: 'password', username, password, captcha_token}
    //   {type: 'sms', phone, sms_code}
    if (credential is Map) {
      final type = credential['type']?.toString() ?? 'token';
      if (type == 'token') {
        final token = credential['access_token']?.toString() ?? '';
        if (token.isNotEmpty) {
          setToken(
            token,
            refreshToken: credential['refresh_token']?.toString() ?? '',
            userId: credential['user_id']?.toString() ?? '',
            deviceId: credential['device_id']?.toString() ?? '',
            cookie: credential['cookie']?.toString() ?? '',
            clientId: credential['client_id']?.toString() ?? '',
          );
          return null;
        }
      } else if (type == 'password') {
        final username = credential['username']?.toString() ?? '';
        final password = credential['password']?.toString() ?? '';
        final captchaToken = credential['captcha_token']?.toString() ?? '';
        if (username.isNotEmpty && password.isNotEmpty) {
          try {
            final data = await _post(
              _authSignin,
              data: {
                'client_id': 'XLP_ANDROID',
                'client_secret': 'XLP_ANDROID_SECRET',
                'username': username,
                'password': password,
                'captcha_token': captchaToken,
              },
            );
            final token = data['access_token']?.toString() ?? '';
            if (token.isNotEmpty) {
              setToken(
                token,
                refreshToken: data['refresh_token']?.toString() ?? '',
                userId: data['user_id']?.toString() ?? '',
                deviceId: data['device_id']?.toString() ?? '',
              );
              return null;
            }
            return '登录失败：未获取到访问令牌';
          } on XunleiException catch (e) {
            return '登录失败(${e.code}): ${e.message}';
          } catch (e) {
            return '登录失败: $e';
          }
        }
        return '用户名或密码为空';
      } else if (type == 'sms') {
        final phone = credential['phone']?.toString() ?? '';
        final smsCode = credential['sms_code']?.toString() ?? '';
        if (phone.isNotEmpty && smsCode.isNotEmpty) {
          try {
            // 1) smslogin：用 sendsms 阶段的服务端上下文换 sessionID
            final loginData = await _smsCodeLoginFlow(phone, smsCode);
            final sessionId = loginData['sessionID']?.toString() ?? '';
            final userId = loginData['userID']?.toString() ?? '';
            AppLogger.I.i('xunlei_login',
                'smslogin 响应 sessionIDLen=${sessionId.length} userIDLen=${userId.length} '
                'creditkeyLen=${_smsCreditKey.length} deviceidLen=${_smsDeviceId.length}');
            if (sessionId.isEmpty) {
              final errno = loginData['errorCode']?.toString() ?? '';
              final desc = loginData['errorDesc']?.toString() ?? '未获取到会话ID';
              AppLogger.I.e('xunlei_login', 'smslogin 未返回 sessionID: code=$errno desc=$desc');
              return '短信登录失败($errno): $desc';
            }
            // 2) signin：用 sessionID 走 OAuth2 换取 access_token / refresh_token
            // 注意：该接口返回扁平结构 {access_token,...,refresh_token}（无 data 字段），
            // 必须用 _request+_parseBody 读取完整 body，不能走 _post（会取 .data 得到 null）。
            final signResp = await _request(
              'POST',
              '$_authSignin?client_id=$_oauthClientId',
              data: {
                'client_id': _oauthClientId,
                'client_secret': _oauthClientSecret,
                'provider': 'access_end_point_token',
                'signin_token': sessionId,
              },
            );
            final signBody = _parseBody(signResp);
            final token = signBody['access_token']?.toString() ?? '';
            final refresh = signBody['refresh_token']?.toString() ?? '';
            AppLogger.I.i('xunlei_login',
                'signin/token 响应 accessTokenLen=${token.length} refreshTokenLen=${refresh.length}');
            if (refresh.isNotEmpty || token.isNotEmpty) {
              setToken(
                token,
                refreshToken: refresh,
                userId: userId.isNotEmpty
                    ? userId
                    : (signBody['user_id']?.toString() ?? ''),
                deviceId: (_smsDeviceId.isNotEmpty ? _smsDeviceId : _deviceId),
              );
              // 若 signin 只给了 refresh_token，立即兑换一次 access_token
              _smsCreditKey = '';
              _smsToken = '';
              return null;
            }
            return '短信登录失败：未获取到令牌(${signBody['error']?.toString() ?? ''} ${signBody['error_description']?.toString() ?? ''})';
          } on XunleiException catch (e) {
            return '短信登录失败(${e.code}): ${e.message}';
          } catch (e) {
            return '短信登录失败: $e';
          }
        }
        return '手机号或验证码为空';
      }
    }
    return '未提供有效的登录凭据';
  }

  @override
  Future<void> logout() async {
    _accessToken = '';
    _refreshToken = '';
    _userId = '';
    _deviceId = '';
    _cookie = '';
    _userInfo = null;
  }

  @override
  Future<void> refreshUser() async {
    if (_accessToken.isEmpty) return;
    try {
      final data = await _get(_fileInfo);
      final user = data['user'];
      if (user is Map) {
        final m = user.cast<String, dynamic>();
        _userInfo = DriveUserInfo(
          nickname: m['nickname']?.toString() ?? '',
          avatar: m['avatar']?.toString() ?? '',
          userId: m['user_id']?.toString() ?? _userId,
        );
      }
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取用户信息失败: $e');
    }
  }

  @override
  Future<List<DriveFile>> listFiles(String pdirFid,
      {int page = 1, int size = 100}) async {
    try {
      // OpenList(Thunder) 真实请求：
      //   GET /drive/v1/files?space=&__type=drive&refresh=true&__sync=true
      //      &parent_id=...&page_token=&with_audit=true&limit=100
      //      &filters={"phase":{"eq":"PHASE_TYPE_COMPLETE"},"trashed":{"eq":false}}
      // 顶层/子目录 parent_id 直接传 id，根目录传 "0"。
      final data = await _get(
        _fileList,
        params: {
          'parent_id': pdirFid,
          'page_token': '',
          'limit': size,
          // 主云盘 space 传空串即可（OpenList Android 驱动即用空 space+parent_id 成功列出）。
          // 注意：不要传 "0"——服务端会按 space_name_invalid 拒绝。
          'space': '',
          '__type': 'drive',
          'refresh': 'true',
          '__sync': 'true',
          'with_audit': 'true',
          'filters':
              '{"phase":{"eq":"PHASE_TYPE_COMPLETE"},"trashed":{"eq":false}}',
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['updated_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取文件列表失败: $e');
    }
  }

  @override
  Future<List<DriveFile>> searchFiles(String keyword,
      {int page = 1, int size = 50}) async {
    try {
      final data = await _get(
        '$_fileList:search',
        params: {
          'query': keyword,
          'page': page,
          'page_size': size,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['updated_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '搜索文件失败: $e');
    }
  }

  @override
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids) async {
    try {
      final data = await _post(
        _batchGet,
        data: {
          'ids': fids,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        String url = '';
        // 尝试从不同字段获取下载链接
        final downloadUrl = m['download_url'];
        if (downloadUrl != null) {
          url = downloadUrl.toString();
        }
        final mediaInfo = m['media_info'];
        if (mediaInfo is Map) {
          final mediaUrl = mediaInfo['download_url']?.toString() ?? '';
          if (mediaUrl.isNotEmpty) url = mediaUrl;
        }
        return DriveDownloadInfo(
          url: url,
          fileName: m['name']?.toString() ?? '',
          size: toInt(m['size']),
          fid: m['id']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取下载链接失败: $e');
    }
  }

  @override
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    var pwdId = '';
    var passcode = '';
    final uri = Uri.tryParse(url.trim());
    if (uri != null) {
      // 迅雷分享链接: https://pan.xunlei.com/s/xxxx
      final path = uri.path;
      final idx = path.lastIndexOf('/s/');
      if (idx >= 0) {
        pwdId = path.substring(idx + 3);
        final slash = pwdId.indexOf('/');
        if (slash > 0) pwdId = pwdId.substring(0, slash);
      }
      passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['passcode'] ?? '';
    }
    return (pwdId: pwdId, passcode: passcode);
  }

  @override
  Future<DriveShareSession> getShareToken(String pwdId, String passcode) async {
    // api-pan 的 share 解析普遍要求携带 X-Captcha-Token；若尚未持有则先主动获取，
    // 避免 share:verify 因 captcha_token 为空直接失败（拿不到则安全空转，仍走懒加载重试）。
    if (_captchaToken.isEmpty) {
      try {
        await _tryAcquireCaptcha();
      } catch (_) {}
    }
    try {
      final data = await _post(
        '$_shareApi:verify',
        data: {
          'share_id': pwdId,
          'passcode': passcode,
        },
      );
      final stoken = data['share_token']?.toString() ?? '';
      final shareId = data['share_id']?.toString() ?? pwdId;
      if (stoken.isEmpty) {
        throw XunleiException(-1, '分享链接已失效或提取码错误');
      }
      return DriveShareSession(
        shareId: shareId,
        pwdId: pwdId,
        passcode: passcode,
        stoken: stoken,
      );
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取分享 token 失败: $e');
    }
  }

  @override
  Future<List<DriveShareFile>> listShare(DriveShareSession session, String pdirFid,
      {int page = 1, int size = 50}) async {
    try {
      final data = await _get(
        _shareDetail,
        params: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'parent_id': pdirFid,
          'page': page,
          'page_size': size,
          'thumbnail_size': 'SIZE_LARGE',
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveShareFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          shareFidToken: m['share_fid_token']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取分享文件列表失败: $e');
    }
  }

  @override
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(
      DriveShareSession session, List<String> fidList) async {
    try {
      // 迅雷分享下载需要先获取文件详情，再提取下载链接
      final data = await _post(
        _shareDetail,
        data: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'file_ids': fidList,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        String url = '';
        final downloadUrl = m['download_url'];
        if (downloadUrl != null) {
          url = downloadUrl.toString();
        }
        final mediaInfo = m['media_info'];
        if (mediaInfo is Map) {
          final mediaUrl = mediaInfo['download_url']?.toString() ?? '';
          if (mediaUrl.isNotEmpty) url = mediaUrl;
        }
        return DriveDownloadInfo(
          url: url,
          fileName: m['name']?.toString() ?? '',
          size: toInt(m['size']),
          fid: m['id']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取分享下载链接失败: $e');
    }
  }

  @override
  Future<void> saveShare(
      DriveShareSession session, List<DriveShareFile> files, String toPdirFid) async {
    try {
      await _post(
        _shareRestore,
        data: {
          'share_id': session.pwdId,
          'share_token': session.stoken,
          'file_ids': files.map((f) => f.fid).toList(),
          'parent_id': toPdirFid,
        },
      );
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '转存分享文件失败: $e');
    }
  }

  // ---- 迅雷网盘专属方法 ----

  /// 批量删除文件（软删除到回收站）
  Future<void> batchDelete(List<String> fids) async {
    try {
      await _post(
        _batchDelete,
        data: {
          'ids': fids,
        },
      );
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '批量删除失败: $e');
    }
  }

  /// 批量获取文件信息
  Future<List<DriveFile>> batchGet(List<String> fids) async {
    try {
      final data = await _post(
        _batchGet,
        data: {
          'ids': fids,
        },
      );
      final list = data['files'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['updated_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '批量获取文件信息失败: $e');
    }
  }

  /// 批量移动文件到指定目录
  Future<void> batchMove(List<String> fids, String toPdirFid) async {
    try {
      await _post(
        _batchMove,
        data: {
          'ids': fids,
          'parent_id': toPdirFid,
        },
      );
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '批量移动文件失败: $e');
    }
  }

  /// 获取资源列表（迅雷特有资源聚合接口）
  Future<List<DriveFile>> listResource({int page = 1, int size = 100}) async {
    try {
      final data = await _get(
        _resourceList,
        params: {
          'page': page,
          'page_size': size,
        },
      );
      final list = data['resources'];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) {
        final m = e.cast<String, dynamic>();
        final kind = m['kind']?.toString() ?? '';
        return DriveFile(
          fid: m['id']?.toString() ?? '',
          fileName: m['name']?.toString() ?? '',
          fileType: kind,
          isDir: kind == 'drive#folder',
          size: toInt(m['size']),
          pdirFid: m['parent_id']?.toString() ?? '',
          fileExt: m['ext']?.toString() ?? '',
          updatedAt: toInt(m['updated_at']),
          thumbnail: m['thumbnail']?.toString() ?? '',
          previewUrl: m['preview_url']?.toString() ?? '',
        );
      }).toList();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取资源列表失败: $e');
    }
  }

  /// 获取任务列表（离线下载/转存任务）
  Future<List<Map<String, dynamic>>> listTasks({int page = 1, int size = 20}) async {
    try {
      final data = await _get(
        _taskApi,
        params: {
          'page': page,
          'page_size': size,
        },
      );
      final list = data['tasks'];
      if (list is! List) return [];
      return list.cast<Map<String, dynamic>>();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取任务列表失败: $e');
    }
  }

  /// 创建离线下载任务
  Future<String> createTask(String url, {String? name, String? parentId}) async {
    try {
      final data = await _post(
        _taskApi,
        data: {
          'url': url,
          if (name != null) 'name': name,
          if (parentId != null) 'parent_id': parentId,
        },
      );
      return data['task_id']?.toString() ?? '';
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '创建任务失败: $e');
    }
  }

  /// 获取字幕信息
  Future<List<Map<String, dynamic>>> getSubtitles(String fileId, {String? lang}) async {
    try {
      final data = await _get(
        _subtitleApi,
        params: {
          'file_id': fileId,
          if (lang != null) 'language': lang,
        },
      );
      final list = data['subtitles'];
      if (list is! List) return [];
      return list.cast<Map<String, dynamic>>();
    } on XunleiException {
      rethrow;
    } catch (e) {
      throw XunleiException(-1, '获取字幕信息失败: $e');
    }
  }

  /// 发送短信验证码（Android 客户端协议）
  Future<void> sendSmsCode(String phone) async {
    AppLogger.I.i('xunlei_login', 'sendsms 发起 phone=$phone 设备signLen=${_sdkDeviceSign.length}');
    final resp = await _request(
      'POST',
      _smsSend,
      userAgent: _sdkUa,
      extraHeaders: {
        'x-device-id': _sdkDeviceId,
        'Content-Type': 'application/json;charset=utf-8',
      },
      data: _smsBaseBody(phone, creditKey: _smsCreditKey),
    );
    // 兼容 resp.data 为 Map 或原始 JSON 字符串的两种情况
    final data = _parseBody(resp);
    final code = data['errorCode']?.toString() ?? '';
    if (code.isNotEmpty && code != '0') {
      // 服务端明确拒绝：如 errorCode=13 身份失效 / 需图形验证，在此抛错由 UI 展示
      final desc = data['errorDesc']?.toString() ?? '';
      final verify = data['verifyType']?.toString() ?? '';
      AppLogger.I.e('xunlei_login',
          'sendsms 被拒绝 code=$code desc=$desc verifyType=$verify error=${data['error']}');
      throw XunleiException(
        int.tryParse(code) ?? -1,
        desc.isNotEmpty ? desc : '发送短信验证码失败',
      );
    }
    // 保存服务端上下文，供 smslogin 使用
    _smsCreditKey = data['creditkey']?.toString() ?? _smsCreditKey;
    _smsDeviceId = data['deviceid']?.toString() ?? _smsDeviceId;
    _smsToken = data['token']?.toString() ?? '';
    AppLogger.I.i('xunlei_login',
        'sendsms 成功 creditkeyLen=${_smsCreditKey.length} deviceidLen=${_smsDeviceId.length} '
        'tokenLen=${_smsToken.length}（服务端已受理，短信已发出）');
  }

  /// 构造 Android 客户端协议统一请求体（sendsms / smslogin 共用）
  Map<String, dynamic> _smsBaseBody(String phone, {String creditKey = ''}) => {
        'protocolVersion': _sdkProtocolVersion,
        'sequenceNo':
            '1000${DateTime.now().millisecondsSinceEpoch % 1000000}',
        'platformVersion': _sdkPlatformVersion,
        'isCompressed': '0',
        'appid': _sdkAppId,
        'clientVersion': _sdkClientVersion,
        'peerID': _sdkPeerId,
        'appName': _sdkAppName,
        'sdkVersion': _sdkVersion,
        'devicesign': _smsDeviceId.isNotEmpty ? _smsDeviceId : _sdkDeviceSign,
        'netWorkType': '2G',
        'providerName': 'NONE',
        'deviceModel': _sdkDeviceModel,
        'deviceName': _sdkDeviceName,
        'OSVersion': _sdkOsVersion,
        'creditkey': creditKey,
        'hl': 'zh-CN',
        'mobile': phone,
        'register': '0',
      };

  /// 短信验证码登录（Android 客户端协议）：返回服务端 JSON（含 sessionID/userID）
  Future<Map<String, dynamic>> _smsCodeLoginFlow(String phone, String smsCode) async {
    final body = _smsBaseBody(phone, creditKey: _smsCreditKey)
      ..['smsCode'] = smsCode
      ..['token'] = _smsToken;
    final resp = await _request(
      'POST',
      _smsCodeLogin,
      userAgent: _sdkUa,
      extraHeaders: {
        'x-device-id': _sdkDeviceId,
        'Content-Type': 'application/json;charset=utf-8',
      },
      data: body,
    );
    final data = _parseBody(resp);
    final code = data['errorCode']?.toString() ?? '0';
    if (code.isNotEmpty && code != '0') {
      throw XunleiException(
        int.tryParse(code) ?? -1,
        data['errorDesc']?.toString() ?? '短信验证码不正确',
      );
    }
    return data;
  }

  @override
  void dispose() {
    _dio.close();
  }
}