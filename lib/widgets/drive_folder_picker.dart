import 'package:flutter/material.dart';

import '../api/base_drive.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'empty_view.dart';
import 'file_icon.dart';

/// 选择网盘目标文件夹的选择器（通用，基于任意 [BaseDrive]）。
/// 从根目录逐级浏览子文件夹，点击「移动至此」返回当前目录 fid；
/// 返回 null 表示用户取消。
class DriveFolderPicker extends StatefulWidget {
  final BaseDrive drive;
  final String title;

  const DriveFolderPicker({super.key, required this.drive, this.title = '选择目标文件夹'});

  /// 弹出文件夹选择，返回选中的目录 fid（取消返回 null）。
  static Future<String?> show(
    BuildContext context, {
    required BaseDrive drive,
    String title = '选择目标文件夹',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.75,
        child: DriveFolderPicker(drive: drive, title: title),
      ),
    );
  }

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  final List<(String, String)> _crumbs = [('0', '根目录')];
  String _currentFid = '0';
  bool _loading = false;
  List<DriveFile> _dirs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.drive.listFiles(_currentFid);
      if (mounted) {
        setState(() {
          _dirs = files.where((f) => f.isDir).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  void _enterDir(DriveFile dir) {
    setState(() {
      _crumbs.add((_currentFid, dir.fileName));
      _currentFid = dir.fid;
      _dirs = [];
      _loading = true;
    });
    _load();
  }

  void _goTo(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _currentFid = _crumbs.last.$1;
      _dirs = [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded,
                    color: AppColors.of(context).textSecondary),
              ),
            ],
          ),
        ),
        // 面包屑
        SizedBox(
          height: 32,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (var i = 0; i < _crumbs.length; i++) ...[
                  if (i > 0)
                    Icon(Icons.chevron_right_rounded,
                        size: 15, color: AppColors.of(context).textSecondary),
                  InkWell(
                    onTap: () => _goTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(
                        _crumbs[i].$2,
                        style: TextStyle(
                          fontSize: 13,
                          color: i == _crumbs.length - 1
                              ? AppColors.of(context).accent
                              : AppColors.of(context).textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // 目录列表
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? EmptyView(
                      icon: Icons.cloud_off_rounded,
                      text: '加载失败',
                      subText: _error!,
                      action: OutlinedButton(
                          onPressed: _load, child: const Text('重试')),
                    )
                  : _dirs.isEmpty
                      ? const EmptyView(
                          icon: Icons.folder_open_rounded,
                          text: '当前目录没有子文件夹')
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: _dirs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final d = _dirs[i];
                            return InkWell(
                              onTap: () => _enterDir(d),
                              borderRadius: BorderRadius.circular(10),
                              child: Row(
                                children: [
                                  FileIcon(isDir: true, name: d.fileName),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(d.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: AppColors.of(context)
                                                .textPrimary,
                                            fontSize: 14)),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      color: AppColors.of(context)
                                          .textSecondary),
                                ],
                              ),
                            );
                          },
                        ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context, _currentFid),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.of(context).accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                label: const Text('选择此文件夹'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}