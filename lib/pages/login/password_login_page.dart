import 'package:flutter/material.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../theme/app_theme.dart';
import 'login_service.dart';

/// 密码登录页面（参考APK的 TianyiPasswordLoginDebug / Pan123LoginDebug）
/// 顶部有「保存」按钮，用户输入账号密码后点击保存提交
class PasswordLoginPage extends StatefulWidget {
  final DriveType driveType;

  const PasswordLoginPage({super.key, required this.driveType});

  @override
  State<PasswordLoginPage> createState() => _PasswordLoginPageState();
}

class _PasswordLoginPageState extends State<PasswordLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  bool _submitting = false;
  bool _needCaptcha = false;
  String? _status;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  String get _label => widget.driveType.label;

  bool get _isPhoneLogin =>
      widget.driveType == DriveType.tianyi;

  Future<void> _onSave() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      _toast('请输入${_isPhoneLogin ? "手机号" : "账号"}');
      return;
    }
    if (password.isEmpty) {
      _toast('请输入密码');
      return;
    }

    setState(() {
      _submitting = true;
      _status = '正在登录…';
    });

    try {
      String? result;
      Map<String, dynamic>? credentialMap;
      if (widget.driveType == DriveType.tianyi) {
        final r = await LoginService.tianyiPasswordLogin(
          phone: username,
          password: password,
          captchaCode: _captchaController.text.trim().isEmpty
              ? null
              : _captchaController.text.trim(),
        );
        result = r['cookie'];
      } else if (widget.driveType == DriveType.pan123) {
        final r = await LoginService.pan123PasswordLogin(
          username: username,
          password: password,
          captcha: _captchaController.text.trim().isEmpty
              ? null
              : _captchaController.text.trim(),
        );
        result = r['cookie'];
      } else if (widget.driveType == DriveType.lanzou) {
        // 蓝奏云：由 LanzouClient 通过 mlogin.php 直接提交账号密码
        credentialMap = {'username': username, 'password': password};
      } else if (widget.driveType == DriveType.xunlei) {
        // 迅雷网盘：由 XunleiClient 提交账号密码换取 access_token
        credentialMap = {
          'type': 'password',
          'username': username,
          'password': password,
        };
      }

      if (widget.driveType != DriveType.lanzou &&
          widget.driveType != DriveType.xunlei &&
          (result == null || result.isEmpty)) {
        throw Exception('未获取到登录凭证');
      }

      // 调用 drive.login 保存凭证
      final drive = DriveManager.I.getDrive(widget.driveType);
      if (drive == null) {
        _toast('驱动器未初始化');
        setState(() => _submitting = false);
        return;
      }
      final err = credentialMap != null
          ? await drive.login(credentialMap)
          : await drive.login(result);
      if (!mounted) return;
      if (err == null) {
        Navigator.of(context).pop(true);
      } else {
        _toast('登录失败: $err');
      }
    } on CaptchaRequiredException {
      setState(() {
        _needCaptcha = true;
        _submitting = false;
        _status = '请输入验证码';
      });
      return;
    } catch (e) {
      _toast('登录失败: $e');
    }

    if (mounted) setState(() => _submitting = false);
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
        title: Text('$_label 登录'),
        actions: [
          // 保存按钮 - 参考APK样式
          TextButton.icon(
            onPressed: _submitting ? null : _onSave,
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
            // 图标
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accentDeep,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.accent, size: 36),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '账号密码登录',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(
                _status!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 32),

            // 账号输入
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                labelText: _isPhoneLogin ? '手机号' : '账号',
                hintText: _isPhoneLogin ? '输入手机号' : '输入邮箱/账号',
                prefixIcon: Icon(
                  _isPhoneLogin ? Icons.phone_android_rounded : Icons.person_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              keyboardType: _isPhoneLogin ? TextInputType.phone : TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // 密码输入
            TextField(
              controller: _passwordController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: const InputDecoration(
                labelText: '密码',
                hintText: '输入密码',
                prefixIcon: Icon(Icons.lock_rounded, color: AppColors.textSecondary),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // 验证码输入（需要时显示）
            if (_needCaptcha) ...[
              TextField(
                controller: _captchaController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: const InputDecoration(
                  labelText: '验证码',
                  hintText: '输入验证码',
                  prefixIcon:
                      Icon(Icons.text_fields_rounded, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 状态提示
            if (_needCaptcha)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentDeep.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: AppColors.accent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '需要验证码，请查看网页版登录页面获取验证码',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}