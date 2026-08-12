import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../api/quark_auth.dart';

/// 登录页面：支持多网盘选择与登录，新增网页登录和账号密码登录
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  DriveType _selectedDrive = DriveType.quark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('登录${_selectedDrive.label}'),
      ),
      body: Column(
        children: [
          _DriveSelector(
            selected: _selectedDrive,
            onChanged: (type) {
              setState(() => _selectedDrive = type);
            },
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildLoginContent()),
        ],
      ),
    );
  }

  Widget _buildLoginContent() {
    switch (_selectedDrive) {
      case DriveType.quark:
        return const _QuarkLoginContent();
      case DriveType.ali:
        return const _AliLoginContent();
      case DriveType.baidu:
        return const _BaiduLoginContent();
      case DriveType.tianyi:
        return const _TianyiLoginContent();
      case DriveType.guangya:
        return const _GuangyaLoginContent();
      case DriveType.xunlei:
        return const _XunleiLoginContent();
      case DriveType.pan123:
        return const _Pan123LoginContent();
      default:
        return _DefaultLoginContent(driveType: _selectedDrive);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// 顶部网盘选择器
// ═══════════════════════════════════════════════════════════════

class _DriveSelector extends StatelessWidget {
  final DriveType selected;
  final ValueChanged<DriveType> onChanged;

  const _DriveSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: DriveType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final type = DriveType.values[index];
          final isSelected = type == selected;
          return GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 68,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent.withOpacity(0.15)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.divider,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      type.iconAsset,
                      width: 28,
                      height: 28,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.cloud_outlined,
                        size: 28,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用网页登录（WebView）
// ═══════════════════════════════════════════════════════════════

class _WebLoginView extends StatefulWidget {
  final DriveType driveType;
  final String loginUrl;

  const _WebLoginView({
    required this.driveType,
    required this.loginUrl,
  });

  @override
  State<_WebLoginView> createState() => _WebLoginViewState();
}

class _WebLoginViewState extends State<_WebLoginView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _loginDone = false;
  String _status = '正在加载登录页面…';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'QuarkliteChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _loading = false);
            _injectAndCapture();
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.loginUrl));
  }

  /// 注入 JavaScript 捕获 cookies 和 localStorage 中的 token
  Future<void> _injectAndCapture() async {
    if (_loginDone) return;
    await _controller.runJavaScript('''
(function() {
  try {
    var cookies = document.cookie || '';
    var storage = {};
    for (var i = 0; i < localStorage.length; i++) {
      var key = localStorage.key(i);
      try { storage[key] = localStorage.getItem(key); } catch(e) {}
    }
    var sessionStorage = {};
    for (var i = 0; i < sessionStorage.length; i++) {
      var key = sessionStorage.key(i);
      try { sessionStorage[key] = sessionStorage.getItem(key); } catch(e) {}
    }
    QuarkliteChannel.postMessage(JSON.stringify({
      cookies: cookies,
      localStorage: storage,
      sessionStorage: sessionStorage,
      url: window.location.href
    }));
  } catch(e) {
    QuarkliteChannel.postMessage(JSON.stringify({error: e.toString()}));
  }
})();
''');
  }

  void _onJsMessage(JavaScriptMessage message) {
    if (_loginDone) return;
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      if (data.containsKey('error')) return;

      final cookies = data['cookies'] as String? ?? '';
      final url = data['url'] as String? ?? '';
      final storage = data['localStorage'] as Map<String, dynamic>? ?? {};

      // 检查 localStorage 中是否有 token
      String? capturedToken;
      const tokenKeys = [
        'token', 'TOKEN', 'loginToken', 'login_token', 'auth_token',
        'access_token', 'refresh_token', 'bdstoken',
        'aliyundrive_token', 'alipan_token', 'accountToken',
        '__pus', '__puus',
      ];
      for (final key in tokenKeys) {
        final val = storage[key]?.toString();
        if (val != null && val.isNotEmpty && val.length > 4) {
          capturedToken = val;
          debugPrint('捕获到 token: $key');
          break;
        }
      }

      // 检查 cookies 是否有效（有登录特征）
      final hasValidCookie = cookies.isNotEmpty &&
          (cookies.contains('__pus=') ||
              cookies.contains('BDUSS=') ||
              cookies.contains('token=') ||
              cookies.contains('sid=') ||
              cookies.contains('session=') ||
              cookies.contains('login=') ||
              cookies.length > 50);

      if (capturedToken != null || hasValidCookie) {
        _loginDone = true;
        setState(() => _status = '登录成功，正在验证…');
        _attemptLogin(cookies, capturedToken, storage);
      }
    } catch (_) {}
  }

  Future<void> _attemptLogin(
      String cookies, String? token, Map<String, dynamic> storage) async {
    String? err;

    // 根据网盘类型选择登录方式
    switch (widget.driveType) {
      case DriveType.quark:
        if (cookies.isNotEmpty) {
          err = await AppState.I.login(cookies);
        }
        break;
      case DriveType.ali:
        final drive = DriveManager.I.getDrive(DriveType.ali);
        if (drive != null) {
          final refreshToken = storage['refresh_token']?.toString() ?? token ?? '';
          if (refreshToken.isNotEmpty) {
            err = await drive.login(refreshToken);
          }
        }
        break;
      case DriveType.baidu:
        final drive = DriveManager.I.getDrive(DriveType.baidu);
        if (drive != null) {
          final bduss = _extractCookie(cookies, 'BDUSS');
          final stoken = _extractCookie(cookies, 'STOKEN');
          if (bduss.isNotEmpty) {
            err = await drive.login({'bduss': bduss, 'stoken': stoken});
          }
        }
        break;
      default:
        // 通用：尝试用 cookie 登录
        final drive = DriveManager.I.getDrive(widget.driveType);
        if (drive != null && cookies.isNotEmpty) {
          err = await drive.login(cookies);
        }
        break;
    }

    if (!mounted) return;
    if (err == null) {
      _toast('登录成功');
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _loginDone = false;
        _status = '登录验证失败，请重试';
      });
      _toast('登录失败: $err');
    }
  }

  String _extractCookie(String cookie, String key) {
    final regex = RegExp('$key=([^;]+)', caseSensitive: false);
    final match = regex.firstMatch(cookie);
    return match?.group(1)?.trim() ?? '';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator()),
        if (!_loading && _loginDone)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_status,
                    style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用账号密码登录（带验证码）
