import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/baidu_accel_service.dart';
import '../../api/drive_type.dart';
import '../../core/update_checker.dart';
import '../../state/app_state.dart';
import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';

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
            leading: Icon(Icons.swap_vert_rounded,
                color: AppColors.of(context).accent),
            title: const Text('下载与上传'),
            subtitle: Text('目录 · 线程 · 上传并行 · 按网盘设置线程数'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _showTransferSettings(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: Icon(Icons.shield_outlined,
                color: AppColors.of(context).accent),
            title: const Text('权限'),
            subtitle: const Text('存储访问 · 后台运行（忽略电池优化）'),
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary),
            onTap: () => _showPermissions(context, app),
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
            subtitle: Text('Quarklite v${_displayVersion()}  ·  基于 Gopeed 下载引擎'),
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
    // 弹窗内实时刷新日志：每秒重读文件，若出现新内容（如清空后紧接着操作产生的日志）
    // 自动更新显示并滚动到底部展示最新一条，否则旧内容不动。
    final scrollCtrl = ScrollController();
    var lastContent = content;
    Timer? timer;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) async {
              final fresh = await AppLogger.I.readLog();
              if (fresh == lastContent) return;
              lastContent = fresh;
              content = fresh;
              if (!ctx.mounted) return;
              setDialogState(() {});
              // 新日志出现后滚动到底部，让最新一条立即可见
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollCtrl.hasClients) {
                  final pos = scrollCtrl.position;
                  if (pos.maxScrollExtent > 0) {
                    scrollCtrl.animateTo(pos.maxScrollExtent,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut);
                  }
                }
              });
            });
            return AlertDialog(
              title: Text('运行日志(${(content.isEmpty) ? 0 : content.split('\n').length}行)'),
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
                        controller: scrollCtrl,
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
                TextButton(
                  onPressed: () async {
                    final r = await AppLogger.I.exportTo('/sdcard/1.log');
                    if (!ctx.mounted) return;
                    AppMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(r.ok
                            ? '日志已导出到 ${r.message}'
                            : r.message)));
                  },
                  child: Text('导出/1.log',
                      style: TextStyle(
                          color: AppColors.of(context).textSecondary)),
                ),
                TextButton.icon(
                  icon: Icon(Icons.delete_sweep_rounded,
                      size: 18, color: AppColors.of(context).red),
                  label: Text('清空日志',
                      style: TextStyle(color: AppColors.of(context).red)),
                  onPressed: () async {
                    await AppLogger.I.clear();
                    content = await AppLogger.I.readLog();
                    lastContent = content;
                    if (!ctx.mounted) return;
                    setDialogState(() {});
                    AppMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('日志已清空')));
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('复制日志'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: content));
                    if (ctx.mounted) {
                      Navigator.pop(context);
                      AppMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('日志已复制，请直接粘贴发送给开发者')));
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      timer?.cancel();
    });
  }

  /// 「下载与上传」一级页面：下载目录 / 下载连接数 / 上传并行数。
  /// 点「下载连接数」进入二级设置，可为每个网盘单独配置下载线程数。
  void _showTransferSettings(BuildContext context, AppState app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: AppState.I,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下载与上传',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.of(context).textPrimary)),
                const SizedBox(height: 6),
                Text('下载线程可按网盘独立设置，未单独设置的网盘使用全局默认值。',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.of(context).textSecondary)),
                const SizedBox(height: 14),
                _SheetTile(
                  icon: Icons.folder_rounded,
                  title: '下载目录',
                  subtitle: app.downloadDir,
                  onTap: () {
                    Navigator.pop(ctx);
                    _editDownloadDir(context, app);
                  },
                ),
                const Divider(height: 1, indent: 48),
                _SheetTile(
                  icon: Icons.speed_rounded,
                  title: '下载连接数',
                  subtitle:
                      '全局默认 ${app.connections} 线程 · 点此按网盘单独设置',
                  onTap: () => _showDriveThreads(ctx, app),
                ),
                const Divider(height: 1, indent: 48),
                _SheetTile(
                  icon: Icons.cloud_upload_rounded,
                  title: '上传并行数',
                  subtitle: '同时上传 ${app.uploadParallelism} 个文件',
                  onTap: () {
                    Navigator.pop(ctx);
                    _editUploadParallelism(context, app);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「权限」一级页面：存储访问 + 后台运行（忽略电池优化）。单项点击不弹二级，
  /// 直接在页面内给出两个操作项，点击即拉起对应系统权限引导。
  void _showPermissions(BuildContext context, AppState app) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('权限',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.of(context).textPrimary)),
              const SizedBox(height: 14),
              _SheetTile(
                icon: Icons.storage_rounded,
                title: '存储访问',
                subtitle: '允许读写下载目录（“所有文件访问权限”）',
                onTap: () {
                  Navigator.pop(ctx);
                  app.openAllFilesAccess();
                },
              ),
              const Divider(height: 1, indent: 48),
              _SheetTile(
                icon: Icons.battery_saver_rounded,
                title: '后台运行',
                subtitle: '允许忽略电池优化，锁屏后仍持续下载',
                onTap: () {
                  Navigator.pop(ctx);
                  app.requestIgnoreBattery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「下载连接数」二级设置：列出常用网盘，各自可设置专属线程数（夸克最大 128）。
  void _showDriveThreads(BuildContext dialogCtx, AppState app) {
    final drives = <DriveType>[
      DriveType.quark,
      DriveType.baidu,
      DriveType.xunlei,
      DriveType.ali,
      DriveType.tianyi,
      DriveType.lanzou,
    ];
    showModalBottomSheet(
      context: dialogCtx,
      backgroundColor: AppColors.of(dialogCtx).card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
          child: ListenableBuilder(
            listenable: AppState.I,
            builder: (ctx, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          color: AppColors.of(ctx).accent, size: 24),
                      const SizedBox(width: 8),
                      Text('按网盘设置下载线程',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.of(ctx).textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('未设置的网盘沿用全局默认 ${app.connections} 线程。夸克最大可调 128。',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.of(ctx).textSecondary)),
                  const SizedBox(height: 12),
                  for (final d in drives) ...[
                    _DriveThreadTile(
                      drive: d,
                      value: app.connectionsFor(d),
                      onChanged: (n) => app.setDriveConnections(d, n),
                    ),
                    const Divider(height: 1, indent: 48),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
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
        content: Text(
          '夸克网盘不限速下载工具\n\n'
          '· 内置 Gopeed 多线程下载引擎\n'
          '· 支持分享链接解析 / 网盘直连 / BT 磁力\n'
          '· 本项目基于 GPL-3.0 协议开源\n\n'
          'v${_displayVersion()}',
          style: const TextStyle(fontSize: 13, height: 1.7),
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

  /// 当前应用版本号（去 v 前缀）。CI 通过 --dart-define=APP_VERSION 注入，
  /// 未注入（本地开发）时回退 0.0.0 —— 与检查更新的版本来源保持一致。
  String _displayVersion() {
    var v = UpdateChecker.kLocalVersion.trim();
    if (v.toLowerCase().startsWith('v')) v = v.substring(1);
    return v;
  }
}

/// 设置在底部弹层中的一行「图标 + 标题 + 副标题 + 箭头」。
class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.of(context).accent),
      title: Text(title),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.of(context).textSecondary)),
      trailing: Icon(Icons.chevron_right_rounded,
          color: AppColors.of(context).textSecondary),
      onTap: onTap,
    );
  }
}

/// 单个网盘的下载线程数设置行。点击弹出可选线程数，夸克最大 128，其它默认到 64。
class _DriveThreadTile extends StatelessWidget {
  final DriveType drive;
  final int value;
  final ValueChanged<int> onChanged;

  const _DriveThreadTile({
    required this.drive,
    required this.value,
    required this.onChanged,
  });

  int get _max => drive == DriveType.quark ? 128 : 64;

  List<int> get _options {
    final opts = <int>[...[1, 2, 4, 8, 16, 32]];
    if (_max >= 64 && !opts.contains(64)) opts.add(64);
    if (_max >= 128) opts.add(128);
    if (!opts.contains(value)) opts.add(value);
    opts.sort();
    return opts;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.cable_rounded, color: AppColors.of(context).accent),
      title: Text(drive.label),
      subtitle: Text('$value 线程${drive == DriveType.quark ? ' · 最大 128' : ''}'),
      trailing: Icon(Icons.edit_rounded,
          color: AppColors.of(context).textSecondary, size: 18),
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('${drive.label} · 下载线程'),
            children: [
              for (final n in _options)
                SimpleDialogOption(
                  onPressed: () {
                    onChanged(n);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Row(
                    children: [
                      Icon(
                        n == value
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: n == value
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
      },
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
  BaiduAccelQuota? _quota;
  bool _quotaLoading = false;

  @override
  void didUpdateWidget(covariant _InterfaceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从「未开启 → 开启」时刷新一次剩余额度
    if (!oldWidget.enabled && widget.enabled) _loadQuota();
  }

  void _toggleExpand() {
    setState(() => _expanded = !_expanded);
    if (_expanded && widget.enabled) _loadQuota();
  }

  Future<void> _loadQuota() async {
    if (_quotaLoading) return;
    setState(() => _quotaLoading = true);
    BaiduAccelQuota? q;
    try {
      q = await BaiduAccelService.I.getQuota();
    } catch (_) {
      q = null;
    }
    if (!mounted) return;
    setState(() {
      _quota = q;
      _quotaLoading = false;
    });
  }

  /// 剩余流量 & 剩余次数展示。仅在接口开启时展示数据；加载中/失败给出提示。
  Widget _buildQuotaRow() {
    final color = AppColors.of(context).textSecondary;
    if (_quotaLoading) {
      return Text('正在查询剩余额度…',
          style: TextStyle(fontSize: 12, color: color));
    }
    final q = _quota;
    if (q == null) {
      return Text('剩余额度查询失败',
          style: TextStyle(fontSize: 12, color: AppColors.of(context).red));
    }
    return Row(
      children: [
        Icon(Icons.data_usage_rounded,
            size: 16, color: AppColors.of(context).accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '剩余流量 ${formatBytes(q.size)}  ·  剩余次数 ${q.count}',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
      ],
    );
  }

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
      AppMessenger.of(context).showSnackBar(const SnackBar(
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
                  Text('说明：下载百度网盘文件前，会先对该文件创建私密分享链接，再由该接口解析出加速直链下载；过程中会弹出步骤提示。该接口需要填写解析密码才能使用。',
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
                  const SizedBox(height: 10),
                  _buildQuotaRow(),
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