import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 「自定义下载」弹窗：手动添加下载链接。
///
/// 参考 APK 的「导入下载链接」界面：支持多行 URL（每行一个，可用 | 指定文件名），
/// 并带可折叠的高级设置（请求头 Cookie/UA/Referer + 文件名覆盖 + 路径 + 线程数）。
class ImportDownloadSheet extends StatefulWidget {
  const ImportDownloadSheet({super.key});

  /// 弹出该弹窗，返回 null=取消，否则为导入结果文案
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ImportDownloadSheet(),
    );
  }

  @override
  State<ImportDownloadSheet> createState() => _ImportDownloadSheetState();
}

class _ImportDownloadSheetState extends State<ImportDownloadSheet> {
  final _textController = TextEditingController();
  final _cookieController = TextEditingController();
  final _uaController = TextEditingController();
  final _refererController = TextEditingController();
  final _nameController = TextEditingController();
  final _pathController = TextEditingController();
  final _threadController = TextEditingController();

  bool _advancedVisible = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // 默认路径与线程数取全局设置
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dir = await AppState.I.effectiveDownloadDir();
      if (!mounted) return;
      _pathController.text = dir;
      _threadController.text = '${AppState.I.connections}';
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _cookieController.dispose();
    _uaController.dispose();
    _refererController.dispose();
    _nameController.dispose();
    _pathController.dispose();
    _threadController.dispose();
    super.dispose();
  }

  /// 解析多行输入为 [url, nullableName] 列表
  List<(String, String?)> _parseLines() {
    final lines = _textController.text
        .trim()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final result = <(String, String?)>[];
    for (final line in lines) {
      // 用 | 分隔 URL 与文件名
      final idx = line.lastIndexOf('|');
      if (idx > 0) {
        final url = line.substring(0, idx).trim();
        final name = line.substring(idx + 1).trim();
        if (url.isNotEmpty) result.add((url, name.isEmpty ? null : name));
      } else {
        result.add((line, null));
      }
    }
    return result;
  }

  Future<void> _import() async {
    if (_importing) return;
    final entries = _parseLines();
    if (entries.isEmpty) {
      _toast('请先输入至少一个下载链接');
      return;
    }

    final overrideName = _nameController.text.trim();
    // 完全自定义请求头：仅在用户填了任一项时使用自定义 header，否则不附加
    final cookie = _cookieController.text.trim();
    final ua = _uaController.text.trim();
    final referer = _refererController.text.trim();
    final useCustomHeader = cookie.isNotEmpty || ua.isNotEmpty || referer.isNotEmpty;
    Map<String, String>? headers;
    if (useCustomHeader) {
      headers = {
        if (cookie.isNotEmpty) 'Cookie': cookie,
        if (ua.isNotEmpty) 'User-Agent': ua,
        if (referer.isNotEmpty) 'Referer': referer,
      };
    }
    final path = _pathController.text.trim();
    final threads = int.tryParse(_threadController.text.trim()) ?? AppState.I.connections;

    setState(() => _importing = true);
    var ok = 0;
    final errors = <String>[];
    for (final (url, lineName) in entries) {
      final name = overrideName.isNotEmpty
          ? overrideName
          : (lineName?.isNotEmpty == true
              ? lineName!
              : DownloadService.inferFileName(url));
      final err = await DownloadService.addDirectUrl(
        url: url,
        fileName: name,
        cookie: '',
        path: path.isNotEmpty ? path : null,
        extraHeaders: headers,
        connections: threads,
      );
      if (err == null) {
        ok++;
      } else {
        errors.add('$name: $err');
      }
    }
    if (!mounted) return;
    Navigator.pop(context, ok > 0 ? '已添加 $ok 个下载任务' : '导入失败');
  }

  Widget _field(TextEditingController c, String hint,
      {int maxLines = 1, bool numeric = false, double height = 0}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(color: AppColors.of(context).textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: AppColors.of(context).textSecondary, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: AppColors.of(context).cardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('导入下载链接',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('每行一个 URL，可用 | 指定文件名',
                  style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            _field(_textController, 'https://example.com/file.apk\nhttps://example.com/a.zip | 自定义名.zip',
                maxLines: 6),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _advancedVisible = !_advancedVisible),
              child: Row(
                children: [
                  Text(_advancedVisible ? '收起高级设置' : '展开高级设置',
                      style: TextStyle(
                          color: AppColors.of(context).accent, fontSize: 13)),
                  Icon(
                    _advancedVisible
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.of(context).accent,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_advancedVisible) ...[
              const SizedBox(height: 12),
              _sectionTitle('请求头（本批次，可选）'),
              const SizedBox(height: 8),
              _field(_cookieController, 'Cookie'),
              const SizedBox(height: 8),
              _field(_uaController, 'User-Agent'),
              const SizedBox(height: 8),
              _field(_refererController, 'Referer'),
              const SizedBox(height: 12),
              _sectionTitle('本次任务覆盖'),
              const SizedBox(height: 8),
              _field(_nameController, '统一文件名（可选）'),
              const SizedBox(height: 8),
              _field(_pathController, '下载目录（默认使用全局目录）'),
              const SizedBox(height: 8),
              _field(_threadController, '线程数（默认使用全局连接数）', numeric: true),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _importing
                        ? null
                        : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text('取消',
                        style: TextStyle(color: AppColors.of(context).textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _importing ? null : _import,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: _importing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('导入'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: TextStyle(
          color: AppColors.of(context).textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600));

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}