// ═══════════════════════════════════════════════════════════════

class _AccountPasswordLoginView extends StatefulWidget {
  final DriveType driveType;
  final String? captchaUrl; // 验证码图片 URL（可选）

  const _AccountPasswordLoginView({
    required this.driveType,
    this.captchaUrl,
  });

  @override
  State<_AccountPasswordLoginView> createState() =>
      _AccountPasswordLoginViewState();
}

class _AccountPasswordLoginViewState extends State<_AccountPasswordLoginView> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _submitting = false;
  bool _showCaptcha = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 说明
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '使用 ${widget.driveType.label} 账号密码登录',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 账号输入
          const Text('账号',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _accountController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '请输入手机号/邮箱',
              prefixIcon:
                  Icon(Icons.person_outline, color: AppColors.textSecondary),
            ),
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 16),
          // 密码输入
          const Text('密码',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '请输入密码',
              prefixIcon:
                  Icon(Icons.lock_outline, color: AppColors.textSecondary),
            ),
          ),
          // 验证码输入
          if (_showCaptcha) ...[
            const SizedBox(height: 16),
            const Text('验证码',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _captchaController,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: '请输入验证码',
                      prefixIcon: Icon(Icons.text_fields_rounded,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.captchaUrl != null)
                  Container(
                    width: 100,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        widget.captchaUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_rounded,
                              color: AppColors.textSecondary, size: 24),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text.trim();
    if (account.isEmpty) {
      _toast('请输入账号');
      return;
    }
    if (password.isEmpty) {
      _toast('请输入密码');
      return;
    }

    setState(() => _submitting = true);

    // 获取驱动器实例
    final drive = DriveManager.I.getDrive(widget.driveType);
    if (drive == null) {
      _toast('该网盘暂不支持账号密码登录');
      setState(() => _submitting = false);
      return;
    }

    // 尝试登录 - 各驱动器的 login 方法接收不同类型参数
    String? err;
    try {
      err = await drive.login({
        'username': account,
        'password': password,
        'captcha': _captchaController.text.trim(),
      });
    } catch (e) {
      err = e.toString();
    }

    if (!mounted) return;
    setState(() => _submitting = false);

    if (err == null) {
      _toast('登录成功');
      Navigator.of(context).pop(true);
    } else if (err.contains('captcha') || err.contains('验证码')) {
      setState(() => _showCaptcha = true);
      _toast('需要输入验证码');
    } else {
      _toast('登录失败: $err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═══════════════════════════════════════════════════════════════
// 夸克登录：网页 + 扫码 + Cookie
// ═══════════════════════════════════════════════════════════════

class _QuarkLoginContent extends StatefulWidget {
  const _QuarkLoginContent();

  @override
  State<_QuarkLoginContent> createState() => _QuarkLoginContentState();
}

class _QuarkLoginContentState extends State<_QuarkLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          isScrollable: true,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: '扫码登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.quark,
                loginUrl: 'https://pan.quark.cn/',
              ),
              const _QrLoginView(),
              const _QuarkCookieLoginView(),
            ],
          ),
        ),
      ],
    );
  }
}

