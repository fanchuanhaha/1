import 'package:flutter/material.dart';

import '../../api/drive_type.dart';
import '../../api/drive_manager.dart';
import '../../api/base_drive.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../login/login_page.dart';
import 'drive_files_page.dart';
import 'drive_page.dart' as old_drive;

/// 网盘列表页面：以 2 列网格展示所有已注册的网盘驱动器，
/// 显示登录状态、用户昵称和容量信息。
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
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: DriveType.values.length,
              itemBuilder: (context, index) {
                final type = DriveType.values[index];
                final loggedIn = _hasLogin(type);
                final nickname = _nickname(type);
                return _buildDriveCard(type, loggedIn, nickname);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriveCard(DriveType type, bool loggedIn, String? nickname) {
    return GestureDetector(
      onTap: () => _onTapDrive(type),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部：图标 + 登录状态
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    type.iconAsset,
                    width: 36,
                    height: 36,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.cloud_rounded,
                      size: 36,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: loggedIn
                        ? AppColors.green.withOpacity(0.15)
                        : AppColors.cardLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    loggedIn ? '已登录' : '未登录',
                    style: TextStyle(
                      color: loggedIn ? AppColors.green : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 网盘名称
            Text(
              type.label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            // 用户昵称（已登录时显示）
            if (loggedIn && nickname != null && nickname.isNotEmpty)
              Text(
                nickname,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (loggedIn && (nickname == null || nickname.isEmpty))
              const Text(
                '已登录',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            const Spacer(),
            // 容量信息
            const Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 4),
                Text(
                  '容量: --',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}