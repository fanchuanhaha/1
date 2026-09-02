import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 一次「分享设置」的配置结果。
class ShareConfig {
  /// 有效期原始值：0=永久、1=1天、7=7天、30=30天（各网盘自行映射）。
  final int period;

  /// 用户自定义提取码（可空，为空时由网盘自动生成）。
  final String pwd;

  /// 是否开启提取码（私密分享）。为 false 时生成公开分享、无提取码。
  final bool requirePwd;

  const ShareConfig({
    this.period = 0,
    this.pwd = '',
    this.requirePwd = true,
  });

  bool get hasCustomPwd => pwd.isNotEmpty;
}

const List<(int, String)> kSharePeriods = [
  (0, '永久'),
  (1, '1天'),
  (7, '7天'),
  (30, '30天'),
];

/// 弹出「分享设置」对话框：选择有效期 + 是否开启提取码 + 填写提取码（留空自动生成）。
/// 返回 null 表示用户取消。
Future<ShareConfig?> showShareSetupDialog(BuildContext context) async {
  var period = 0;
  var requirePwd = true;
  var pwd = '';
  final pwdCtrl = TextEditingController();
  String? pwdError;

  final cfg = await showDialog<ShareConfig>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          backgroundColor: AppColors.of(ctx).card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('分享设置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('有效期',
                  style: TextStyle(
                      color: AppColors.of(ctx).textSecondary, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: kSharePeriods.map((e) {
                  final selected = e.$1 == period;
                  return ChoiceChip(
                    label: Text(e.$2),
                    selected: selected,
                    selectedColor: AppColors.of(ctx).accentDeep,
                    backgroundColor: AppColors.of(ctx).cardLight,
                    labelStyle: TextStyle(
                      color: selected
                          ? AppColors.of(ctx).accent
                          : AppColors.of(ctx).textSecondary,
                      fontSize: 13,
                    ),
                    onSelected: (_) => setState(() => period = e.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('开启提取码',
                        style: TextStyle(
                            color: AppColors.of(ctx).textSecondary,
                            fontSize: 13)),
                  ),
                  Switch(
                    value: requirePwd,
                    activeColor: AppColors.of(ctx).accent,
                    onChanged: (_) => setState(() {
                      requirePwd = !requirePwd;
                      if (requirePwd) {
                        pwdError = null;
                      }
                    }),
                  ),
                ],
              ),
              if (requirePwd) ...[
                const SizedBox(height: 8),
                Text('提取码',
                    style: TextStyle(
                        color: AppColors.of(ctx).textSecondary, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: pwdCtrl,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.of(ctx).textPrimary),
                  decoration: InputDecoration(
                    hintText: '留空自动生成 4 位数字',
                    hintStyle:
                        TextStyle(color: AppColors.of(ctx).textSecondary),
                    counterText: '',
                    errorText: pwdError,
                    filled: true,
                    fillColor: AppColors.of(ctx).cardLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) {
                    if (pwdError != null) setState(() => pwdError = null);
                  },
                ),
              ],
              const SizedBox(height: 8),
              Text('开启提取码时为私密分享；关闭后为公开分享（夸克支持）。',
                  style: TextStyle(
                      color: AppColors.of(ctx).textSecondary, fontSize: 11)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('取消',
                  style: TextStyle(color: AppColors.of(ctx).textSecondary)),
            ),
            FilledButton(
              onPressed: () {
                final raw = pwdCtrl.text.trim();
                pwd = raw;
                if (requirePwd &&
                    raw.isNotEmpty &&
                    !RegExp(r'^\d{4}$').hasMatch(raw)) {
                  setState(() => pwdError = '提取码需为 4 位数字');
                  return;
                }
                Navigator.pop(ctx,
                    ShareConfig(period: period, pwd: pwd, requirePwd: requirePwd));
              },
              child: const Text('生成分享'),
            ),
          ],
        );
      },
    ),
  );
  pwdCtrl.dispose();
  return cfg;
}

/// 弹出分享结果对话框：展示完整链接，仅提供「取消」和「复制」按钮。
/// [pwd] 提取码（可空）。
Future<void> showShareResultDialog(
    BuildContext context, String fullUrl, String pwd) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.of(ctx).card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('分享链接已生成'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            fullUrl,
            style: TextStyle(
                color: AppColors.of(ctx).accent,
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600),
          ),
          if (pwd.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('提取码：$pwd',
                style: TextStyle(
                    color: AppColors.of(ctx).textSecondary, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('取消',
              style: TextStyle(color: AppColors.of(ctx).textSecondary)),
        ),
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: fullUrl));
            if (!ctx.mounted) return;
            Navigator.pop(ctx);
            AppMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('链接已复制')));
          },
          child: const Text('复制'),
        ),
      ],
    ),
  );
}

/// 根据 baseUrl 与提取码拼装完整分享链接（含 ?pwd= or &pwd=）。无提取码时返回原链接。
String buildShareFullUrl(String baseUrl, String pwd) {
  if (pwd.isEmpty) return baseUrl;
  final sep = baseUrl.contains('?') ? '&' : '?';
  return '${baseUrl}${sep}pwd=${pwd}';
}