// ──────── 夸克扫码登录 ────────

class _QrLoginView extends StatefulWidget {
  const _QrLoginView();

  @override
  State<_QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<_QrLoginView> {
  final _auth = QuarkQrLogin();
  String? _qrUrl;
  String? _status;
  bool _loading = true;
  Timer? _pollTimer;
  bool _loginDone = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _qrUrl = null;
      _status = '正在获取二维码…';
    });
    try {
      final url = await _auth.fetchQrUrl();
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _loading = false;
        _status = '请使用夸克 App 扫码登录';
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = '获取二维码失败: $e';
      });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_loginDone) return;
      String? cookie;
      try {
        cookie = await _auth.checkOnce();
      } catch (_) {
        return;
      }
      if (cookie == null || !mounted) return;
      _pollTimer?.cancel();
      _loginDone = true;
      setState(() => _status = '登录成功，正在验证…');
      final err = await AppState.I.login(cookie);
      if (!mounted) return;
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _status = '验证失败: $err';
          _loginDone = false;
        });
        _startPolling();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const CircularProgressIndicator()
            else if (_qrUrl != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: _qrUrl!,
                  size: 240,
                  backgroundColor: Colors.white,
                ),
              )
            else
              const Icon(Icons.qr_code_2_rounded,
                  size: 120, color: AppColors.cardLight),
            const SizedBox(height: 20),
            Text(
              _status ?? '',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '二维码 5 分钟内有效，请用夸克 App「扫一扫」登录',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _refresh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              ),
              child: const Text('刷新二维码'),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────── 夸克 Cookie 登录 ────────

class _QuarkCookieLoginView extends StatefulWidget {
  const _QuarkCookieLoginView();

  @override
  State<_QuarkCookieLoginView> createState() => _QuarkCookieLoginViewState();
}

class _QuarkCookieLoginViewState extends State<_QuarkCookieLoginView> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '从浏览器登录 pan.quark.cn 后，复制 Cookie 粘贴到这里（登录二维码失效时的备用方式）',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 Cookie，形如 __pus=xxx; __puus=xxx; ...',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      _toast('请先粘贴 Cookie');
      return;
    }
    setState(() => _submitting = true);
    final err = await AppState.I.login(cookie);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      _toast('登录失败: $err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═══════════════════════════════════════════════════════════════
// 阿里云盘登录：网页 + Token
// ═══════════════════════════════════════════════════════════════

class _AliLoginContent extends StatefulWidget {
  const _AliLoginContent();

  @override
  State<_AliLoginContent> createState() => _AliLoginContentState();
}

class _AliLoginContentState extends State<_AliLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Token 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.ali,
                loginUrl: 'https://www.aliyundrive.com/sign/in',
              ),
              const _AliTokenLoginView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _AliTokenLoginView extends StatefulWidget {
  const _AliTokenLoginView();

  @override
  State<_AliTokenLoginView> createState() => _AliTokenLoginViewState();
}

