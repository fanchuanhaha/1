import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../api/ali_client.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../api/quark_auth.dart';
import 'login_service.dart';
import 'web_login_page.dart';
import 'password_login_page.dart';

/// 登录页面：支持多网盘选择与登录
/// 参考APK样式：每个登录方式为一个按钮，点击打开独立页面，登录成功后显示用户信息
class LoginPage extends StatefulWidget {
  /// 指定初始选中的网盘（从网盘列表点击进入时传参）
  final DriveType? initialDrive;

  const LoginPage({super.key, this.initialDrive});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late DriveType _selectedDrive;
  bool _loginSuccess = false;
  String? _nickname;
  String? _avatar;

  /// 是否来自网盘列表（有 initialDrive 则为特定网盘登录）
  bool get _isFromDrive => widget.initialDrive != null;

  @override
  void initState() {
    super.initState();
    _selectedDrive = widget.initialDrive ?? DriveType.quark;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loginSuccess ? '${_selectedDrive.label} 已登录' : '登录${_selectedDrive.label}'),
        actions: [
          if (_loginSuccess)
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.green),
              label: const Text(
                '返回保存',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.green),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 当从网盘列表进入时，显示当前网盘大图标和信息
          if (_isFromDrive) _buildDriveHeader(),
          // 如果未从网盘列表进入，显示网盘选择器
          if (!_isFromDrive)
            _DriveSelector(
              selected: _selectedDrive,
              onChanged: (type) {
                setState(() => _selectedDrive = type);
              },
            ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: _loginSuccess ? _buildLoginSuccess() : _buildLoginMethods(),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建网盘头部（大图标 + 名称）
  Widget _buildDriveHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              _selectedDrive.iconAsset,
              width: 44,
              height: 44,
              errorBuilder: (_, __, ___) => Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_rounded, color: AppColors.textSecondary, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedDrive.label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _loginSuccess ? '已登录' : '未登录',
                style: TextStyle(
                  color: _loginSuccess ? AppColors.green : AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建登录成功信息
  Widget _buildLoginSuccess() {
    return Column(
      children: [
        const SizedBox(height: 16),
        // 用户头像
        CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.green.withOpacity(0.15),
          child: _avatar != null && _avatar!.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    _avatar!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.person_rounded,
                      size: 48,
                      color: AppColors.green,
                    ),
                  ),
                )
              : const Icon(
                  Icons.person_rounded,
                  size: 48,
                  color: AppColors.green,
                ),
        ),
        const SizedBox(height: 16),
        Text(
          _nickname ?? '${_selectedDrive.label}用户',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: AppColors.green),
              SizedBox(width: 6),
              Text(
                '登录成功',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 网盘信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Row(
                children: [
                  Icon(Icons.storage_rounded, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text(
                    '容量: --',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.green),
                  SizedBox(width: 8),
                  Text(
                    '已登录，可正常使用网盘功能',
                    style: TextStyle(color: AppColors.green, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.check_rounded),
            label: const Text(
              '返回保存',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建当前网盘的登录方式按钮列表
  Widget _buildLoginMethods() {
    switch (_selectedDrive) {
      case DriveType.quark:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.qr_code_scanner_rounded,
            title: '扫码登录',
            subtitle: '使用夸克 App 扫码登录',
            color: AppColors.accent,
            onTap: () => _openPage(const _QrLoginPage()),
          ),
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(const _CookieLoginForm(driveType: DriveType.quark)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.quark),
          ),
        ]);

      case DriveType.ali:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.sms_rounded,
            title: '手机号验证码登录',
            subtitle: '使用手机号 + 短信验证码登录（参考原版）',
            color: AppColors.green,
            onTap: () => _openPage(const _AliSmsCodeLoginPage()),
          ),
          _MethodItem(
            icon: Icons.vpn_key_rounded,
            title: 'Refresh Token',
            subtitle: '使用阿里云盘 refresh_token 登录',
            color: AppColors.accent,
            onTap: () => _openPage(const _AliTokenLoginPage()),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.ali),
          ),
        ]);

      case DriveType.baidu:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.vpn_key_rounded,
            title: 'BDUSS + STOKEN',
            subtitle: '粘贴百度网盘 BDUSS 和 STOKEN',
            color: AppColors.accent,
            onTap: () => _openPage(const _BaiduTokenLoginPage()),
          ),
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(const _CookieLoginForm(driveType: DriveType.baidu)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.baidu),
          ),
        ]);

      case DriveType.tianyi:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.lock_rounded,
            title: '账号密码登录',
            subtitle: '使用手机号 + 密码登录',
            color: AppColors.accent,
            onTap: () => _openPage(PasswordLoginPage(driveType: DriveType.tianyi)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.tianyi),
          ),
        ]);

      case DriveType.pan123:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.lock_rounded,
            title: '账号密码登录',
            subtitle: '使用邮箱 + 密码登录',
            color: AppColors.accent,
            onTap: () => _openPage(PasswordLoginPage(driveType: DriveType.pan123)),
          ),
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(const _CookieLoginForm(driveType: DriveType.pan123)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.pan123),
          ),
        ]);

      case DriveType.lanzou:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.lock_rounded,
            title: '账号密码登录',
            subtitle: '在应用内登录蓝奏云，遇滑动验证请完成后点保存',
            color: AppColors.accent,
            onTap: () => _openWebLogin(DriveType.lanzou),
          ),
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(const _CookieLoginForm(driveType: DriveType.lanzou)),
          ),
        ]);

      case DriveType.xunlei:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.lock_rounded,
            title: '账号密码登录',
            subtitle: '使用迅雷账号和密码登录',
            color: AppColors.accent,
            onTap: () => _openPage(PasswordLoginPage(driveType: DriveType.xunlei)),
          ),
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(_CookieLoginForm(driveType: DriveType.xunlei)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(DriveType.xunlei),
          ),
        ]);

      default:
        return _buildMethodList([
          _MethodItem(
            icon: Icons.content_paste_rounded,
            title: 'Cookie 登录',
            subtitle: '粘贴浏览器 Cookie 登录',
            color: Colors.orange,
            onTap: () => _openPage(_CookieLoginForm(driveType: _selectedDrive)),
          ),
          _MethodItem(
            icon: Icons.language_rounded,
            title: '网页登录',
            subtitle: '在应用内打开登录页，登录后点击保存',
            color: Colors.blue,
            onTap: () => _openWebLogin(_selectedDrive),
          ),
        ]);
    }
  }

  /// 构建登录方法按钮列表
  Widget _buildMethodList(List<_MethodItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text('选择登录方式',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MethodCard(item: item),
            )),
      ],
    );
  }

  /// 登录成功后的处理：显示用户信息，不直接返回
  void _onLoginSuccess(DriveType type) {
    // 持久化除夸克外其它网盘的登录态，保证重启后仍在
    if (type != DriveType.quark) {
      DriveManager.I.saveDriveSession(type);
    }
    // 通知所有监听 DriveManager 的页面（如网盘列表）刷新登录态，立即显示「已登录」
    DriveManager.I.notifyListeners();
    // 获取用户信息
    String? nickname;
    String? avatar;

    if (type == DriveType.quark) {
      nickname = DriveManager.I.user?.nickname;
      avatar = DriveManager.I.user?.avatar;
    } else {
      final drive = DriveManager.I.getDrive(type);
      if (drive != null) {
        nickname = drive.userInfo?.nickname;
        avatar = drive.userInfo?.avatar;
      }
    }

    if (!mounted) return;
    setState(() {
      _loginSuccess = true;
      _nickname = nickname;
      _avatar = avatar;
    });
  }

  /// 打开独立页面（参考APK样式：页面有保存按钮）
  Future<void> _openPage(Widget page) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (result == true && mounted) {
      _onLoginSuccess(_selectedDrive);
    }
  }

  /// 打开网页登录页
  Future<void> _openWebLogin(DriveType type) async {
    final loginUrl = LoginService.getLoginUrl(type);
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WebLoginPage(
          driveType: type,
          loginUrl: loginUrl,
        ),
      ),
    );
    if (cookie == null || cookie.isEmpty || !mounted) return;

    // 尝试登录（夸克特殊处理）
    if (type == DriveType.quark) {
      final err = await DriveManager.I.login(cookie);
      if (!mounted) return;
      if (err == null) {
        _onLoginSuccess(type);
      } else {
        _toast('登录失败: $err');
      }
      return;
    }

    final drive = DriveManager.I.getDrive(type);
    if (drive == null) {
      _toast('驱动器未初始化');
      return;
    }
    final err = await drive.login(cookie);
    if (!mounted) return;
    if (err == null) {
      _onLoginSuccess(type);
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
// 登录方法卡片组件
// ═══════════════════════════════════════════════════════════════

class _MethodItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MethodItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _MethodCard extends StatelessWidget {
  final _MethodItem item;

  const _MethodCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: item.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 夸克扫码登录页面（独立页面，有保存按钮）
// ═══════════════════════════════════════════════════════════════

class _QrLoginPage extends StatefulWidget {
  const _QrLoginPage();

  @override
  State<_QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends State<_QrLoginPage> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录')),
      body: Center(
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
              const Text(
                '二维码 5 分钟内有效，请用夸克 App「扫一扫」登录',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用 Cookie 登录表单页面（独立页面，有保存按钮）
// ═══════════════════════════════════════════════════════════════

class _CookieLoginForm extends StatefulWidget {
  final DriveType driveType;

  const _CookieLoginForm({required this.driveType});

  @override
  State<_CookieLoginForm> createState() => _CookieLoginFormState();
}

class _CookieLoginFormState extends State<_CookieLoginForm> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.driveType.label} Cookie 登录'),
        actions: [
          TextButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _submitting ? '登录中…' : '保存',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: Padding(
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
                    '1. 打开网盘网页版并登录\n'
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
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '粘贴 Cookie',
                  hintStyle: TextStyle(fontSize: 13),
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
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

    // 夸克特殊处理
    if (widget.driveType == DriveType.quark) {
      final err = await DriveManager.I.login(cookie);
      if (!mounted) return;
      setState(() => _submitting = false);
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        _toast('登录失败: $err');
      }
      return;
    }

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
// 阿里云盘 Refresh Token 登录页面（独立页面，有保存按钮）
// ═══════════════════════════════════════════════════════════════

class _AliTokenLoginPage extends StatefulWidget {
  const _AliTokenLoginPage();

  @override
  State<_AliTokenLoginPage> createState() => _AliTokenLoginPageState();
}

class _AliTokenLoginPageState extends State<_AliTokenLoginPage> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阿里云盘登录'),
        actions: [
          TextButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _submitting ? '登录中…' : '保存',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
          ],
        ),
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
// 阿里云盘 手机号 + 短信验证码登录页面（参考原版 account + SMS 登录）
// 内嵌 WebView 加载阿里云盘授权页，用户用手机号+验证码登录，
// 结束回调到 www.aliyundrive.com/sign/callback?code=XXX 时自动捕获 code
// 并换取 refresh_token，登录完成自动返回。
// ═══════════════════════════════════════════════════════════════

class _AliSmsCodeLoginPage extends StatefulWidget {
  const _AliSmsCodeLoginPage();

  @override
  State<_AliSmsCodeLoginPage> createState() => _AliSmsCodeLoginPageState();
}

class _AliSmsCodeLoginPageState extends State<_AliSmsCodeLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _done = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) => _checkCallback(change.url),
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
            // 登录成功后优先从 localStorage 读取 refresh_token
            _tryReadRefreshToken();
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(AliClient.webviewLoginUrl));
  }

  /// 从阿里云盘网页的 localStorage 直接读取 refresh_token（token 键下含 refresh_token）
  Future<void> _tryReadRefreshToken() async {
    if (_done || !mounted) return;
    try {
      final tokenStr = await _controller.runJavaScriptReturningResult('''
(function() {
  try {
    var v = localStorage.getItem('token');
    if (v) {
      var p = JSON.parse(v);
      if (p && p.refresh_token) return String(p.refresh_token);
    }
  } catch(e) {}
  return '';
})();
''');
      final value = tokenStr.toString();
      if (value.isNotEmpty && value != '""' && value != "''") {
        await _completeLoginWith(value);
      }
    } catch (_) {}
  }

  /// 用 refresh_token 或 code 完成登录
  Future<void> _completeLoginWith(dynamic credential) async {
    _done = true;
    if (mounted) {
      setState(() {
        _status = '登录成功，正在获取凭证…';
        _loading = false;
      });
    }
    final drive = DriveManager.I.getDrive(DriveType.ali);
    String? err = '驱动器未初始化';
    if (drive != null) {
      err = await drive.login(credential);
    }
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _done = false;
        _status = '登录失败: $err';
      });
      _toast('登录失败: $err');
    }
  }

  /// 监听授权回调，捕获 code 并换取 token
  void _checkCallback(String? url) {
    if (url == null || _done) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    var code = uri.queryParameters['code'];
    if (code == null && uri.fragment.isNotEmpty) {
      // 兼容 code 放在 fragment 的情况
      try {
        final frag = Uri.splitQueryString(uri.fragment);
        code = frag['code'];
      } catch (_) {}
    }
    if (code == null) return;
    // 只在阿里云盘回调域名下触发，避免误抓
    final host = uri.host;
    if (!host.contains('aliyundrive.com') &&
        !host.contains('aliyundrive.cn') &&
        !host.contains('alipan.com')) {
      return;
    }
    if (code.trim().isEmpty) return;
    // 注意：_checkCallback 由 WebView onUrlChange 同步回调触发，非 async。
    // 这里发起异步登录，不需要在此等待。
    // ignore: unawaited_futures
    _completeLoginWith({'code': code.trim()});
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
        title: const Text('阿里云盘 验证码登录'),
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
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.accentDeep.withOpacity(0.3),
            child: Row(
              children: [
                const Icon(Icons.sms_rounded, size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status.isNotEmpty
                        ? _status
                        : '在下方页面输入手机号，点击「获取验证码」，登录成功后自动完成',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
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

// ═══════════════════════════════════════════════════════════════
// 百度网盘 BDUSS/STOKEN 登录页面（独立页面，有保存按钮）
// ═══════════════════════════════════════════════════════════════

class _BaiduTokenLoginPage extends StatefulWidget {
  const _BaiduTokenLoginPage();

  @override
  State<_BaiduTokenLoginPage> createState() => _BaiduTokenLoginPageState();
}

class _BaiduTokenLoginPageState extends State<_BaiduTokenLoginPage> {
  final _bdussController = TextEditingController();
  final _stokenController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _bdussController.dispose();
    _stokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('百度网盘登录'),
        actions: [
          TextButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              _submitting ? '登录中…' : '保存',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
            const SizedBox(height: 20),
            const Text(
              'BDUSS',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bdussController,
              maxLines: 2,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 BDUSS',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'STOKEN',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _stokenController,
              maxLines: 2,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '粘贴 STOKEN（可选，部分功能需要）',
                hintStyle: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final bduss = _bdussController.text.trim();
    if (bduss.isEmpty) {
      _toast('请先输入 BDUSS');
      return;
    }
    final stoken = _stokenController.text.trim();

    setState(() => _submitting = true);
    final drive = DriveManager.I.getDrive(DriveType.baidu);
    if (drive == null) {
      _toast('驱动器未初始化');
      setState(() => _submitting = false);
      return;
    }
    final err = await drive.login({'bduss': bduss, 'stoken': stoken});
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