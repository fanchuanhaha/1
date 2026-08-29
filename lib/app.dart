import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/gopeed/gopeed_boot.dart';
import 'pages/downloads/downloads_page.dart';
import 'pages/drive/drive_list_page.dart';
import 'pages/drive/drive_page.dart';
import 'pages/me/me_page.dart';
import 'pages/parse/parse_page.dart';
import 'pages/uploads/uploads_page.dart';
import 'state/app_state.dart';
import 'state/download_manager.dart';
import 'theme/app_theme.dart';
import 'utils/app_logger.dart';
import 'utils/permission.dart';

class QuarkLiteApp extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;

  const QuarkLiteApp({super.key, this.navigatorKey});

  @override
  State<QuarkLiteApp> createState() => _QuarkLiteAppState();
}

class _QuarkLiteAppState extends State<QuarkLiteApp> {
  bool _ready = false;
  String? _bootError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await AppState.I.init();
    } catch (e) {
      _bootError = e.toString();
      AppLogger.I.e('app', 'AppState 初始化失败: $e');
    }
    // 引擎后台异步启动，不阻塞界面（失败时下载页/添加任务时会自动重试）
    unawaited(_bootEngine());
    DownloadManager.I.startPolling();
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  Future<void> _bootEngine() async {
    try {
      await GopeedEngine.start();
      final client = GopeedEngine.client;
      final cfg = await client.getConfig();
      final dir = await AppState.I.effectiveDownloadDir();
      if (cfg['downloadDir']?.toString().isEmpty ?? true) {
        await client.updateConfig(
          downloadDir: dir,
          maxRunning: 3,
          connections: AppState.I.connections,
        );
      }
    } catch (e) {
      AppLogger.I.e('app', '后台启动引擎失败: $e');
      // 引擎启动失败不阻塞应用：添加下载任务时会自动尝试拉起
    }
  }

  @override
  void dispose() {
    DownloadManager.I.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        return MaterialApp(
          title: 'Quarklite',
          debugShowCheckedModeBanner: false,
          navigatorKey: widget.navigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _resolveThemeMode(AppState.I.themeMode),
          home: _ready ? const RootPage() : _BootView(error: _bootError),
        );
      },
    );
  }

  ThemeMode _resolveThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }
}

class _BootView extends StatelessWidget {
  final String? error;

  const _BootView({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: AppColors.of(context).red, size: 48),
                  const SizedBox(height: 16),
                  const Text('下载引擎启动失败', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.of(context).textSecondary,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  static const _pages = [
    ParsePage(),
    DriveListPage(),
    DownloadsPage(),
    UploadsPage(),
    MePage(),
  ];

  @override
  void initState() {
    super.initState();
    // 进入应用即申请必要的系统能力，避免用到时才提示：
    // 1) 所有文件访问权限（存储）
    // 2) 忽略电池优化 / 允许后台运行（保证后台持续下载不被系统杀）
    // 已授权时对应弹窗静默跳过，仅未授权时引导去系统设置。
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_grantStartupPermissions());
      });
    }
  }

  Future<void> _grantStartupPermissions() async {
    await ensureStoragePermission(context);
    if (!mounted) return;
    await _ensureIgnoreBattery(context);
  }

  /// 未开启「忽略电池优化」时弹窗引导，用户拒绝不阻塞使用（仅提示一次）
  Future<void> _ensureIgnoreBattery(BuildContext context) async {
    final app = AppState.I;
    if (await app.canIgnoreBattery()) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保持后台运行'),
        content: const Text('建议允许「忽略电池优化」，否则锁屏一段时间后系统可能终止下载进程，任务会中断。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              app.requestIgnoreBattery();
            },
            child: const Text('去开启'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppState.I.tabIndex,
      builder: (context, index, _) {
        return Scaffold(
          body: IndexedStack(index: index, children: _pages),
          bottomNavigationBar: _BottomBar(
            index: index,
            onTap: (i) => AppState.I.tabIndex.value = i,
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.link_rounded, '解析'),
      (Icons.folder_rounded, '网盘'),
      (Icons.download_rounded, '下载'),
      (Icons.cloud_upload_outlined, '上传'),
      (Icons.person_outline_rounded, '我的'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFF12121A),
        border:
            Border(top: BorderSide(color: AppColors.of(context).divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final selected = i == index;
            final color = selected
                ? AppColors.of(context).accent
                : AppColors.of(context).textSecondary;
            return Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.of(context).accentDeep,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(items[i].$1,
                              size: 22, color: AppColors.of(context).accent),
                        )
                      else
                        Icon(items[i].$1, size: 22, color: color),
                      const SizedBox(height: 3),
                      Text(
                        items[i].$2,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
