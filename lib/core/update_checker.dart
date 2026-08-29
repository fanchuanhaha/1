import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// 一条可用的新版本信息
class AppUpdate {
  final String version;
  final Uri? url;
  final String? notes;
  const AppUpdate(this.version, this.url, this.notes);
}

/// 检查 GitHub Releases 是否有新版本（移植自 ZXEB/quarklite 上游 update_checker）。
///
/// 本次发布 action 生成 tag 形如 `build-N`，因而用其中的数字 N 与本地已构建
/// 的 build 号比较大小：[kLocalBuild] 需在每次发布后随之递增。
class UpdateChecker {
  static const _repo = 'fanchuanhaha/1';
  static const _latestUrl =
      'https://api.github.com/repos/fanchuanhaha/1/releases/latest';

  /// 当前代码已发布到的最新 build 号（随发布递增）
  static const int kLocalBuild = 69;

  static const _kSkippedKey = 'update_skipped_build';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// 检查远端最新 release；有比本地更新的 build 才返回，否则返回 null。
  /// 任何异常都静默吞掉（不阻塞启动）。
  static Future<AppUpdate?> check() async {
    try {
      final resp = await _dio.get<dynamic>(
        _latestUrl,
        options: Options(headers: {
          'User-Agent': 'Quarklite-update-checker',
          'Accept': 'application/vnd.github+json',
        }),
      );
      final data = resp.data;
      if (data is! Map) return null;
      final tag = data['tag_name']?.toString() ?? '';
      final remote = _buildNum(tag);
      if (remote == null || remote <= kLocalBuild) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt(_kSkippedKey) == remote) return null;
      return AppUpdate(
        tag,
        Uri.tryParse(data['html_url']?.toString() ?? ''),
        data['body']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 启动时/手动触发检查并弹窗提示。manual=true 且无新版本时提示「已是最新」。
  static Future<void> checkAndPrompt(BuildContext context,
      {bool manual = false}) async {
    final update = await check();
    if (!context.mounted) return;
    if (update == null) {
      if (manual) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${update.version} 已发布',
                style: TextStyle(
                    color: AppColors.of(ctx).accent,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              update.notes ?? '前往 Releases 页面下载更新。',
              style: TextStyle(
                  color: AppColors.of(ctx).textSecondary,
                  fontSize: 12,
                  height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final remote = _buildNum(update.version);
              if (remote != null) {
                await prefs.setInt(_kSkippedKey, remote);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('忽略此版本'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('稍后',
                style: TextStyle(color: AppColors.of(ctx).textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              final url = update.url;
              Navigator.pop(ctx);
              if (url != null) {
                Clipboard.setData(ClipboardData(text: url.toString()));
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('下载链接已复制，请在浏览器打开')));
              }
            },
            child: const Text('复制下载链接'),
          ),
        ],
      ),
    );
  }

  static int? _buildNum(String tag) {
    final m = RegExp(r'build-?(\d+)', caseSensitive: false).firstMatch(tag) ??
        RegExp(r'(\d+)').firstMatch(tag);
    return m == null ? null : int.tryParse(m[1] ?? '');
  }
}