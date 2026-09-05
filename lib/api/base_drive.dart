import 'dart:async';

import 'drive_type.dart';

/// 通用文件模型
class DriveFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String fileExt;
  final int updatedAt;
  final String thumbnail;
  final String previewUrl;

  DriveFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.fileExt,
    required this.updatedAt,
    this.thumbnail = '',
    this.previewUrl = '',
  });
}

/// 分享文件模型
class DriveShareFile {
  final String fid;
  final String fileName;
  final String fileType;
  final bool isDir;
  final int size;
  final String pdirFid;
  final String shareFidToken;

  /// 进入目录时用的导航 id。与 [fid] 分离：部分盘（如百度）listShare 的 dir 参数
  /// 需要文件夹自身的完整路径，而 [fid] 需保持数字 fs_id 供下载/转存。为空则用 [fid] 导航。
  final String dirId;

  DriveShareFile({
    required this.fid,
    required this.fileName,
    required this.fileType,
    required this.isDir,
    required this.size,
    required this.pdirFid,
    required this.shareFidToken,
    this.dirId = '',
  });
}

/// 下载信息
class DriveDownloadInfo {
  final String url;
  final String fileName;
  final int size;
  final String fid;

  /// 覆盖下载时使用的 User-Agent（为空则用驱动器默认 UA）。
  /// 例如百度加速直链会返回其绑定的专用 UA，必须原样带上。
  final String userAgent;

  /// 为 true 时不携带登录账号的个人 cookie 下载。
  /// 百度加速直链属于分享/匿名上下文，带个人 cookie 会被 CDN 拒签。
  final bool skipCookie;

  DriveDownloadInfo({
    required this.url,
    required this.fileName,
    required this.size,
    required this.fid,
    this.userAgent = '',
    this.skipCookie = false,
  });
}

/// 用户信息
class DriveUserInfo {
  final String nickname;
  final String avatar;
  final String userId;

  /// 总容量（字节），0 表示未返回
  final int totalSpace;

  /// 已用容量（字节）
  final int usedSpace;

  DriveUserInfo({
    required this.nickname,
    required this.avatar,
    required this.userId,
    this.totalSpace = 0,
    this.usedSpace = 0,
  });
}

/// 分享会话
class DriveShareSession {
  final String shareId;
  final String pwdId;
  final String passcode;
  String stoken;

  /// 分享来源用户 uk（百度网盘分享列目录必需）
  final int uk;

  DriveShareSession({
    required this.shareId,
    required this.pwdId,
    required this.passcode,
    required this.stoken,
    this.uk = 0,
  });
}

/// 所有网盘驱动器的抽象基类
abstract class BaseDrive {
  DriveType get type;
  String get label;

  bool get hasLogin => false;
  DriveUserInfo? get userInfo => null;

  /// 当前登录凭证（cookie/token 字符串），用于展示与持久化
  String? get loginCookie => null;

  /// 从持久化凭证恢复登录态（应尽量不发网络，失败静默）。
  /// [credential] 即 [loginCookie] 保存下来的值。
  void restoreSession(String credential) {}

  /// 初始化（加载持久化的登录凭证）
  Future<void> init();

  /// 登录
  Future<String?> login(dynamic credential);

  /// 登出
  Future<void> logout();

  /// 刷新用户信息
  Future<void> refreshUser();

  /// 获取文件列表
  Future<List<DriveFile>> listFiles(String pdirFid, {int page = 1, int size = 100});

  /// 搜索文件
  Future<List<DriveFile>> searchFiles(String keyword, {int page = 1, int size = 50});

  /// 获取下载链接
  Future<List<DriveDownloadInfo>> getDownloadInfo(List<String> fids);

  /// 解析分享链接
  static ({String pwdId, String passcode}) parseShareUrl(String url) => (pwdId: '', passcode: '');

  /// 获取分享 token
  Future<DriveShareSession> getShareToken(String pwdId, String passcode);

  /// 列出分享文件
  Future<List<DriveShareFile>> listShare(DriveShareSession session, String pdirFid, {int page = 1, int size = 50});

  /// 获取分享文件下载链接
  Future<List<DriveDownloadInfo>> getShareDownloadInfo(DriveShareSession session, List<String> fidList);

  /// 转存分享文件
  Future<void> saveShare(DriveShareSession session, List<DriveShareFile> files, String toPdirFid);

  // ──────────────────── 文件管理操作（分享 / 重命名 / 移动等） ────────────────────
  // 默认不支持；对应网盘（如百度）通过覆写实现，UI 用 [supportsFileOps] 判断是否展示。

  /// 是否支持文件管理操作（分享/重命名/移动/复制/删除）
  bool get supportsFileOps => false;

  /// 是否支持生成分享链接
  bool get supportsShare => false;

  /// 是否支持重命名
  bool get supportsRename => false;

  /// 是否支持移动
  bool get supportsMove => false;

  /// 创建分享链接，返回分享结果（链接 + 提取码）。异常或失败抛 [StateError]。
  /// [pwd] 自定义提取码（为空时由网盘默认生成）；[period] 有效期时长（各网盘自定义）。
  /// [requirePwd] 为 false 时优先生成公开分享（无提取码）；网盘不支持时回退为私密分享。
  Future<DriveShareResult> shareFiles(List<String> fids,
      {String? pwd, int? period, bool requirePwd = true}) {
    throw StateError('当前网盘不支持创建分享链接');
  }

  /// 重命名文件/文件夹，返回 null 表示成功，否则返回错误信息。
  Future<String?> renameFile(String fid, String newName) {
    return Future.value('当前网盘不支持重命名');
  }

  /// 移动文件/文件夹到目标目录，返回 null 表示成功，否则返回错误信息。
  Future<String?> moveFiles(List<String> fids, String toDirFid) {
    return Future.value('当前网盘不支持移动');
  }

  /// 复制文件/文件夹到目标目录，返回 null 表示成功，否则返回错误信息。
  Future<String?> copyFiles(List<String> fids, String toDirFid) {
    return Future.value('当前网盘不支持复制');
  }

  /// 释放资源
  void dispose();
}

/// 创建分享链接的返回结果
class DriveShareResult {
  /// 完整分享链接，如 https://pan.baidu.com/s/xxx?pwd=xxxx
  final String url;

  /// 提取码（可能为空）
  final String pwd;

  /// 分享短码（surl）
  final String surl;

  DriveShareResult({required this.url, this.pwd = '', this.surl = ''});

  bool get hasPwd => pwd.isNotEmpty;
}