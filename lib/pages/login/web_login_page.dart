import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/drive_type.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 网页登录页面：使用 WebView 加载网盘登录页
/// 用户登录后点击「保存」按钮手动保存 Cookie/Token（参考 APK 样式）
class WebLoginPage extends StatefulWidget {
  final DriveType driveType;
  final String loginUrl;

  const WebLoginPage({
    super.key,
    required this.driveType,
    required this.loginUrl,
  });

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String _currentCookie = '';

  /// 阿里云盘 OAuth 授权回调里捕获到的 code（`redirect_uri?code=xxx`）。
  /// 阿里云盘走的是 OAuth code 流程，cookie/localStorage 拿不到 refresh_token，
  /// 必须捕获回跳地址里的 code，再交给 login（换取 refresh_token）。
  String _aliOauthCode = '';

  /// 各网盘用于捕获 token 的 localStorage key
  static const _tokenKeys = {
    DriveType.ali: [
      'aliyundrive_token',
      'alipan_token',
      'accountToken',
      'account_token',
      'token',
      'loginToken',
      'login_token',
      'auth_token',
    ],
    DriveType.quark: [
      'token',
      'loginToken',
      'login_token',
      'auth_token',
    ],
    DriveType.baidu: ['bduss', 'token', 'loginToken'],
    DriveType.pikpak: ['token', 'session', 'auth_token'],
    DriveType.uc: ['token', 'loginToken', 'auth_token'],
    DriveType.tianyi: ['token', 'session', 'loginToken'],
    DriveType.xunlei: [
      'token', 'session', 'loginToken', 'accessToken', 'access_token',
      'auth_token', 'xl_token', 'xl_access_token', 'app_token', 'APP_TOKEN',
    ],
    DriveType.pan123: ['token', 'loginToken', 'auth_token'],
  };

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    // 蓝奏云 = H5 移动端登录页，需用现代移动端 UA 才能正常渲染并完成「我是人」滑动验证；
    // 阿里云/其它网盘 = 电脑端站点，必须用桌面 UA（手机 UA 会不显示登录表单）。
    final isLanzou = widget.driveType == DriveType.lanzou;
    // 桌面 UA：电脑端网盘站点必须用它（手机 UA 不会显示登录表单）
    final desktopUA =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(isLanzou
          ? 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230805.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
          : desktopUA)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => _checkAliCallback(change.url),
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() => _loading = true);
            // 页面加载早期先注入一次（可能因 document 未就绪而失败，onPageFinished 会再补一次）
            if (!isLanzou) {
              _controller.runJavaScript(_desktopInjectScript(desktopUA));
            }
          },
          onPageFinished: (_) {
            if (!mounted) return;
            // 页面就绪后再强制注入桌面布局与桌面 UA，确保迅雷这类电脑站
            // 按桌面版渲染（onPageStarted 时 document.body 可能为 null 会让上一次注入抛错中断）。
            if (!isLanzou) {
              _controller.runJavaScript(_desktopInjectScript(desktopUA));
            }
            setState(() => _loading = false);
            _refreshCookie();
            // 登录成功跳转后 Cookie 可能稍后才落地，延迟再读一次
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) _refreshCookie();
            });
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.loginUrl));
  }

  /// 构造注入脚本：把非蓝奏云网盘的 WebView 渲染成桌面版
  /// （固定 980 宽布局 + 覆盖 navigator.userAgent 为桌面 UA），全部 null 安全。
  String _desktopInjectScript(String ua) => '''
(function() {
  var vp = document.querySelector('meta[name="viewport"]');
  var w = 980;
  if (!vp) {
    vp = document.createElement('meta');
    vp.name = 'viewport';
    if (document.head) document.head.appendChild(vp);
  }
  if (vp) vp.content = 'width=' + w + ', initial-scale=0.55, minimum-scale=0.25, maximum-scale=3, user-scalable=yes';
  if (document.documentElement) document.documentElement.style.minWidth = w + 'px';
  if (document.body) document.body.style.minWidth = w + 'px';
  try {
    Object.defineProperty(navigator, 'userAgent', {
      get: function() { return '$ua'; },
      configurable: true
    });
  } catch (e) {}
})();
''';

  /// 捕获阿里云盘 OAuth 授权回调的 code（仅阿里云盘使用，走 redirect_uri?code=xxx）。
  void _checkAliCallback(String? url) {
    if (widget.driveType != DriveType.ali) return;
    if (url == null || _aliOauthCode.isNotEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    String? code = uri.queryParameters['code'];
    if (code == null && uri.fragment.isNotEmpty) {
      try {
        code = Uri.splitQueryString(uri.fragment)['code'];
      } catch (_) {}
    }
    final host = uri.host;
    if (!host.contains('aliyundrive.com') &&
        !host.contains('aliyundrive.cn') &&
        !host.contains('alipan.com')) {
      return;
    }
    if (code == null || code.trim().isEmpty) return;
    _aliOauthCode = code.trim();
    debugPrint('[WebLogin] 捕获阿里云盘 OAuth code');
  }

  Future<void> _refreshCookie() async {
    debugPrint('[WebLogin] _refreshCookie 开始, type=${widget.driveType}');
    // 1) 优先使用 CookieManager，能读到 HttpOnly cookie
    try {
      // 登录过程中可能有跳转（如 passport.baidu.com → pan.baidu.com），
      // 不同子域（passport/pan/yun）会分别存放关键 cookie（如百度 BDUSS 在 passport.baidu.com，
      // 蓝奏云 ylogin 在 up.woozooo.com）。必须把候选子域的 cookie 全部合并，
      // 而不是拿到第一个非空就返回，否则会漏掉跳转后子域上的关键会话 cookie。
      final allParts = <String>{};
      final candidateHosts = <String>{Uri.parse(widget.loginUrl).host};
      try {
        final cur = await _controller.currentUrl();
        debugPrint('[WebLogin] 当前URL: $cur');
        if (cur != null && cur.isNotEmpty) {
          final u = Uri.parse(cur);
          if (u.host.isNotEmpty) candidateHosts.add(u.host);
        }
      } catch (e) {
        debugPrint('[WebLogin] 获取当前URL失败: $e');
      }
      // 对百度额外补上常见会话子域及父域，确保 BDUSS/STOKEN 被读到
      if (widget.driveType == DriveType.baidu) {
        candidateHosts.addAll({
          'passport.baidu.com',
          'pan.baidu.com',
          'yun.baidu.com',
          '.baidu.com',
        });
      }
      debugPrint('[WebLogin] 候选域名: $candidateHosts');
      for (final host in candidateHosts) {
        try {
          final uri = host.startsWith('.')
              ? Uri.parse('https://pan.baidu.com/')
              : Uri.parse('https://$host/');
          final cookies = await WebViewCookieManager().getCookies(domain: uri);
          debugPrint('[WebLogin] 域名 $host -> 找到 ${cookies.length} 个 cookie');
          for (final c in cookies) {
            debugPrint('[WebLogin]   cookie: ${c.name}=${c.value.length > 30 ? "${c.value.substring(0, 30)}..." : c.value}');
            if (c.name.isNotEmpty && c.value.isNotEmpty) {
              allParts.add('${c.name}=${c.value}');
            }
          }
        } catch (e) {
          debugPrint('[WebLogin] 读取域名 $host cookie 失败: $e');
        }
      }
      if (allParts.isNotEmpty) {
        _currentCookie = allParts.join('; ');
        debugPrint('[WebLogin] 合并后cookie长度=${_currentCookie.length}, 含BDUSS=${_currentCookie.contains("BDUSS")}');
        return;
      }
      debugPrint('[WebLogin] CookieManager 未找到任何 cookie');
    } catch (e) {
      debugPrint('[WebLogin] CookieManager 整体失败: $e');
    }
    // 2) 兜底：document.cookie（读不到 HttpOnly）
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieStr = cookies.toString();
      debugPrint('[WebLogin] document.cookie 兜底: ${cookieStr.length > 100 ? "${cookieStr.substring(0, 100)}..." : cookieStr}');
      if (cookieStr.isNotEmpty && cookieStr != '""' && cookieStr != "''") {
        _currentCookie = cookieStr;
      }
    } catch (e) {
      debugPrint('[WebLogin] document.cookie 兜底失败: $e');
    }
  }

  /// 用户点击保存按钮 - 手动确认保存 cookie
  void _onSave() async {
    // 夸克/UC/蓝奏云/百度 使用 Cookie 认证，必须用完整 cookie（含 HttpOnly 的 __puus/__pus、
    // 蓝奏云 ylogin、百度 BDUSS/STOKEN），不能回退到 localStorage 里的 token。
    if (widget.driveType == DriveType.quark ||
        widget.driveType == DriveType.uc ||
        widget.driveType == DriveType.lanzou ||
        widget.driveType == DriveType.baidu) {
      if (_currentCookie.isEmpty) {
        _toast('未检测到登录 Cookie，请先登录后再点击保存');
        return;
      }
      if (mounted) Navigator.of(context).pop(_currentCookie);
      return;
    }

    // 阿里云盘：优先使用捕获到的 OAuth code（返回 Map，由 drive.login 兑换 refresh_token）。
    // cookie/localStorage 拿不到阿里云盘的 refresh_token。
    if (widget.driveType == DriveType.ali && _aliOauthCode.isNotEmpty) {
      if (mounted) Navigator.of(context).pop({'code': _aliOauthCode});
      return;
    }

    // 其他网盘：先尝试从 localStorage 获取 token
    String? result;

    final isXunlei = widget.driveType == DriveType.xunlei;

    try {
      final tokenResult = await _controller.runJavaScriptReturningResult('''
(function() {
  try {
    var keys = ${jsonEncode(_tokenKeys[widget.driveType] ?? [])};
    var isXunlei = ${widget.driveType == DriveType.xunlei};
    function pick(o) {
      if (!o) return '';
      if (o.refresh_token) return JSON.stringify({type: 'refresh_token', value: o.refresh_token});
      if (o.access_token) return JSON.stringify({type: 'access_token', value: o.access_token});
      if (o.token) return JSON.stringify({type: 'token', value: o.token});
      if (o.sessionId) return JSON.stringify({type: 'sessionId', value: o.sessionId});
      if (typeof o === 'string' && o.length > 20) return JSON.stringify({type: 'raw', value: o});
      return '';
    }
    // 迅雷网页登录：token 存于 credentials_<clientId> 的 JSON 对象里，
    // 这里精确定位并连同 client_id 一起返回，避免兜底扫描取到别的长字符串。
    if (isXunlei) {
      for (var c = 0; c < localStorage.length; c++) {
        var ck = localStorage.key(c);
        if (!ck || ck.indexOf('credentials_') !== 0) continue;
        try {
          var cv = JSON.parse(localStorage.getItem(ck));
          if (cv && (cv.access_token || cv.refresh_token)) {
            var cid = ck.substring('credentials_'.length);
            return JSON.stringify({type: 'token', value: JSON.stringify({
              access_token: cv.access_token || '',
              refresh_token: cv.refresh_token || '',
              user_id: cv.user_id || cv.uid || '',
              device_id: cv.deviceid || '',
              client_id: cid
            })});
          }
        } catch(e) {}
      }
    }
    for (var i = 0; i < keys.length; i++) {
      var val = localStorage.getItem(keys[i]);
      if (val) {
        try { var r = pick(JSON.parse(val)); if (r) return r; } catch(e) { var r = pick(val); if (r) return r; }
      }
    }
    // 兜底：扫描全部 localStorage，返回最可能的 token 型字段
    var best = ''; var bestKey = '';
    for (var k = 0; k < localStorage.length; k++) {
      var key = localStorage.key(k);
      if (!key) continue;
      var v = String(localStorage.getItem(key) || '');
      if (!v || v.length < 20) continue;
      try { var o = JSON.parse(v); var r = pick(o); if (r) return r; } catch(e) {}
      if (/access_token|accessToken|\.access\.|\.token/.test(key) && v.length > best.length) { best = v; bestKey = key; }
      if (v.length > 40 && v.length > best.length && !/^([0-9]+)\$/.test(v)) { best = v; bestKey = key; }
    }
    if (best) return JSON.stringify({type: 'token', value: best.trim(), key: bestKey});
    return '';
  } catch(e) { return ''; }
})();
''');
      final tokenStr = tokenResult.toString();
      if (tokenStr.isNotEmpty && tokenStr != '""' && tokenStr != "''") {
        try {
          final parsed = jsonDecode(tokenStr);
          final value = (parsed['value']?.toString() ?? '').trim();
          if (value.isNotEmpty && value.length >= 20) result = value;
        } catch (_) {}
      }
    } catch (_) {}

    // 如果没有 token，使用 cookie
    result ??= _currentCookie.isNotEmpty ? _currentCookie : null;

    if (result == null || result.isEmpty) {
      AppLogger.I.w(
        'web_login',
        '未获取到登录凭证 drive=${widget.driveType.name} '
        'localStorageKeys=${_tokenKeys[widget.driveType]} '
        'localStorage结果Token=${result ?? ''} cookieLen=${_currentCookie.length}',
      );
      _toast(isXunlei
          ? '未捕获到迅雷 access_token：请改用「手机号验证码登录」，或手动粘贴有效 Cookie'
          : '未检测到登录凭证，请先登录后再点击保存');
      return;
    }

    // 迅雷：若只拿到 Cookie（非 token），给出明确提示，避免误以为登录成功
    if (isXunlei && !result.startsWith('Bearer ') &&
        !result.contains('access_token') && !_looksLikeToken(result)) {
      AppLogger.I.w('web_login',
          '迅雷只捕获到 Cookie（非 Bearer token），该 Cookie 无法用于迅雷云盘 API，长度=${result.length}');
      _toast('检测到的是会话 Cookie，迅雷云盘需 access_token，请改用「验证码登录」');
      return;
    }

    AppLogger.I.i('web_login',
        '保存登录凭证成功 drive=${widget.driveType.name} 凭证长度=${result.length}');
    if (mounted) Navigator.of(context).pop(result);
  }

    /// 判断字符串是否像 token（用于迅雷等网盘：避免把 Cookie 误当 token 保存）
  bool _looksLikeToken(String value) {
    if (value.isEmpty) return false;
    // 过于短的一般不是 token
    if (value.length < 20) return false;
    // 包含常见 token 关键字
    if (value.contains('access_token') || value.contains('refresh_token') ||
        value.startsWith('Bearer ') || value.contains('eyJ') || // JWT
        value.contains('.')) {
      return true;
    }
    // 如果是 JSON 结构，可能是 token 对象
    if (value.startsWith('{') && value.contains('token')) return true;
    // 移除常见分隔符后判断是否还有字符
    final cleaned = value.replaceAll(RegExp(r'[=;,]'), '');
    if (cleaned.length > 30) return true;
    return false;
  }

  /// 手动粘贴 Cookie
  void _manualPaste() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴 Cookie'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 6,
            style: TextStyle(color: AppColors.of(context).textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '从浏览器复制 Cookie 粘贴到这里',
              hintStyle: TextStyle(fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.of(context).pop(text);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.driveType.label} 网页登录'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () => _controller.reload(),
            tooltip: '刷新',
          ),
          // 保存按钮 - 参考APK样式
          TextButton.icon(
            onPressed: _onSave,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.of(context).accent,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 提示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.of(context).accentDeep.withOpacity(0.3),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.of(context).accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '登录后点击右上角「保存」获取凭证',
                    style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _manualPaste,
                  child: const Text('手动粘贴', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.of(context).accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}