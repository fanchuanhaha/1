import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.accent),
            title: const Text('下载目录'),
            subtitle: Text(app.downloadDir,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editDownloadDir(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading:
                const Icon(Icons.speed_rounded, color: AppColors.accent),
            title: const Text('下载连接数'),
            subtitle: Text('每个任务 ${app.connections} 线程并发下载'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => _editConnections(context, app),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            leading: const Icon(Icons.storage_rounded, color: AppColors.accent),
            title: const Text('存储权限'),
            subtitle: const Text('访问下载目录所需权限'),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary),
            onTap: () => app.openAllFilesAccess(),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        leading: const Icon(Icons.info_outline_rounded,
            color: AppColors.accent),
        title: const Text('关于'),
        subtitle: const Text('Quarklite v1.1.3  ·  基于 Gopeed 下载引擎'),
        onTap: () => _showAbout(context),
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
          style: const TextStyle(color: AppColors.textPrimary),
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
                        ? AppColors.accent
                        : AppColors.textSecondary,
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