import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import '../state/download_service.dart';
import '../theme/app_theme.dart';

/// 一条可用的新版本信息。
///
/// 每条 release 由 CI 自动发布，tag 形如 `build-N`，附件含通用包
/// `app-release.apk` 以及分架构包 `app-{abi}-release.apk`。
/// 此处按当前设备版本号 + CPU 架构匹配出对应直链。
class AppUpdate {
  final String version;
  final String? notes;

  /// GitHub Release 页面地址
  final String? htmlUrl;

  /// 匹配当前架构的 APK 直链（可能为 null，此时回退到 htmlUrl）
  final String? directUrl;

  /// 识别的架构标签，如 arm64-v8a / x86_64 / armeabi-v7a / 通用
  final String? archLabel;

  const AppUpdate({
    required this.version,
    this.notes,
    this.htmlUrl,
    this.directUrl,
    this.archLabel,
  });
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

  /// gh-proxy 加速前缀（用于「加速下载」）
  static const _ghProxyPrefix = 'https://gh-proxy.com/';

  /// APK 直链需要的优先架构顺序（匹配当前设备已支持的 ABI）
  static const _abiOrder = ['arm64-v8a', 'x86_64', 'armeabi-v7a'];

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
  ));

  /// 检查远端最新 release；有比本地更新的 build 且存在可用直链时才返回。
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

      final abis = await AppState.I.getSupportedAbis();
      final assets = (data['assets'] as List?) ?? const [];
      final directUrl = _matchApk(assets);
      return AppUpdate(
        version: tag,
        notes: data['body']?.toString(),
        htmlUrl: data['html_url']?.toString(),
        directUrl: directUrl,
        archLabel: _archLabel(abis, directUrl != null),
      );
    } catch (_) {
      return null;
    }
  }

  /// 从 release 的附件中匹配当前设备架构对应的 APK 直链，无匹配则回退通用包。
  static String? _matchApk(List assets) {
    final urls = <String, String>{};
    for (final a in assets) {
      if (a is! Map) continue;
      final name = a['name']?.toString() ?? '';
      final url = a['browser_download_url']?.toString();
      if (!name.toLowerCase().endsWith('.apk') || url == null || url.isEmpty) {
        continue;
      }
      // 记录每个 ABI 对应的 URL；通用包名为 app-release.apk
      final m = RegExp(r'app-(arm64-v8a|armeabi-v7a|x86_64)-release\.apk')
          .firstMatch(name);
      if (m != null) {
        urls[m[1]!] = url;
      } else if (name == 'app-release.apk') {
        urls['universal'] = url;
      }
    }
    // 按设备 ABI 优先级挑选，命中即返回
    for (final abi in _abiOrder) {
      if (urls.containsKey(abi)) return urls[abi];
    }
    // 设备 ABI 未知/未匹配时回退通用包
    return urls['universal'];
  }

  /// 架构标签（用于在弹窗中展示「为你的架构匹配的版本」）
  static String? _archLabel(List<String> abis, bool hasApk) {
    if (abis.isEmpty) return hasApk ? '通用包' : null;
    for (final abi in _abiOrder) {
      if (abis.contains(abi)) return abi;
    }
    return hasApk ? '通用包' : null;
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
            Text(update.version,
                style: TextStyle(
                    color: AppColors.of(ctx).accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 20)),
            if (update.archLabel != null) ...[
              const SizedBox(height: 4),
              Text('当前架构 ${update.archLabel} · 已匹配对应安装包',
                  style: TextStyle(
                      color: AppColors.of(ctx).textSecondary, fontSize: 12)),
            ],
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
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消',
                style: TextStyle(color: AppColors.of(ctx).textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final url = update.directUrl ?? update.htmlUrl;
              if (url == null) return;
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              _toast(context, '下载链接已复制');
            },
            child: const Text('复制链接'),
          ),
          if (update.directUrl != null) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _startDownload(context, update.directUrl!,
                    update.version, useProxy: false);
              },
              child: const Text('下载'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _startDownload(
                    context, update.directUrl!, update.version,
                    useProxy: true);
              },
              child: const Text('加速下载'),
            ),
          ],
        ],
      ),
    );
  }

  /// 走内置下载引擎，把安装包加入「任务」进行下载。
  /// [useProxy] 为 true 时走 gh-proxy 加速。
  static Future<void> _startDownload(BuildContext root, String url,
      String version, {required bool useProxy}) async {
    final target = useProxy ? '$_ghProxyPrefix$url' : url;
    final fileName = 'quarklite-${version.replaceAll('/', '')}.apk';
    final err = await DownloadService.addDirectUrl(
      url: target,
      fileName: fileName,
      cookie: '',
      referer: '',
      userAgent: 'Quarklite/2.0 (update-download)',
      connections: 4,
    );
    if (!root.mounted) return;
    ScaffoldMessenger.of(root).showSnackBar(SnackBar(
        content: Text(err == null
            ? '已加入下载任务，请到「任务」页查看进度'
            : '下载失败：$err')));
  }

  static int? _buildNum(String tag) {
    final m = RegExp(r'build-?(\d+)', caseSensitive: false).firstMatch(tag) ??
        RegExp(r'(\d+)').firstMatch(tag);
    return m == null ? null : int.tryParse(m[1] ?? '');
  }

  static void _toast(BuildContext context, String msg) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}