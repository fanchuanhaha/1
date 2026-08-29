import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/update_checker.dart';
import '../../state/app_state.dart';
import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

class MePage extends StatelessWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final app = AppState.I;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('我的',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
              _buildSettingsCard(context, app),
              const SizedBox(height: 16),
              _buildInterfaceCard(context, app),
              const SizedBox(height: 16),
              _buildAboutCard(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingsCard(BuildContext context, AppState app) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.folder_rounded, color: AppColors.of(context).accent),
            title: const Text('下载目录'),
            subtitle: Text(app.downloadDir,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _editDownloadDir(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading:
                Icon(Icons.speed_rounded, color: AppColors.of(context).accent),
            title: const Text('下载连接数'),
            subtitle: Text('每个任务 ${app.connections} 线程并发下载'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _editConnections(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.cloud_upload_rounded,
                color: AppColors.of(context).accent),
            title: const Text('上传并行数'),
            subtitle: Text('同时上传 ${app.uploadParallelism} 个文件'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _editUploadParallelism(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.storage_rounded, color: AppColors.of(context).accent),
            title: const Text('存储权限'),
            subtitle: const Text('访问下载目录所需权限'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => app.openAllFilesAccess(),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.battery_saver_rounded,
                color: AppColors.of(context).accent),
            title: const Text('后台运行'),
            subtitle: const Text('允许忽略电池优化，锁屏后仍持续下载'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => app.requestIgnoreBattery(),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.close_fullscreen_rounded,
                color: AppColors.of(context).accent),
            title: const Text('关闭窗口时'),
            subtitle: Text(_closeActionLabel(app.closeAction)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _editCloseAction(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading:
                Icon(Icons.dark_mode_rounded, color: AppColors.of(context).accent),
            title: const Text('深色模式'),
            subtitle: Text(_themeModeLabel(app.themeMode)),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _editThemeMode(context, app),
          ),
        ],
      ),
    );
  }

  /// 「接口」设置卡片：目前内置「野鸡百度加速」，预留后续新增接口。
  /// 结构为接口列表，每个接口可展开，包含开启开关与密码配置。
  Widget _buildInterfaceCard(BuildContext context, AppState app) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('接口',
                style: TextStyle(
                    color: AppColors.of(context).textSecondary, fontSize: 12)),
          ),
          const Divider(height: 1),
          _InterfaceTile(
            icon: Icons.bolt_rounded,
            name: '野鸡百度加速',
            desc: '百度网盘下载走第三方解析直链',
            enabled: app.baiduAccelEnabled,
            password: app.baiduAccelPassword,
            needsPassword: true,
            onEnabledChanged: (on) => app.setBaiduAccelEnabled(on),
            onPasswordChanged: (p) => app.setBaiduAccelPassword(p),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.bug_report_rounded,
                color: AppColors.of(context).accent),
            title: const Text('日志'),
            subtitle: const Text('查看/复制运行日志，排查容量与文件加载问题'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _showLog(context),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.system_update_alt_rounded,
                color: AppColors.of(context).accent),
            title: const Text('检查更新'),
            subtitle: const Text('查看 GitHub Releases 是否有新版本'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () =>
                UpdateChecker.checkAndPrompt(context, manual: true),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.info_outline_rounded,
                color: AppColors.of(context).accent),
            title: const Text('关于'),
            subtitle: const Text('Quarklite v1.1.3  ·  基于 Gopeed 下载引擎'),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _showLog(BuildContext context) async {
    final path = await AppLogger.I.logPath();
    var content = await AppLogger.I.readLog();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('运行日志'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('日志文件位置：',
                    style: TextStyle(fontSize: 12, color: AppColors.of(context).textSecondary)),
                SelectableText(path,
                    style: TextStyle(fontSize: 12, color: AppColors.of(context).accent)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 220,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).cardLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: TextStyle(
                          fontSize: 11, color: AppColors.of(context).textSecondary, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            TextButton.icon(
              icon: Icon(Icons.delete_sweep_rounded,
                  size: 18, color: AppColors.of(context).red),
              label: Text('清空日志',
                  style: TextStyle(color: AppColors.of(context).red)),
              onPressed: () async {
                await AppLogger.I.clear();
                content = await AppLogger.I.readLog();
                if (!ctx.mounted) return;
                setDialogState(() {});
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('日志已清空')));
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('复制日志'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('日志已复制，请直接粘贴发送给开发者')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editDownloadDir(BuildContext context, AppState app) {
    final controller = TextEditingController(text: app.downloadDir);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载目录'),
        content: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.of(context).textPrimary),
          decoration: const InputDecoration(
              hintText: '/storage/emulated/0/Download/Quarklite'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final dir = controller.text.trim();
              if (dir.isNotEmpty) {
                await app.setDownloadDir(dir);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _closeActionLabel(String action) {
    switch (action) {
      case 'minimize':
        return '最小化到托盘（后台继续下载）';
      case 'exit':
        return '直接退出';
      case 'ask':
        return '每次询问';
      default:
        return '首次询问后记住（默认）';
    }
  }

  String _themeModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return '浅色';
      case 'system':
        return '跟随系统';
      default:
        return '深色（默认）';
    }
  }

  void _editThemeMode(BuildContext context, AppState app) {
    final options = <(String, String)>[
      ('dark', '深色（默认）'),
      ('light', '浅色'),
      ('system', '跟随系统'),
    ];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('深色模式'),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setThemeMode(value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    value == app.themeMode
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: value == app.themeMode
                        ? AppColors.of(context).accent
                        : AppColors.of(context).textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editCloseAction(BuildContext context, AppState app) {
    final options = <(String, String)>[
      ('ask_once', '首次询问后记住（默认）'),
      ('minimize', '最小化到托盘（后台继续下载）'),
      ('exit', '直接退出'),
      ('ask', '每次询问'),
    ];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('关闭窗口时'),
        children: [
          for (final (value, label) in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setCloseAction(value);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    value == app.closeAction
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: value == app.closeAction
                        ? AppColors.of(context).accent
                        : AppColors.of(context).textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child:
                        Text(label, style: const TextStyle(fontSize: 14)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editConnections(BuildContext context, AppState app) {
    final options = [4, 8, 16, 32];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('下载连接数'),
        children: [
          for (final n in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setConnections(n);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    n == app.connections
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: n == app.connections
                        ? AppColors.of(context).accent
                        : AppColors.of(context).textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('$n 线程', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editUploadParallelism(BuildContext context, AppState app) {
    final options = [1, 2, 3, 4];
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('上传并行数'),
        children: [
          for (final n in options)
            SimpleDialogOption(
              onPressed: () async {
                await app.setUploadParallelism(n);
                // 上传管理器立即获取新值（老的任务跑完按新并行数补充）
                UploadManager.I.overrideParallelism = 0;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  Icon(
                    n == app.uploadParallelism
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: n == app.uploadParallelism
                        ? AppColors.of(context).accent
                        : AppColors.of(context).textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('同时上传 $n 个文件', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: Text(
              '并行数越高上传越快，但可能使页面卡顿或触发接口限流；默认为 1，请按网络与设备性能自行取舍。',
              style: TextStyle(
                  fontSize: 12, color: AppColors.of(context).textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quarklite'),
        content: const Text(
          '夸克网盘不限速下载工具\n\n'
          '· 内置 Gopeed 多线程下载引擎\n'
          '· 支持分享链接解析 / 网盘直连 / BT 磁力\n'
          '· 本项目基于 GPL-3.0 协议开源\n\n'
          'v1.0.0',
          style: TextStyle(fontSize: 13, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 「接口」列表中的单个可展开项：头部为图标/名称/描述 + 开启开关，
/// 展开后露出密码配置与说明。结构可复用，便于后续新增更多接口。
class _InterfaceTile extends StatefulWidget {
  final IconData icon;
  final String name;
  final String desc;
  final bool enabled;
  final String password;
  final bool needsPassword;
  final Future<void> Function(bool) onEnabledChanged;
  final Future<void> Function(String) onPasswordChanged;

  const _InterfaceTile({
    required this.icon,
    required this.name,
    required this.desc,
    required this.enabled,
    required this.password,
    required this.onEnabledChanged,
    required this.onPasswordChanged,
    this.needsPassword = false,
  });

  @override
  State<_InterfaceTile> createState() => _InterfaceTileState();
}

class _InterfaceTileState extends State<_InterfaceTile> {
  bool _expanded = false;

  void _toggleExpand() => setState(() => _expanded = !_expanded);

  /// 切换开关：开启时若需要密码但尚未填写，则先引导填写密码。
  Future<void> _toggleEnabled() async {
    if (widget.enabled) {
      await widget.onEnabledChanged(false);
      return;
    }
    if (widget.needsPassword && widget.password.isEmpty) {
      await _editPassword(enableAfterSave: true);
      return;
    }
    await widget.onEnabledChanged(true);
  }

  Future<void> _editPassword({bool enableAfterSave = false}) async {
    final controller = TextEditingController(text: widget.password);
    if (!mounted) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${widget.name}」解析密码'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '请输入站点公告提供的解析密码',
            labelText: '解析密码',
          ),
          style: TextStyle(color: AppColors.of(ctx).textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    await widget.onPasswordChanged(saved);
    if (enableAfterSave && !widget.enabled) {
      await widget.onEnabledChanged(true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('解析密码已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.of(context).accent;
    final textSecondary = AppColors.of(context).textSecondary;
    return Column(
      children: [
        InkWell(
          onTap: _toggleExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? accent.withValues(alpha: 0.15)
                        : AppColors.of(context).cardLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon,
                      color: widget.enabled ? accent : textSecondary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.name,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        widget.enabled
                            ? '已开启'
                            : (widget.needsPassword && widget.password.isEmpty
                                ? '未配置解析密码'
                                : '未开启'),
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: widget.enabled,
                  activeColor: accent,
                  onChanged: (_) => _toggleEnabled(),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: textSecondary,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.needsPassword) ...[
                  Text('说明：下载百度网盘文件前，会先对该文件创建公开分享链接，再由该接口解析出加速直链下载。该接口需要填写解析密码才能使用。',
                      style: TextStyle(fontSize: 12, color: textSecondary, height: 1.5)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.password.isEmpty ? '解析密码：未设置' : '解析密码：${widget.password}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _editPassword(),
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('修改密码'),
                      ),
                    ],
                  ),
                ] else
                  Text(widget.desc,
                      style: TextStyle(fontSize: 12, color: textSecondary)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}