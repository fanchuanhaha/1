import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/base_drive.dart';
import '../../api/drive_manager.dart';
import '../../api/drive_type.dart';
import '../../api/quark_client.dart';
import '../../api/quark_drive_adapter.dart';
import '../../state/app_state.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/permission.dart';
import 'share_files_page.dart';

/// 解析页面：自动识别粘贴链接所属的网盘，使用对应客户端解析
class ParsePage extends StatefulWidget {
  const ParsePage({super.key});

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage> {
  final _urlController = TextEditingController();
  final _pwdController = TextEditingController();
  final _btController = TextEditingController();

  bool _btMode = false;
  bool _parsing = false;
  List<Map<String, String>> _history = [];
  DriveType _selectedDrive = DriveType.quark;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    final text = _urlController.text.trim();
    if (text.isNotEmpty) {
      final detected = DriveType.detectFromUrl(text);
      if (detected != _selectedDrive) {
        setState(() => _selectedDrive = detected);
      }
    }
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('parse_history');
    if (raw != null) {
      final list = (raw.split('\n'))
          .where((e) => e.isNotEmpty)
          .map((e) {
            final parts = e.split('\u0001');
            return {
              'url': parts.isNotEmpty ? parts[0] : '',
              'pwd': parts.length > 1 ? parts[1] : '',
              'time': parts.length > 2 ? parts[2] : '',
            };
          })
          .toList();
      if (mounted) setState(() => _history = list);
    }
  }

  Future<void> _saveHistory(String url, String pwd) async {
    final time = DateTime.now().millisecondsSinceEpoch.toString();
    _history.removeWhere((e) => e['url'] == url);
    _history.insert(0, {'url': url, 'pwd': pwd, 'time': time});
    if (_history.length > 30) _history = _history.sublist(0, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'parse_history', _history.map((e) => e.values.join('\u0001')).join('\n'));
    if (mounted) setState(() {});
  }

