import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../api/quark_auth.dart';
import 'login_service.dart';
import 'web_login_page.dart';

/// 登录页面：支持多网盘选择与登录
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
        return const _AliLoginView();
      case DriveType.baidu:
        return const _BaiduLoginView();
      default:
        return _MultiLoginView(driveType: _selectedDrive);
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
// 夸克登录：扫码 + Cookie + 网页登录
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
            Tab(text: '扫码登录'),
            Tab(text: 'Cookie 登录'),
            Tab(text: '网页登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _QrLoginView(),
              _QuarkCookieLoginView(),
              _WebLoginTab(driveType: DriveType.quark),
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
            const Text(
              '二维码 5 分钟内有效，请用夸克 App「扫一扫」登录',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
// 阿里云盘登录：refresh_token + 网页登录
// ═══════════════════════════════════════════════════════════════

class _AliLoginView extends StatefulWidget {
  const _AliLoginView();

  @override
  State<_AliLoginView> createState() => _AliLoginViewState();
}

class _AliLoginViewState extends State<_AliLoginView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _tab.dispose();
    _controller.dispose();
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
            Tab(text: 'Refresh Token'),
            Tab(text: '网页登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildTokenView(),
              const _WebLoginTab(driveType: DriveType.ali),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTokenView() {
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
// 百度网盘登录：BDUSS+STOKEN / Cookie + 网页登录
// ═══════════════════════════════════════════════════════════════

class _BaiduLoginView extends StatefulWidget {
  const _BaiduLoginView();

  @override
  State<_BaiduLoginView> createState() => _BaiduLoginViewState();
}

class _BaiduLoginViewState extends State<_BaiduLoginView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  bool _useCookieMode = false;
  final _bdussController = TextEditingController();
  final _stokenController = TextEditingController();
  final _cookieController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _tab.dispose();
    _bdussController.dispose();
    _stokenController.dispose();
    _cookieController.dispose();
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
            Tab(text: '账号/Cookie'),
            Tab(text: '网页登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _buildFormView(),
              const _WebLoginTab(driveType: DriveType.baidu),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 模式切换
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
            // Cookie 模式
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
            // BDUSS + STOKEN 模式
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
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 13),
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
// 通用多方式登录（其他网盘）：Cookie + 网页登录
// ═══════════════════════════════════════════════════════════════

class _MultiLoginView extends StatefulWidget {
  final DriveType driveType;

  const _MultiLoginView({required this.driveType});

  @override
  State<_MultiLoginView> createState() => _MultiLoginViewState();
}

class _MultiLoginViewState extends State<_MultiLoginView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
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
            Tab(text: 'Cookie 登录'),
            Tab(text: '网页登录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _CookieLoginView(driveType: widget.driveType),
              _WebLoginTab(driveType: widget.driveType),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用网页登录 Tab
// ═══════════════════════════════════════════════════════════════

class _WebLoginTab extends StatelessWidget {
  final DriveType driveType;

  const _WebLoginTab({required this.driveType});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.accentDeep,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.language_rounded,
                        color: AppColors.accent, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '网页登录',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在应用内打开 ${driveType.label} 登录页面，\n登录后自动获取凭证',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openWebLogin(context),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: const Text('打开网页登录'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  Future<void> _openWebLogin(BuildContext context) async {
    final loginUrl = LoginService.getLoginUrl(driveType);
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WebLoginPage(
          driveType: driveType,
          loginUrl: loginUrl,
        ),
      ),
    );
    if (cookie == null || cookie.isEmpty || !context.mounted) return;
    final drive = DriveManager.I.getDrive(driveType);
    if (drive == null) {
      _toast(context, '驱动器未初始化');
      return;
    }
    final err = await drive.login(cookie);
    if (!context.mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      _toast(context, '登录失败: $err');
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          TextField(
            controller: _controller,
            maxLines: 8,
            style:
                const TextStyle(color: AppColors.textPrimary, fontSize: 13),
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