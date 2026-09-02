import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/drive_manager.dart';
import '../../api/drive_type.dart';
import '../../api/xunlei_client.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 迅雷云盘 手机号 + 短信验证码登录
///
/// 参考原版 APK 的官方账号+短信流程：输入绑定手机号 → 点击「获取验证码」
/// （调用 xluser.core.login/v3/sendsms）→ 输入短信验证码 → 直接登录
/// （调用 xluser.core.login/v3/smslogin 换取 access_token）。
class XunleiSmsLoginPage extends StatefulWidget {
  const XunleiSmsLoginPage({super.key});

  @override
  State<XunleiSmsLoginPage> createState() => _XunleiSmsLoginPageState();
}

class _XunleiSmsLoginPageState extends State<XunleiSmsLoginPage> {
  final _phoneController = TextEditingController();
  final _smsController = TextEditingController();

  bool _sending = false;
  bool _submitting = false;
  int _countdown = 0;
  String? _err;
  Timer? _timer;

  XunleiClient? get _client {
    final d = DriveManager.I.getDrive(DriveType.xunlei);
    return d is XunleiClient ? d : null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _toast('请输入手机号');
      return;
    }
    setState(() { _sending = true; _err = null; });
    AppLogger.I.i('xunlei_login', '发送短信验证码 phone=$phone');
    try {
      final c = _client;
      if (c == null) {
        _toast('迅雷驱动器未初始化');
        setState(() => _sending = false);
        return;
      }
      await c.sendSmsCode(phone);
      AppLogger.I.i('xunlei_login', '短信验证码发送成功 phone=$phone');
      if (!mounted) return;
      setState(() => _sending = false);
      _toast('验证码已发送，请注意查收');
      _startCountdown();
    } on XunleiException catch (e) {
      AppLogger.I.e('xunlei_login', '发送短信验证码失败 code=${e.code} msg=${e.message}');
      if (!mounted) return;
      setState(() { _sending = false; _err = '发送失败(${e.code}): ${e.message}'; });
    } catch (e) {
      AppLogger.I.e('xunlei_login', '发送短信验证码异常 $e');
      if (!mounted) return;
      setState(() { _sending = false; _err = '发送失败: $e'; });
    }
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    final smsCode = _smsController.text.trim();
    if (phone.isEmpty || smsCode.isEmpty) {
      _toast('请输入手机号和验证码');
      return;
    }
    setState(() { _submitting = true; _err = null; });
    AppLogger.I.i('xunlei_login', '短信登录提交 phone=$phone');
    try {
      final d = DriveManager.I.getDrive(DriveType.xunlei);
      if (d == null) {
        _toast('迅雷驱动器未初始化');
        setState(() => _submitting = false);
        return;
      }
      final err = await d.login({
        'type': 'sms',
        'phone': phone,
        'sms_code': smsCode,
      });
      if (!mounted) return;
      if (err == null) {
        AppLogger.I.i('xunlei_login', '短信登录成功 phone=$phone');
        Navigator.of(context).pop(true);
      } else {
        AppLogger.I.e('xunlei_login', '短信登录失败 $err');
        setState(() { _submitting = false; _err = err; });
      }
    } catch (e) {
      AppLogger.I.e('xunlei_login', '短信登录异常 $e');
      if (!mounted) return;
      setState(() { _submitting = false; _err = '登录失败: $e'; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _smsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('迅雷云盘 验证码登录'),
        backgroundColor: c.bg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入手机号获取验证码，验证后直接登录（参考官方账号 + 短信流程，无需网页）',
              style: TextStyle(fontSize: 13, color: Color(0xFF8A8F98)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              decoration: const InputDecoration(
                labelText: '手机号',
                hintText: '请输入迅雷账号绑定的手机号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _smsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      hintText: '输入短信验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: (_sending || _countdown > 0) ? null : _sendCode,
                    child: Text(
                      _countdown > 0
                          ? '$_countdown s'
                          : (_sending ? '发送中…' : '获取验证码'),
                    ),
                  ),
                ),
              ],
            ),
            if (_err != null) ...[
              const SizedBox(height: 14),
              Text(
                _err!,
                style: const TextStyle(color: Color(0xFFE5484D), fontSize: 13),
              ),
            ],
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _submitting ? null : _login,
                child: Text(
                  _submitting ? '登录中…' : '登录',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}