  /// 解析分享链接，提取 pwdId 和 passcode
  ({String pwdId, String passcode}) _parseShareUrl(String url, DriveType type) {
    final u = url.trim();
    final lower = u.toLowerCase();

    switch (type) {
      case DriveType.quark:
        return QuarkClient.parseShareUrl(u);

      case DriveType.ali:
        // https://www.aliyundrive.com/s/xxxxx 或 https://www.alipan.com/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            // 提取提取码（通常在 URL 参数中）
            final passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['passcode'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.baidu:
        // https://pan.baidu.com/s/xxxxx?pwd=xxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.pikpak:
        // https://mypikpak.com/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.tianyi:
        // https://cloud.189.cn/t/xxxxx (访问码)
        // https://cloud.189.cn/web/share?code=xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 't') {
            // 路径格式：/t/xxxxx
            final passcode = uri.queryParameters['accessCode'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
          // 参数格式：?code=xxxxx
          final code = uri.queryParameters['code'] ?? '';
          if (code.isNotEmpty) {
            final passcode = uri.queryParameters['accessCode'] ?? '';
            return (pwdId: code, passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.uc:
        // https://drive.uc.cn/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.weiyun:
        // https://share.weiyun.com/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          // 提取路径最后一段作为 shareId
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments.last, passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.xunlei:
        // https://pan.xunlei.com/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.pan123:
        // https://www.123pan.com/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.yidong:
        // https://caiyun.139.com/w/i/?xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments.last, passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.guangya:
        // https://guangyapan.com/s/xxxxx
        final uri = Uri.tryParse(u);
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.length >= 2 && segments[0] == 's') {
            final passcode = uri.queryParameters['pwd'] ?? '';
            return (pwdId: segments[1], passcode: passcode);
          }
        }
        return (pwdId: '', passcode: '');

      case DriveType.lanzou:
        // https://pan.lanzoui.com/xxxxx 或 https://www.lanzou.com/xxxxx
        final uri = Uri.tryParse(u);
        String pwdId = '';
        if (uri != null) {
          final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) {
            pwdId = segments.last;
          }
          // 蓝奏云提取码在参数中
          final passcode = uri.queryParameters['pwd'] ?? uri.queryParameters['code'] ?? '';
          return (pwdId: pwdId, passcode: passcode);
        }
        return (pwdId: '', passcode: '');
    }
  }

  Future<void> _parse() async {
    if (_parsing) return;

    if (_btMode) {
      final magnet = _btController.text.trim();
      if (magnet.isEmpty) {
        _toast('请输入磁力链接或种子地址');
        return;
      }
      await _addBt(magnet);
      return;
    }

    final text = _urlController.text.trim();
    if (text.isEmpty) {
      _toast('请粘贴分享链接');
      return;
    }
    final urls = _extractUrls(text);
    if (urls.isEmpty) {
      _toast('未识别到有效链接');
      return;
    }

    final url = urls.first;
    if (url.startsWith('magnet:')) {
      await _addBt(url);
      return;
    }

    // 解析链接
    final parsed = _parseShareUrl(url, _selectedDrive);
    if (parsed.pwdId.isEmpty) {
      _toast('无法识别的分享链接');
      return;
    }
    final pwd = _pwdController.text.trim().isEmpty
        ? parsed.passcode
        : _pwdController.text.trim();

    // 获取对应网盘客户端
    final drive = _getDriveForType(_selectedDrive);
    if (drive == null) {
      _toast('该网盘暂不支持解析');
      return;
    }

    // 检查登录状态
    if (!drive.hasLogin) {
      _toast('请先登录${_selectedDrive.label}');
      return;
    }

    setState(() => _parsing = true);
    try {
      final session = await drive.getShareToken(parsed.pwdId, pwd);
      final files = await drive.listShare(session, '0');
      await _saveHistory(url, pwd);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ShareFilesPage(
          drive: drive,
          session: session,
          initialFiles: files,
          initialName: _selectedDrive.label,
          cookie: _selectedDrive == DriveType.quark
              ? DriveManager.I.quark.downloadCookieSnapshot
              : '',
        ),
      ));
    } catch (e) {
      _toast('解析失败: $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  /// 根据网盘类型获取对应的驱动器实例
  BaseDrive? _getDriveForType(DriveType type) {
    if (type == DriveType.quark) {
      return QuarkDriveAdapter(DriveManager.I.quark);
    }
    return DriveManager.I.getDrive(type);
  }

  Future<void> _addBt(String magnet) async {
    setState(() => _parsing = true);
    try {
      final err = await DownloadService.addMagnet(url: magnet);
      if (err != null) throw Exception(err);
      showDownloadAddedToast(context, '已添加到下载队列');
    } catch (e) {
      _toast('添加失败: $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  List<String> _extractUrls(String text) {
    final re = RegExp(r'''https?://[^\s<>"'，。]+''');
    return re.allMatches(text).map((m) => m.group(0)!).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    _pwdController.dispose();
    _btController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${now.day} / ${months[now.month - 1]}',
                          style: const TextStyle(
                              fontSize: 30, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text('下午好，解析分享链接',
                          style: TextStyle(
                              color: AppColors.of(context).accent, fontSize: 14)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _showHistory(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).accentDeep,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            color: AppColors.of(context).accent, size: 18),
                        SizedBox(width: 6),
                        Text('历史',
                            style: TextStyle(
                                color: AppColors.of(context).accent, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildInputCard(),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text('解析记录',
                        style: TextStyle(
                            color: AppColors.of(context).textSecondary, fontSize: 13)),
                  ),
                  ..._history.map(_buildHistoryItem),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.of(context).accentDeep,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.paste_rounded,
                    color: AppColors.of(context).accent, size: 19),
              ),
              const SizedBox(width: 10),
              Text('粘贴内容',
                  style: TextStyle(
                      color: AppColors.of(context).textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _urlController,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(color: AppColors.of(context).textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '粘贴分享链接或包含链接的文本（自动识别网盘）',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pwdController,
            style: TextStyle(color: AppColors.of(context).textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '提取码（自动识别，可手动修改）',
            ),
          ),
          if (_btMode) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _btController,
              maxLines: 2,
              minLines: 1,
              style:
                  TextStyle(color: AppColors.of(context).textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '磁力链接或种子文件地址（magnet: 开头）',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _btMode = !_btMode),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _btMode ? AppColors.of(context).accent : AppColors.of(context).textSecondary,
                    backgroundColor: _btMode ? AppColors.of(context).accentDeep : AppColors.of(context).bg,
                    side: BorderSide(color: _btMode ? AppColors.of(context).accent : AppColors.of(context).divider),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_btMode ? '关闭 BT 输入' : '+ 添加BT'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _parsing ? null : _parse,
                  style: FilledButton.styleFrom(
                    backgroundColor: _parsing
                        ? AppColors.of(context).accentDeep
                        : AppColors.of(context).accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _parsing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('开始解析'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, String> item) {
    final url = item['url'] ?? '';
    final pwd = item['pwd'] ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () async {
          _urlController.text = url;
          _pwdController.text = pwd;
          await _parse();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.of(context).card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.of(context).accentDeep,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.link_rounded,
                    color: AppColors.of(context).accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.of(context).textPrimary, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(
                      pwd.isEmpty ? '无提取码' : '提取码: $pwd',
                      style: TextStyle(
                          color: AppColors.of(context).textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _removeHistory(url),
                icon: Icon(Icons.close_rounded,
                    color: AppColors.of(context).textSecondary, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeHistory(String url) async {
    setState(() {
      _history.removeWhere((e) => e['url'] == url);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'parse_history', _history.map((e) => e.values.join('\u0001')).join('\n'));
  }

  void _showHistory() {
    if (_history.isEmpty) {
      _toast('暂无解析记录');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('解析记录',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _history.map((e) {
                  return ListTile(
                    leading: Icon(Icons.link_rounded,
                        color: AppColors.of(context).accent),
                    title: Text(e['url'] ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(e['pwd'] == null || e['pwd']!.isEmpty
                        ? '无提取码'
                        : '提取码: ${e['pwd']}'),
                    onTap: () {
                      Navigator.pop(context);
                      _urlController.text = e['url'] ?? '';
                      _pwdController.text = e['pwd'] ?? '';
                      _parse();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}