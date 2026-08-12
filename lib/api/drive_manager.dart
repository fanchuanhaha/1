import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ali_client.dart';
import 'base_drive.dart';
import 'baidu_client.dart';
import 'drive_type.dart';
import 'guangya_client.dart';
import 'pan123_client.dart';
import 'pikpak_client.dart';
import 'quark_client.dart';
import 'quark_models.dart';
import 'tianyi_client.dart';
import 'uc_client.dart';
import 'weiyun_client.dart';
import 'xunlei_client.dart';
import 'yidong_client.dart';
import 'lanzou_client.dart';

/// 网盘驱动管理器，统一管理所有网盘登录状态
class DriveManager extends ChangeNotifier {
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static DriveManager? _instance;
  static DriveManager get I => _instance ??= DriveManager._();

  DriveManager._();

  /// 夸克客户端（保留原有实现）
  final QuarkClient quark = QuarkClient();

  /// 各网盘驱动器实例
  final Map<DriveType, BaseDrive> _drives = {};

  /// 当前活跃的网盘类型
  DriveType _activeDrive = DriveType.quark;
  DriveType get activeDrive => _activeDrive;
  set activeDrive(DriveType t) {
    _activeDrive = t;
    notifyListeners();
  }

  /// 当前活跃驱动器
  QuarkClient get activeQuark => quark;

  /// 用户信息（夸克）
  QuarkUserInfo? user;
  String? loginError;
  bool loading = false;

  bool get isLoggedIn => user != null;

  /// 初始化所有驱动器
  Future<void> init() async {
    _drives[DriveType.ali] = AliClient();
    _drives[DriveType.baidu] = BaiduClient();
    _drives[DriveType.pikpak] = PikPakClient();
    _drives[DriveType.tianyi] = TianyiClient();
    _drives[DriveType.uc] = UcClient();
    _drives[DriveType.weiyun] = WeiyunClient();
    _drives[DriveType.xunlei] = XunleiClient();
    _drives[DriveType.pan123] = Pan123Client();
    _drives[DriveType.yidong] = YiDongClient();
    _drives[DriveType.guangya] = GuangyaClient();
    _drives[DriveType.lanzou] = LanzouClient();

    // 初始化各驱动器
    for (final d in _drives.values) {
      try {
        await d.init();
      } catch (_) {}
    }

    // 初始化夸克
    final cookie = await _secure.read(key: 'quark_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      quark.setCookie(cookie);
      quark.startSessionRefresher();
      await refreshUser();
    }
  }

  /// 获取指定类型的驱动器实例
  BaseDrive? getDrive(DriveType type) {
    if (type == DriveType.quark) {
      return null; // 夸克使用 QuarkClient
    }
    return _drives[type];
  }

  /// 获取当前活跃驱动器
  QuarkClient get currentClient => quark;

  /// 检测 URL 所属网盘类型
  static DriveType detectDriveType(String url) {
    return DriveType.detectFromUrl(url);
  }

  /// 解析分享链接（夸克）
  static ({String pwdId, String passcode}) parseShareUrl(String url) {
    return QuarkClient.parseShareUrl(url);
  }

  /// 登录夸克
  Future<String?> login(String cookie) async {
    try {
      quark.setCookie(cookie);
      final info = await quark.getUserInfo();
      user = info;
      loginError = null;
      quark.startSessionRefresher();
      await _secure.write(key: 'quark_cookie', value: quark.cookie);
      notifyListeners();
      return null;
    } catch (e) {
      quark.setCookie('');
      return e.toString();
    }
  }

  Future<void> refreshUser() async {
    loading = true;
    notifyListeners();
    try {
      user = await quark.getUserInfo();
      loginError = null;
    } catch (e) {
      loginError = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    quark.setCookie('');
    user = null;
    await _secure.delete(key: 'quark_cookie');
    notifyListeners();
  }

  @override
  void dispose() {
    quark.dispose();
    for (final d in _drives.values) {
      d.dispose();
    }
    super.dispose();
  }
}

/// 登录凭证
class DriveCredential {
  final DriveType driveType;
  final String? cookie;
  final String? token;
  final String? refreshToken;
  final String? username;
  final String? password;
  final String? smsCode;

  DriveCredential({
    required this.driveType,
    this.cookie,
    this.token,
    this.refreshToken,
    this.username,
    this.password,
    this.smsCode,
  });
}