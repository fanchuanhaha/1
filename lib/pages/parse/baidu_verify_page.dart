import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 百度「安全验证」内嵌页。
///
/// 当百度 filemanager 等管理操作返回 errno=132（verify_scene 风控安全验证）时，
/// 通过本页在应用内用 WebView 注入当前已登录的百度 Cookie 并载入百度网盘，
/// 让用户直接在应用内完成百度要求的安全验证（滑块/点选等）。
/// 完成后点击「保存」，本页会把刷新后的完整 Cookie 合并返回给调用方，
/// 由外层保存回网盘客户端并自动重试原操作。
class BaiduVerifyPage extends StatefulWidget {
  /// 当前已登录的百度 Cookie（BDUSS=xxx; STOKEN=xxx; ...）
  final String cookie;

  const BaiduVerifyPage({super.key, required this.cookie});

  @override
  State<BaiduVerifyPage> createState() => _BaiduVerifyPageState();
}

class _BaiduVerifyPageState extends State<BaiduVerifyPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String _currentCookie = '';

  /// 可能存放百度关键会话 cookie 的子域都读一遍再合并，避免漏掉跳转子域。
  static const _domainHosts = [
    'passport.baidu.com',
    'pan.baidu.com',
    'yun.baidu.com',
  ];

  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    _buildController();
    // 先注入登录 Cookie，再加载页面，确保 WebView 里是已登录的百度网盘。
    _injectCookies().then((_) {
      _controller.loadRequest(Uri.parse('https://pan.baidu.com/disk/main'));
    });
  }

  Future<void> _injectCookies() async {
    final pairs = _cookieToMap(widget.cookie);
    if (pairs.isEmpty) return;
    for (final host in _domainHosts) {
      for (final e in pairs.entries) {
        try {
          await WebViewCookieManager().setCookie(WebViewCookie(
            name: e.key,
            value: e.value,
            domain: host,
            path: '/',
          ));
        } catch (err) {
          AppLogger.I.w('baidu_verify', '注入 cookie 失败 $host/${e.key}: $err');
        }
      }
    }
  }

  void _buildController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _refreshCookie();
          // 验证可能涉及跳转，页面就绪后延迟再合并一次最新 cookie。
          Future.delayed(const Duration(milliseconds: 1800), () {
            if (mounted) _refreshCookie();
          });
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ));
  }

  static Map<String, String> _cookieToMap(String cookie) {
    final map = <String, String>{};
    for (final seg in cookie.split(';')) {
      final idx = seg.indexOf('=');
      if (idx <= 0) continue;
      final k = seg.substring(0, idx).trim();
      final v = seg.substring(idx + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
    }
    return map;
  }

  /// 从 WebView 合并各百度子域上的 cookie（能读到 HttpOnly）。
  Future<void> _refreshCookie() async {
    try {
      final allParts = <String>{};
      for (final host in _domainHosts) {
        final cookies = await WebViewCookieManager()
            .getCookies(domain: Uri.parse('https://$host/'));
        for (final c in cookies) {
          if (c.name.isNotEmpty && c.value.isNotEmpty) {
            allParts.add('${c.name}=${c.value}');
          }
        }
      }
      if (allParts.isNotEmpty) {
        final merged = allParts.join('; ');
        if (merged != _currentCookie) {
          AppLogger.I.i('baidu_verify',
              '验证页合并 cookie 长度=${merged.length} 含BDUSS=${merged.contains("BDUSS")}');
          _currentCookie = merged;
        }
        // 至少保证原 BDUSS 在场（若 WebView 途中自行登出会丢失，这里用注入值兜底）
        if (!_currentCookie.contains('BDUSS') &&
            widget.cookie.contains('BDUSS')) {
          _currentCookie = widget.cookie;
        }
      } else if (_currentCookie.isEmpty) {
        _currentCookie = widget.cookie;
      }
    } catch (e) {
      AppLogger.I.w('baidu_verify', '读取验证页 cookie 失败: $e');
      if (_currentCookie.isEmpty) _currentCookie = widget.cookie;
    }
  }

  void _onSave() {
    if (mounted) Navigator.of(context).pop(_currentCookie);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('百度网盘 · 安全验证'),
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
          ),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.of(context).accentDeep.withOpacity(0.3),
            child: Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    size: 16, color: AppColors.of(context).accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已自动带入当前百度账号。请在下方完成弹出的安全验证后，点右上角「保存」',
                    style: TextStyle(
                        color: AppColors.of(context).textSecondary,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}