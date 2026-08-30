import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/drive_manager.dart';
import '../api/drive_type.dart';
import '../api/quark_client.dart';
import '../api/quark_models.dart';
import '../utils/app_logger.dart';

class AppState extends ChangeNotifier {
  static const _sysChannel = MethodChannel('quarklite.com/system');
  static const _kDownloadDir = 'download_dir';
  static const _kConnections = 'connections';
  static const _kCloseAction = 'window_close_action';
  static const _kThemeMode = 'theme_mode';
  static const _kUploadParallelism = 'upload_parallelism';

  // ---- 第三方接口配置（「野鸡百度加速」等，预留多接口扩展） ----
  static const _kBaiduAccelEnabled = 'baidu_accel_enabled';
  static const _kBaiduAccelPassword = 'baidu_accel_password';

  static AppState? _instance;
  static AppState get I => _instance ??= AppState._();

  AppState._();

  /// 网盘驱动管理器
  final DriveManager driveManager = DriveManager.I;

  /// 设备支持的 CPU 架构（Android ABI 列表，如 [arm64-v8a]）；非 Android 返回空
  Future<List<String>> getSupportedAbis() async {
    try {
      final list =
          await _sysChannel.invokeListMethod<String>('getSupportedAbis');
      return list ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// 用系统方式打开本地文件（交由系统弹出「用哪个应用打开」选择器）。
  /// 返回是否成功拉起某个应用。
  Future<bool> openDownloadedFile(String path) async {
    try {
      final ok =
          await _sysChannel.invokeMethod<bool>('openFile', {'path': path});
      AppLogger.I.i('open_file',
          'openDownloadedFile 结果 ok=${ok ?? false} path=$path');
      return ok ?? false;
    } catch (e) {
      AppLogger.I.e('open_file', 'openDownloadedFile 异常 path=$path err=$e');
      return false;
    }
  }

  /// 夸克客户端（兼容旧代码）
  QuarkClient get quark => driveManager.quark;

  /// 当前活跃的网盘类型
  DriveType get activeDrive => driveManager.activeDrive;
  set activeDrive(DriveType t) => driveManager.activeDrive = t;

  /// 用户信息
  QuarkUserInfo? get user => driveManager.user;
  String? get loginError => driveManager.loginError;
  bool get loading => driveManager.loading;
  bool get isLoggedIn => driveManager.isLoggedIn;

  /// 底部导航当前 tab（0解析 / 1网盘 / 2下载 / 3我的），供全局跳转（如下载提示的「查看」）
  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  final _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String downloadDir = '';
  int connections = 16;
  String closeAction = 'ask_once';
  String themeMode = 'dark';

  /// 同时上传任务数（默认 1：一次一个文件，减少接口限流与内存占用）
  int uploadParallelism = 1;

  /// 是否开启「野鸡百度加速」接口
  bool baiduAccelEnabled = false;

  /// 「野鸡百度加速」接口的解析密码（站点公告提供的解析密码）
  String baiduAccelPassword = '';

  /// 是否应使用百度加速接口下载百度网盘文件
  bool get isBaiduAccelOn =>
      baiduAccelEnabled && driveManager.getDrive(DriveType.baidu)?.hasLogin == true;

  Timer? _sessionTimer;

  Future<void> init() async {
    _loadSettings();
    await driveManager.init();
  }

  void _loadSettings() {
    SharedPreferences.getInstance().then((prefs) {
      downloadDir =
          prefs.getString(_kDownloadDir) ?? '/storage/emulated/0/Download/Quarklite';
      connections = prefs.getInt(_kConnections) ?? 16;
      closeAction = prefs.getString(_kCloseAction) ?? 'ask_once';
      themeMode = prefs.getString(_kThemeMode) ?? 'dark';
      uploadParallelism = prefs.getInt(_kUploadParallelism) ?? 1;
      baiduAccelEnabled = prefs.getBool(_kBaiduAccelEnabled) ?? false;
      baiduAccelPassword = prefs.getString(_kBaiduAccelPassword) ?? '';
      notifyListeners();
    });
  }

  Future<void> refreshUser() => driveManager.refreshUser();

  /// 登录：设置 cookie 并验证
  Future<String?> login(String cookie) => driveManager.login(cookie);

  Future<void> logout() => driveManager.logout();

  Future<void> setDownloadDir(String dir) async {
    downloadDir = dir;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDir, dir);
    notifyListeners();
  }

  Future<void> setConnections(int n) async {
    connections = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kConnections, n);
    notifyListeners();
  }

  Future<void> setCloseAction(String action) async {
    closeAction = action;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCloseAction, action);
    notifyListeners();
  }

  /// 主题模式：'dark' / 'light' / 'system'
  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode);
    notifyListeners();
  }

  /// 设置同时上传任务数（持久化；立即生效由 UploadManager 下一次 kick 读取）
  Future<void> setUploadParallelism(int n) async {
    uploadParallelism = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUploadParallelism, n);
    notifyListeners();
  }

  /// 设置是否开启「野鸡百度加速」接口
  Future<void> setBaiduAccelEnabled(bool on) async {
    baiduAccelEnabled = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBaiduAccelEnabled, on);
    notifyListeners();
  }

  /// 设置「野鸡百度加速」接口的解析密码
  Future<void> setBaiduAccelPassword(String pwd) async {
    baiduAccelPassword = pwd.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaiduAccelPassword, baiduAccelPassword);
    notifyListeners();
  }

  /// 当前可用的下载目录（无存储权限时回退到应用专属目录）
  Future<String> effectiveDownloadDir() async {
    if (!kIsWeb && !Platform.isAndroid && !Platform.isIOS) {
      // Windows / macOS / Linux：直接用系统文档目录
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}/Quarklite';
    }
    final canWrite = await canWriteDownload();
    if (canWrite && downloadDir.isNotEmpty) return downloadDir;
    final ext = await getExternalStorageDirectory();
    return '${ext?.path ?? (await getApplicationDocumentsDirectory()).path}/downloads';
  }

  Future<bool> canWriteDownload() async {
    try {
      return await _sysChannel.invokeMethod<bool>('canWriteDownload') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAllFilesAccess() async {
    try {
      await _sysChannel.invokeMethod('openAllFilesAccess');
    } catch (_) {}
  }

  /// 是否已允许忽略电池优化（后台下载不被系统终止）
  Future<bool> canIgnoreBattery() async {
    if (!kIsWeb && !Platform.isAndroid) return true;
    try {
      return await _sysChannel.invokeMethod<bool>('canIgnoreBattery') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 引导开启「忽略电池优化 / 允许后台运行」
  Future<void> requestIgnoreBattery() async {
    if (!kIsWeb && !Platform.isAndroid) return;
    try {
      await _sysChannel.invokeMethod('requestIgnoreBattery');
    } catch (_) {}
  }

  @override
  void dispose() {
    driveManager.dispose();
    _sessionTimer?.cancel();
    super.dispose();
  }
}