class _AliTokenLoginViewState extends State<_AliTokenLoginView> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: AppColors.accent),
                    SizedBox(width: 8),
                    Text(
                      '如何获取 refresh_token？',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  '1. 打开 https://www.aliyundrive.com/ 并登录\n'
                  '2. 按 F12 打开开发者工具\n'
                  '3. 在 Console 中输入：\n'
                  '   JSON.parse(localStorage.getItem("token"))?.refresh_token\n'
                  '4. 复制输出的 refresh_token 值',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Refresh Token',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '粘贴 refresh_token',
              hintStyle: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final token = _controller.text.trim();
    if (token.isEmpty) {
      _toast('请先输入 refresh_token');
      return;
    }
    setState(() => _submitting = true);
    final drive = DriveManager.I.getDrive(DriveType.ali);
    if (drive == null) {
      _toast('驱动器未初始化');
      setState(() => _submitting = false);
      return;
    }
    final err = await drive.login(token);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      _toast('登录成功');
      Navigator.of(context).pop(true);
    } else {
      _toast('登录失败: $err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═══════════════════════════════════════════════════════════════
// 百度网盘登录：网页 + BDUSS/STOKEN + Cookie
// ═══════════════════════════════════════════════════════════════

class _BaiduLoginContent extends StatefulWidget {
  const _BaiduLoginContent();

  @override
  State<_BaiduLoginContent> createState() => _BaiduLoginContentState();
}

class _BaiduLoginContentState extends State<_BaiduLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'BDUSS/STOKEN'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.baidu,
                loginUrl: 'https://pan.baidu.com/',
              ),
              const _BaiduTokenLoginView(),
            ],
          ),
        ),
      ],
    );
  }
}

class _BaiduTokenLoginView extends StatefulWidget {
  const _BaiduTokenLoginView();

  @override
  State<_BaiduTokenLoginView> createState() => _BaiduTokenLoginViewState();
}

class _BaiduTokenLoginViewState extends State<_BaiduTokenLoginView> {
  bool _useCookieMode = false;
  final _bdussController = TextEditingController();
  final _stokenController = TextEditingController();
  final _cookieController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _bdussController.dispose();
    _stokenController.dispose();
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _modeChip('BDUSS + STOKEN', !_useCookieMode, () {
                setState(() => _useCookieMode = false);
              }),
              const SizedBox(width: 10),
              _modeChip('Cookie', _useCookieMode, () {
                setState(() => _useCookieMode = true);
              }),
            ],
          ),
          const SizedBox(height: 20),
          if (_useCookieMode) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        '如何获取 Cookie？',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    '1. 打开 https://pan.baidu.com/ 并登录\n'
                    '2. 按 F12 打开开发者工具\n'
                    '3. 在 Network 中找到任意请求\n'
                    '4. 复制 Request Headers 中的 Cookie 值',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Cookie',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _cookieController,
              maxLines: 5,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 Cookie，形如 BDUSS=xxx; STOKEN=yyy; ...',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppColors.accent),
                      SizedBox(width: 8),
                      Text(
                        '如何获取 BDUSS 和 STOKEN？',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    '1. 打开 https://pan.baidu.com/ 并登录\n'
                    '2. 按 F12 打开开发者工具\n'
                    '3. 在 Application > Cookies 中\n'
                    '   找到 BDUSS 和 STOKEN 的值',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('BDUSS',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _bdussController,
              maxLines: 2,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 BDUSS',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            const Text('STOKEN',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: _stokenController,
              maxLines: 2,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 STOKEN（可选，部分功能需要）',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withOpacity(0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.divider,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.accent : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final drive = DriveManager.I.getDrive(DriveType.baidu);
    if (drive == null) {
      _toast('驱动器未初始化');
      return;
    }
    setState(() => _submitting = true);
    String? err;
    if (_useCookieMode) {
      final cookie = _cookieController.text.trim();
      if (cookie.isEmpty) {
        _toast('请先粘贴 Cookie');
        setState(() => _submitting = false);
        return;
      }
      final bduss = _extractCookieValue(cookie, 'BDUSS');
      final stoken = _extractCookieValue(cookie, 'STOKEN');
      if (bduss.isEmpty) {
        _toast('Cookie 中未找到 BDUSS');
        setState(() => _submitting = false);
        return;
      }
      err = await drive.login({'bduss': bduss, 'stoken': stoken});
    } else {
      final bduss = _bdussController.text.trim();
      if (bduss.isEmpty) {
        _toast('请先输入 BDUSS');
        setState(() => _submitting = false);
        return;
      }
      final stoken = _stokenController.text.trim();
      err = await drive.login({'bduss': bduss, 'stoken': stoken});
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      _toast('登录成功');
      Navigator.of(context).pop(true);
    } else {
      _toast('登录失败: $err');
    }
  }

  String _extractCookieValue(String cookie, String key) {
    final regex = RegExp('$key=([^;]+)', caseSensitive: false);
    final match = regex.firstMatch(cookie);
    return match?.group(1)?.trim() ?? '';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═══════════════════════════════════════════════════════════════
// 天翼云盘登录：网页 + 账号密码 + Cookie
// ═══════════════════════════════════════════════════════════════

class _TianyiLoginContent extends StatefulWidget {
  const _TianyiLoginContent();

  @override
  State<_TianyiLoginContent> createState() => _TianyiLoginContentState();
}

class _TianyiLoginContentState extends State<_TianyiLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.tianyi,
                loginUrl: 'https://cloud.189.cn/',
              ),
              _CookieLoginView(driveType: DriveType.tianyi),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 光丫盘登录：网页 + 账号密码 + Cookie
// ═══════════════════════════════════════════════════════════════

class _GuangyaLoginContent extends StatefulWidget {
  const _GuangyaLoginContent();

  @override
  State<_GuangyaLoginContent> createState() => _GuangyaLoginContentState();
}

class _GuangyaLoginContentState extends State<_GuangyaLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.guangya,
                loginUrl: 'https://guangyapan.com/',
              ),
              _CookieLoginView(driveType: DriveType.guangya),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 迅雷网盘登录：网页 + 账号密码 + Cookie
