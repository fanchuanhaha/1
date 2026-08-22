import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/drive_type.dart';
import '../../theme/app_theme.dart';

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
    DriveType.xunlei: ['token', 'session', 'loginToken'],
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(isLanzou
          ? 'Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230805.001) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
          : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
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

  /// 刷新当前 Cookie
  ///
  /// 优先用 WebViewCookieManager 读取（可包含 HttpOnly cookie）。
  /// 夸克/UC 的关键会话 cookie（__puus、__pus）是 HttpOnly 的，
  /// document.cookie 读不到它们，缺失会导致后续接口返回 500。
  Future<void> _refreshCookie() async {
    // 1) 优先使用 CookieManager，能读到 HttpOnly cookie
    try {
      // 登录过程中可能有跳转（如 passport.baidu.com → pan.baidu.com），
      // 同时尝试初始登录页与当前页两个域名。
      final candidates = <Uri>[Uri.parse(widget.loginUrl)];
      try {
        final cur = _controller.currentUrl();
        if (cur != null && cur.isNotEmpty) {
          final u = Uri.parse(cur);
          if (!candidates.contains(u)) candidates.add(u);
        }
      } catch (_) {}
      for (final u in candidates) {
        final cookies =
            await WebViewCookieManager().getCookies(domain: u);
        if (cookies.isNotEmpty) {
          final parts = cookies
              .where((c) => c.name.isNotEmpty && c.value.isNotEmpty)
              .map((c) => '${c.name}=${c.value}')
              .toList();
          if (parts.isNotEmpty) {
            _currentCookie = parts.join('; ');
            return;
          }
        }
      }
    } catch (_) {}
    // 2) 兜底：document.cookie（读不到 HttpOnly）
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieStr = cookies.toString();
      if (cookieStr.isNotEmpty && cookieStr != '""' && cookieStr != "''") {
        _currentCookie = cookieStr;
      }
    } catch (_) {}
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

    // 其他网盘：先尝试从 localStorage 获取 token
    String? result;

    try {
      final tokenResult = await _controller.runJavaScriptReturningResult('''
(function() {
  try {
    var keys = ${jsonEncode(_tokenKeys[widget.driveType] ?? [])};
    for (var i = 0; i < keys.length; i++) {
      var val = localStorage.getItem(keys[i]);
      if (val) {
        try {
          var parsed = JSON.parse(val);
          if (parsed.refresh_token) return JSON.stringify({type: 'refresh_token', value: parsed.refresh_token});
          if (parsed.access_token) return JSON.stringify({type: 'access_token', value: parsed.access_token});
          if (parsed.token) return JSON.stringify({type: 'token', value: parsed.token});
        } catch(e) {
          if (val.length > 20) return JSON.stringify({type: 'raw', value: val});
        }
      }
    }
  } catch(e) {}
  return '';
})();
''');
      final tokenStr = tokenResult.toString();
      if (tokenStr.isNotEmpty && tokenStr != '""' && tokenStr != "''") {
        try {
          final parsed = jsonDecode(tokenStr);
          final value = parsed['value']?.toString() ?? '';
          if (value.isNotEmpty) result = value;
        } catch (_) {}
      }
    } catch (_) {}

    // 如果没有 token，使用 cookie
    result ??= _currentCookie.isNotEmpty ? _currentCookie : null;

    if (result == null || result.isEmpty) {
      _toast('未检测到登录凭证，请先登录后再点击保存');
      return;
    }

    if (mounted) Navigator.of(context).pop(result);
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
              foregroundColor: AppColors.accent,
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
            color: AppColors.accentDeep.withOpacity(0.3),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '登录后点击右上角「保存」获取凭证',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: _manualPaste,
                  child: const Text('手动粘贴', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
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