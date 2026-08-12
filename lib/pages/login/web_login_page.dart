import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/drive_type.dart';
import '../../theme/app_theme.dart';

/// 网页登录页面：使用 WebView 加载网盘登录页，登录后自动捕获 Cookie 和 Token
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
  String _status = '正在加载登录页面…';
  bool _loginDone = false;
  String _capturedResult = '';

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
    DriveType.baidu: [
      'bduss',
      'token',
      'loginToken',
    ],
    DriveType.pikpak: [
      'token',
      'session',
      'auth_token',
    ],
    DriveType.uc: [
      'token',
      'loginToken',
      'auth_token',
    ],
    DriveType.tianyi: [
      'token',
      'session',
      'loginToken',
    ],
    DriveType.xunlei: [
      'token',
      'session',
      'loginToken',
    ],
    DriveType.pan123: [
      'token',
      'loginToken',
      'auth_token',
    ],
  };

  /// 各网盘的关键 cookie 检测字符串
  static const _cookieCheckKeys = {
    DriveType.quark: '__pus=',
    DriveType.ali: 'token=',
    DriveType.baidu: 'BDUSS=',
    DriveType.pikpak: 'token=',
    DriveType.uc: '__pus=',
    DriveType.tianyi: 'cookie=',
    DriveType.weiyun: 'session=',
    DriveType.xunlei: 'token=',
    DriveType.pan123: 'token=',
    DriveType.yidong: 'token=',
    DriveType.guangya: 'token=',
  };

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _status = '正在加载…';
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _loading = false);
            _captureToken();
            _tryExtractCookie();
          },
          onNavigationRequest: (request) {
            _captureToken();
            _tryExtractCookie();
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _status = '加载失败: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.loginUrl));
  }

  /// 注入 JS 从 localStorage 捕获 token（类似 APK 的 captureToken）
  Future<void> _captureToken() async {
    try {
      // 先检查 localStorage 中是否有 token
      final result = await _controller.runJavaScriptReturningResult('''
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
    // 检查 document.cookie
    var c = document.cookie;
    if (c && c.length > 20) return JSON.stringify({type: 'cookie', value: c});
  } catch(e) {}
  return '';
})();
''');
      final tokenStr = result.toString();
      if (tokenStr.isNotEmpty && tokenStr != '""' && tokenStr != "''" && tokenStr != _capturedResult) {
        _capturedResult = tokenStr;
        try {
          final parsed = jsonDecode(tokenStr);
          final value = parsed['value']?.toString() ?? '';
          if (value.isNotEmpty) {
            if (!mounted) return;
            setState(() => _status = '已检测到登录凭证，正在返回…');
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted) {
              Navigator.of(context).pop(value);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 从 document.cookie 提取登录凭证
  Future<void> _tryExtractCookie() async {
    try {
      final cookies = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final cookieStr = cookies.toString();
      if (cookieStr.isNotEmpty && cookieStr != _capturedResult) {
        // 检查是否包含关键登录凭证
        final checkKey = _cookieCheckKeys[widget.driveType] ?? '';
        if (checkKey.isNotEmpty && cookieStr.contains(checkKey)) {
          _capturedResult = cookieStr;
          if (!mounted) return;
          setState(() => _status = '已检测到登录凭证，正在返回…');
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            Navigator.of(context).pop(cookieStr);
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.driveType.label} 网页登录'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部提示条
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.accentDeep.withOpacity(0.3),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
                // 手动复制按钮
                TextButton.icon(
                  onPressed: _manualCopyDialog,
                  icon: const Icon(Icons.content_paste_rounded, size: 14),
                  label: const Text('手动粘贴Cookie', style: TextStyle(fontSize: 11)),
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

  /// 手动粘贴 Cookie 的对话框（类似 APK 的备用方式）
  void _manualCopyDialog() {
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
              final cookie = controller.text.trim();
              if (cookie.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.of(context).pop(cookie);
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}