// ═══════════════════════════════════════════════════════════════

class _XunleiLoginContent extends StatefulWidget {
  const _XunleiLoginContent();

  @override
  State<_XunleiLoginContent> createState() => _XunleiLoginContentState();
}

class _XunleiLoginContentState extends State<_XunleiLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.xunlei,
                loginUrl: 'https://pan.xunlei.com/',
              ),
              _CookieLoginView(driveType: DriveType.xunlei),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 123云盘登录：网页 + 账号密码 + Cookie
// ═══════════════════════════════════════════════════════════════

class _Pan123LoginContent extends StatefulWidget {
  const _Pan123LoginContent();

  @override
  State<_Pan123LoginContent> createState() => _Pan123LoginContentState();
}

class _Pan123LoginContentState extends State<_Pan123LoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: DriveType.pan123,
                loginUrl: 'https://www.123pan.com/',
              ),
              _CookieLoginView(driveType: DriveType.pan123),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用登录（其他网盘）：网页 + Cookie
// ═══════════════════════════════════════════════════════════════

class _DefaultLoginContent extends StatefulWidget {
  final DriveType driveType;

  const _DefaultLoginContent({required this.driveType});

  @override
  State<_DefaultLoginContent> createState() => _DefaultLoginContentState();
}

class _DefaultLoginContentState extends State<_DefaultLoginContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  String _getLoginUrl() {
    switch (widget.driveType) {
      case DriveType.pikpak:
        return 'https://mypikpak.com/';
      case DriveType.uc:
        return 'https://drive.uc.cn/';
      case DriveType.weiyun:
        return 'https://www.weiyun.com/';
      case DriveType.yidong:
        return 'https://yun.139.com/';
      default:
        return 'https://www.123pan.com/';
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: '网页登录'),
            Tab(text: 'Cookie 登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _WebLoginView(
                driveType: widget.driveType,
                loginUrl: _getLoginUrl(),
              ),
              _CookieLoginView(driveType: widget.driveType),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用 Cookie 登录（其他网盘）
// ═══════════════════════════════════════════════════════════════

class _CookieLoginView extends StatefulWidget {
  final DriveType driveType;

  const _CookieLoginView({required this.driveType});

  @override
  State<_CookieLoginView> createState() => _CookieLoginViewState();
}

class _CookieLoginViewState extends State<_CookieLoginView> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      '如何获取 ${widget.driveType.label} Cookie？',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  '1. 打开网页版并登录\n'
                  '2. 按 F12 打开开发者工具\n'
                  '3. 在 Network 中找到任意请求\n'
                  '4. 复制 Request Headers 中的 Cookie 值',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cookie',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 5,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              hintText: '粘贴 Cookie',
              hintStyle: TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) {
      _toast('请先粘贴 Cookie');
      return;
    }
    setState(() => _submitting = true);

    final drive = DriveManager.I.getDrive(widget.driveType);
    if (drive == null) {
      _toast('驱动器未初始化');
      setState(() => _submitting = false);
      return;
    }

    final err = await drive.login(cookie);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err == null) {
      _toast('登录成功');
      Navigator.of(context).pop(true);
    } else {
      _toast('登录失败: $err');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}