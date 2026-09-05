import 'package:flutter/material.dart';

import '../../api/base_drive.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/permission.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

/// 通用分享文件浏览页面，适用于任何实现了 [BaseDrive] 的网盘
class ShareFilesPage extends StatefulWidget {
  final BaseDrive drive;
  final DriveShareSession session;
  final List<DriveShareFile> initialFiles;
  final String initialName;
  final String cookie;

  const ShareFilesPage({
    super.key,
    required this.drive,
    required this.session,
    required this.initialFiles,
    required this.initialName,
    this.cookie = '',
  });

  @override
  State<ShareFilesPage> createState() => _ShareFilesPageState();
}

class _ShareFilesPageState extends State<ShareFilesPage> {
  late List<DriveShareFile> _files;
  String _dirFid = '0';
  final List<String> _stack = [];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _files = widget.initialFiles;
  }

  Future<void> _openDir(DriveShareFile dir) async {
    // 部分盘（如百度）进目录需要文件夹自身路径，存于 dirId；其余盘沿用 fid。
    final target = dir.dirId.isNotEmpty ? dir.dirId : dir.fid;
    setState(() {
      _loading = true;
      _error = null;
      _stack.add(_dirFid);
      _dirFid = target;
    });
    try {
      final files = await widget.drive.listShare(widget.session, _dirFid);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
          _stack.removeLast();
          _dirFid = _stack.isEmpty ? '0' : _stack.last;
        });
      }
    }
  }

  void _back() {
    if (_stack.isEmpty) return;
    setState(() {
      _dirFid = _stack.removeLast();
      _files = widget.initialFiles;
      _error = null;
    });
    _reloadCurrent();
  }

  Future<void> _reloadCurrent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.drive.listShare(widget.session, _dirFid);
      if (mounted) {
        setState(() {
          _files = files;
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

  // ---------------- 多选 ----------------

  void _enterSelectMode(DriveShareFile file) {
    setState(() {
      _selectMode = true;
      if (!file.isDir) _selected.add(file.fid);
    });
  }

  void _toggleSelect(DriveShareFile file) {
    if (file.isDir) return;
    setState(() {
      if (!_selected.remove(file.fid)) {
        _selected.add(file.fid);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  List<DriveShareFile> _selectedFiles() {
    return _files.where((f) => _selected.contains(f.fid)).toList();
  }

  void _selectAllFiles() {
    final fileIds = _files.where((f) => !f.isDir).map((f) => f.fid).toSet();
    setState(() {
      if (_selected.length == fileIds.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(fileIds);
      }
    });
  }

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final infos = await widget.drive
          .getShareDownloadInfo(widget.session, _selected.toList());
      var added = 0;
      for (final info in infos) {
        if (info.url.isEmpty) continue;
        final err = await DownloadService.addDirectUrl(
          url: info.url,
          fileName: info.fileName,
          cookie: widget.cookie,
          connections: 16,
        );
        if (err == null) added++;
      }
      showDownloadAddedToast(context, '已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batchSave() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.drive.saveShare(widget.session, _selectedFiles(), '0');
      _toast('已保存 ${_selected.length} 项到网盘根目录');
      _exitSelectMode();
    } catch (e) {
      _toast('保存失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode
            ? '已选 ${_selected.length} 项'
            : _stack.isEmpty
                ? widget.initialName
                : _files.isEmpty
                    ? '文件夹'
                    : ''),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (_selectMode) {
              _exitSelectMode();
            } else if (_stack.isNotEmpty) {
              _back();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          if (_selectMode)
            TextButton(
              onPressed: _selectAllFiles,
              child: Text('全选',
                  style: TextStyle(color: AppColors.of(context).accent)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (_selectMode) _buildSelectBar(),
        ],
      ),
    );
  }

  Widget _buildSelectBar() {
    final count = _selected.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(top: BorderSide(color: AppColors.of(context).divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text('已选 $count 项',
                style: TextStyle(
                    color: AppColors.of(context).textPrimary, fontSize: 14)),
            const Spacer(),
            OutlinedButton(
              onPressed: _busy || count == 0 ? null : _batchSave,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.of(context).green,
                side: BorderSide(color: AppColors.of(context).green),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('转存'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _busy || count == 0 ? null : _batchDownload,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.of(context).accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.of(context).accentDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text('下载($count)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(
          onPressed: _reloadCurrent,
          child: const Text('重试'),
        ),
      );
    }
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return const EmptyView(icon: Icons.folder_open_rounded, text: '这个文件夹是空的');
    }
    return RefreshIndicator(
      onRefresh: _reloadCurrent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildItem(_files[i]),
      ),
    );
  }

  Widget _buildItem(DriveShareFile file) {
    final selected = _selected.contains(file.fid);
    return InkWell(
      onTap: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _openDir(file);
        } else {
          _showFileActions(file);
        }
      },
      onLongPress: _selectMode ? null : () => _enterSelectMode(file),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).accentDeep : AppColors.of(context).card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            FileIcon(isDir: file.isDir, name: file.fileName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.of(context).textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file.isDir ? '文件夹' : formatBytes(file.size),
                    style: TextStyle(
                        color: AppColors.of(context).textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (_selectMode)
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.of(context).accent : AppColors.of(context).textSecondary,
                size: 22,
              )
            else
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.of(context).textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  void _showFileActions(DriveShareFile file) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            FileIcon(isDir: false, name: file.fileName, size: 52),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                file.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.of(context).textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(formatBytes(file.size),
                style: TextStyle(
                    color: AppColors.of(context).textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.download_rounded, color: AppColors.of(context).accent),
              title: const Text('立即下载'),
              subtitle: const Text('提取直链，多线程不限速下载'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadFile(file);
              },
            ),
            ListTile(
              leading: Icon(Icons.save_alt_rounded, color: AppColors.of(context).green),
              title: const Text('保存到网盘'),
              subtitle: const Text('转存到自己的网盘'),
              onTap: () {
                Navigator.pop(ctx);
                _saveFile(file);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(DriveShareFile file) async {
    try {
      final infos = await widget.drive
          .getShareDownloadInfo(widget.session, [file.fid]);
      if (infos.isEmpty) {
        _toast('未获取到下载地址');
        return;
      }
      final info = infos.first;
      final err = await DownloadService.addDirectUrl(
        url: info.url,
        fileName: info.fileName.isNotEmpty ? info.fileName : file.fileName,
        cookie: widget.cookie,
        connections: 16,
      );
      if (err != null) throw Exception(err);
      showDownloadAddedToast(context, '已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  Future<void> _saveFile(DriveShareFile file) async {
    try {
      await widget.drive.saveShare(widget.session, [file], '0');
      _toast('已保存到网盘根目录');
    } catch (e) {
      _toast('保存失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}