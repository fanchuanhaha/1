import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../api/base_drive.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../login/login_page.dart';
import 'drive_files_page.dart';
import 'drive_page.dart' as old_drive;

/// 网盘列表页面：以竖向列表展示所有已注册的网盘驱动器，
/// 每行一个，左侧图标+名称、名称下方剩余容量，右侧菜单按钮（退出登录/查看Cookie）。
class DriveListPage extends StatefulWidget {
  const DriveListPage({super.key});

  @override
  State<DriveListPage> createState() => _DriveListPageState();
}

class _DriveListPageState extends State<DriveListPage> {
  /// 获取指定网盘类型的登录状态
  bool _hasLogin(DriveType type) {
    if (type == DriveType.quark) {
      return DriveManager.I.quark.hasLogin;
    }
    final drive = DriveManager.I.getDrive(type);
    return drive?.hasLogin ?? false;
  }

  /// 获取指定网盘类型的用户昵称
  String? _nickname(DriveType type) {
    if (type == DriveType.quark) {
      return DriveManager.I.user?.nickname;
    }
    final drive = DriveManager.I.getDrive(type);
    return drive?.userInfo?.nickname;
  }

  /// 获取指定网盘类型的驱动器实例（BaseDrive），夸克返回 null
  BaseDrive? _getDrive(DriveType type) {
    if (type == DriveType.quark) return null;
    return DriveManager.I.getDrive(type);
  }

  /// 容量信息（参考APK样式：已用 X / 总 Y）及使用比例
  /// 返回 null 表示当前网盘不提供容量数据
  ({String text, double fraction})? _capacityInfo(DriveType type) {
    int used = 0;
    int total = 0;
    if (type == DriveType.quark) {
      final user = DriveManager.I.user;
      if (user != null) {
        used = user.usedSpace;
        total = user.totalSpace;
      }
    } else {
      // 百度等其它网盘：从 DriveUserInfo 读取 totalSpace/usedSpace
      final drive = _getDrive(type);
      final info = drive?.userInfo;
      if (info != null) {
        used = info.usedSpace;
        total = info.totalSpace;
      }
    }
    if (total <= 0) return null;
    final usedClamped = used < 0 ? 0 : used;
    final fraction = (usedClamped / total).clamp(0.0, 1.0);
    return (
      text: '已用 ${formatBytes(usedClamped)} / 总 ${formatBytes(total)}',
      fraction: fraction,
    );
  }

  void _onTapDrive(DriveType type) {
    final loggedIn = _hasLogin(type);
    if (!loggedIn) {
      // 点击未登录网盘 → 直接跳转到该网盘的登录页面
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LoginPage(initialDrive: type),
        ),
      );
      return;
    }

    if (type == DriveType.quark) {
      // 夸克使用原有的 DrivePage（全功能文件浏览）
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const old_drive.DrivePage(),
        ),
      );
    } else {
      // 其他网盘使用通用文件浏览
      final drive = _getDrive(type);
      if (drive != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriveFilesPage(
              drive: drive,
              driveName: type.label,
            ),
          ),
        );
      }
    }
  }

  /// 查看某网盘的登录凭证（Cookie）
  void _viewCookie(DriveType type) {
    final cookie = DriveManager.I.cookieOf(type);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${type.label} Cookie'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              (cookie == null || cookie.isEmpty) ? '（未登录，无 Cookie）' : cookie,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          if (cookie != null && cookie.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _copyCookie(cookie);
              },
              child: const Text('复制'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 复制 Cookie 到剪贴板
  Future<void> _copyCookie(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cookie 已复制')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('复制失败')),
        );
      }
    }
  }

  /// 退出登录（带确认）
  Future<void> _logout(DriveType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出登录'),
        content: Text('确定要退出 ${type.label} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '退出',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await DriveManager.I.logoutOf(type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已退出 ${type.label}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, DriveManager.I]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            title: const Text('我的网盘'),
          ),
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: DriveType.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final type = DriveType.values[index];
              final loggedIn = _hasLogin(type);
              final nickname = _nickname(type);
              return _buildDriveRow(type, loggedIn, nickname);
            },
          ),
        );
      },
    );
  }

  Widget _buildDriveRow(DriveType type, bool loggedIn, String? nickname) {
    final capInfo = _capacityInfo(type);
    final capacity = capInfo?.text ?? '';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onTapDrive(type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 左侧图标
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  type.iconAsset,
                  width: 44,
                  height: 44,
                  errorBuilder: (_, __, ___) => Container(
                    width: 44,
                    height: 44,
                    color: AppColors.cardLight,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.cloud_rounded,
                      size: 26,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // 中部：名称 + 下方剩余容量
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            type.label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 登录状态小标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: loggedIn
                                ? AppColors.green.withOpacity(0.15)
                                : AppColors.cardLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            loggedIn ? '已登录' : '未登录',
                            style: TextStyle(
                              color: loggedIn
                                  ? AppColors.green
                                  : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // 下方：容量（已用 X / 总 Y，参考APK样式）；未登录或无容量时显示昵称/占位
                    Text(
                      loggedIn &&
                              (capacity.isNotEmpty ||
                                  (nickname != null && nickname.isNotEmpty))
                          ? (capacity.isNotEmpty
                              ? capacity
                              : (nickname ?? ''))
                          : '剩余容量: --',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 容量使用进度条（登录且有容量数据时显示）
                    if (loggedIn && capInfo != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: capInfo.fraction,
                          minHeight: 5,
                          backgroundColor: AppColors.cardLight,
                          valueColor: AlwaysStoppedAnimation(
                            capInfo.fraction >= 0.9
                                ? Colors.orangeAccent
                                : AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 右侧：菜单按钮
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textSecondary,
                ),
                color: AppColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (value) {
                  if (value == 'cookie') {
                    _viewCookie(type);
                  } else if (value == 'logout') {
                    _logout(type);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'cookie',
                    child: Row(
                      children: [
                        Icon(Icons.key_rounded, size: 18, color: AppColors.textPrimary),
                        SizedBox(width: 10),
                        Text('查看Cookie'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                        SizedBox(width: 10),
                        Text('退出登录', style: TextStyle(color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}