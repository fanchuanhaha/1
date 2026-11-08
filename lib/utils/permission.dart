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

/// 任务提示：把文案中的「上传」「下载」渲染成可点击超链接，
/// 点击后回到根页面并切到任务页对应分段（下载=0，上传=1）。
void showTaskAddedToast(BuildContext context, String msg, {int? segment}) {
  if (!context.mounted) return;
  final colors = AppColors.of(context);
  final normalStyle = TextStyle(color: colors.textPrimary, fontSize: 14);
  final linkStyle = TextStyle(
    color: colors.accent,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: colors.accent,
  );

  void go(int seg) {
    try {
      Navigator.of(context, rootNavigator: true)
          .popUntil((route) => route.isFirst);
    } catch (_) {}
    AppState.I.tasksSegment.value = seg;
    AppState.I.tabIndex.value = 2;
  }

  final children = <Widget>[];
  final re = RegExp('(上传|下载)');
  var last = 0;
  for (final m in re.allMatches(msg)) {
    if (m.start > last) {
      children.add(Text(msg.substring(last, m.start), style: normalStyle));
    }
    final word = m.group(1)!;
    final seg = segment ?? (word == '上传' ? 1 : 0);
    children.add(GestureDetector(
      onTap: () => go(seg),
      child: Text(word, style: linkStyle),
    ));
    last = m.end;
  }
  if (last < msg.length) {
    children.add(Text(msg.substring(last), style: normalStyle));
  }
  if (children.isEmpty) {
    children.add(Text(msg, style: normalStyle));
  }

  AppMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    );
}

/// 下载入队提示：文案中的「下载」为可点击超链接，点击跳转任务页下载列表。
void showDownloadAddedToast(BuildContext context, String msg) {
  showTaskAddedToast(context, msg, segment: 0);
}

/// 上传入队提示：文案中的「上传」为可点击超链接，点击跳转任务页上传列表。
void showUploadAddedToast(BuildContext context, int count) {
  showTaskAddedToast(context, '已加入 $count 个上传任务，可在上传页查看进度',
      segment: 1);
}

