import 'package:flutter/material.dart';

import '../api/quark_client.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// 夸克图片/缩略图加载所需的请求头（缩略图 URL 带签名，需携带登录 Cookie）
Map<String, String> quarkImageHeaders() {
  return {
    if (AppState.I.quark.cookie.isNotEmpty) 'Cookie': AppState.I.quark.cookie,
    'Referer': 'https://pan.quark.cn/',
    'User-Agent': QuarkClient.uaPc,
  };
}

/// 检查存储权限，未授权时弹窗引导去系统设置；返回是否已可用
Future<bool> ensureStoragePermission(BuildContext context) async {
  final app = AppState.I;
  if (await app.canWriteDownload()) return true;
  if (!context.mounted) return false;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('需要存储权限'),
      content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            app.openAllFilesAccess();
          },
          child: const Text('去授权'),
        ),
      ],
    ),
  );
  return false;
}

void toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  AppMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));
}

/// 下载成功提示：SnackBar 附带「查看」按钮，点击跳转到下载管理页（底部第 3 个 tab）。
/// 优先弹回根导航再切 tab，确保从分享/文件浏览等二级页面跳转后下载页可见。
void showDownloadAddedToast(BuildContext context, String msg) {
  if (!context.mounted) return;
  AppMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '查看',
          textColor: AppColors.of(context).accent,
          onPressed: () {
            try {
              Navigator.of(context, rootNavigator: true)
                  .popUntil((route) => route.isFirst);
            } catch (_) {}
            AppState.I.tabIndex.value = 2;
          },
        ),
      ),
    );
}

/// 上传入队提示：把「上传」页做成可点击的超链接，点击后跳转到任务页的上传列表。
void showUploadAddedToast(BuildContext context, int count) {
  if (!context.mounted) return;
  final colors = AppColors.of(context);
  final normalStyle = TextStyle(color: colors.textPrimary, fontSize: 14);

  void go() {
    try {
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    } catch (_) {}
    // 先切到任务页的上传分段，再切换到「任务」tab。
    AppState.I.tasksSegment.value = 1;
    AppState.I.tabIndex.value = 2;
  }

  AppMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('已加入 $count 个上传任务，可在', style: normalStyle),
            GestureDetector(
              onTap: go,
              child: Text(
                '「上传」页',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.accent,
                ),
              ),
            ),
            Text('查看进度', style: normalStyle),
          ],
        ),
      ),
    );
}
