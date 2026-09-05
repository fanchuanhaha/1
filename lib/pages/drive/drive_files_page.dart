import 'package:flutter/material.dart';

import '../../api/base_drive.dart';
import '../../api/baidu_accel_service.dart';
import '../../api/drive_type.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/drive_folder_picker.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/share_dialogs.dart';

/// 通用网盘文件浏览页面，可适用于任何实现 [BaseDrive] 的网盘。
class DriveFilesPage extends StatefulWidget {
  final BaseDrive drive;
  final String driveName;
  final String initialDirFid;

  const DriveFilesPage({
    super.key,
    required this.drive,
    required this.driveName,
    this.initialDirFid = '0',
  });

  @override
  State<DriveFilesPage> createState() => _DriveFilesPageState();
}

class _DriveFilesPageState extends State<DriveFilesPage> {
  List<DriveFile> _files = [];
  late String _pdirFid = widget.initialDirFid;
  late String _currentName = widget.driveName;
  final List<(String, String)> _crumbs = [];
  bool _loading = false;
  String? _error;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _downloading = false;

  /// 百度加速过程：正中的模态进度条文案与开关
  final ValueNotifier<String> _accelMessage = ValueNotifier<String>('');
  bool _accelDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _crumbs.add((widget.initialDirFid, widget.driveName));
    _load();
  }

  @override
  void dispose() {
    _accelMessage.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.drive.listFiles(_pdirFid);
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

  Future<void> _enterDir(DriveFile dir) async {
    setState(() {
      // 记录进入的文件夹本身作为新面包屑；之前误加旧目录名导致「百度网盘/百度网盘」重复。
      _crumbs.add((dir.fid, dir.fileName));
      _pdirFid = dir.fid;
      _currentName = dir.fileName;
      _files = [];
      _loading = true;
    });
    try {
      final files = await widget.drive.listFiles(_pdirFid);
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

  void _toBreadcrumb(int index) {
    if (index >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(index + 1, _crumbs.length);
      _pdirFid = _crumbs.last.$1;
      _currentName = _crumbs.last.$2;
      _files = [];
      _error = null;
      _selectMode = false;
      _selected.clear();
    });
    _load();
  }

  // ---------------- 多选 ----------------

  void _enterSelectMode(DriveFile file) {
    setState(() {
      _selectMode = true;
      if (!file.isDir) _selected.add(file.fid);
    });
  }

  void _toggleSelect(DriveFile file) {
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

  void _singleDownload(DriveFile file) => _batchDownload([file.fid]);

  /// 当前驱动是否为百度网盘且已开启「野鸡百度加速」接口
  bool get _useAccel =>
      widget.drive.type == DriveType.baidu && AppState.I.isBaiduAccelOn;

  /// 解析下载信息：开启百度加速接口时，先对文件创建分享链接，再由
  /// 第三方接口解析出加速直链；任一环节失败则回退用网盘原生方式获取直链。
  /// 各步骤会通过 toast + 日志提示用户当前进度。
  Future<List<DriveDownloadInfo>> _resolveDownloadInfo(
      List<String> fids) async {
    if (!_useAccel) return widget.drive.getDownloadInfo(fids);

    final accel = BaiduAccelService.I;
    final password = AppState.I.baiduAccelPassword;
    final results = <DriveDownloadInfo>[];
    _openAccelDialog('正在创建分享…');
    try {
      for (final fid in fids) {
        final matched = _files.where((f) => f.fid == fid).toList();
        final fileName =
            matched.isNotEmpty ? matched.first.fileName : '$fid';
        try {
          _accelStep('正在创建分享…');
          final share = await widget.drive.shareFiles([fid]);
          AppLogger.I.i('drive_files', '分享创建成功 url=${share.url} pwd=${share.pwd}');

          _accelStep('正在获取分享文件列表…');
          final fileList =
              await accel.getFileList(url: share.url, pwd: share.pwd, parsePassword: password);
          // 根据文件名定位 fs_id；若分享目录只有一个文件则直接用其 fs_id
          String fsId = fileList.list
              .where((f) => !f.isDir && f.serverFilename == fileName)
              .map((f) => f.fsId)
              .firstOrNull ??
              fileList.list.where((f) => !f.isDir).map((f) => f.fsId).firstOrNull ??
              '';
          if (fsId.isEmpty) {
            _accelWarn('fid=$fid 分享列表中未匹配到该文件，回退普通下载');
            results.addAll(await widget.drive.getDownloadInfo([fid]));
            continue;
          }

          _accelStep('正在解析加速直链…');
          final linkMap = await accel.getDownloadLinks(
            fileList: fileList,
            fsIds: [fsId],
            surl: share.surl,
            pwd: share.pwd,
            parsePassword: password,
          );
          final link = linkMap[fsId];
          if (link == null || link.urls.isEmpty) {
            _accelWarn('fid=$fid 未解析到加速直链，回退普通下载');
            results.addAll(await widget.drive.getDownloadInfo([fid]));
            continue;
          }
          final size =
              matched.isNotEmpty ? matched.first.size : 0;
          _accelStep('加速直链获取成功，准备下载');
          AppLogger.I.i('drive_files', '百度加速直链获取成功 fid=$fid 加速域名=${_hostOf(link.urls.first)}');
          results.add(DriveDownloadInfo(
            url: link.urls.first,
            fileName: fileName,
            size: size,
            fid: fid,
            // 直链绑定专用 UA（如 netdisk;8.42.0.5;PC），原样使用；
            // 且加速链接为分享/匿名上下文，禁止附带个人 cookie。
            userAgent: link.ua,
            skipCookie: true,
          ));
        } catch (e) {
          AppLogger.I.w('drive_files', '百度加速解析失败，回退普通下载 $fid: $e');
          _accelWarn('百度加速解析失败，已回退普通下载：$e');
          results.addAll(await widget.drive.getDownloadInfo([fid]));
        }
      }
      return results;
    } finally {
      _closeAccelDialog();
    }
  }

  String _hostOf(String url) => Uri.tryParse(url)?.host ?? '';

  /// 打开正中的模态进度框（丝带旋转 + 当前步骤文案），不可点击关闭。
  void _openAccelDialog(String initial) {
    if (_accelDialogOpen || !mounted) return;
    _accelDialogOpen = true;
    _accelMessage.value = initial;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: AppColors.of(dialogContext).card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.of(dialogContext).accent,
                  ),
                ),
                const SizedBox(width: 20),
                Flexible(
                  child: ValueListenableBuilder<String>(
                    valueListenable: _accelMessage,
                    builder: (_, msg, __) => Text(
                      msg,
                      style: TextStyle(
                          color: AppColors.of(dialogContext).textPrimary,
                          fontSize: 15),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => _accelDialogOpen = false);
  }

  void _closeAccelDialog() {
    if (!_accelDialogOpen || !mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pop(); // .then 会复位 _accelDialogOpen
  }

  /// 记录一个加速进度步骤并实时更新正中进度框文案。
  void _accelStep(String msg) {
    AppLogger.I.i('drive_files', '[百度加速] $msg');
    _accelMessage.value = msg;
  }

  void _accelWarn(String msg) {
    AppLogger.I.w('drive_files', '[百度加速] $msg');
    if (mounted) {
      AppMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _batchDownload([List<String>? specific]) async {
    final targets = specific ?? _selected.toList();
    if ((specific == null && _selected.isEmpty) || _downloading) return;
    setState(() => _downloading = true);
    try {
      final infos = await _resolveDownloadInfo(targets);
      if (!mounted) return;
      var added = 0;
      for (final info in infos) {
        if (info.url.isEmpty) continue;
        final err = await DownloadService.addDriveUrl(
          widget.drive,
          info,
          connections: AppState.I.connectionsFor(widget.drive.type),
        );
        if (err == null) added++;
      }
      _toast(infos.isEmpty ? '未获取到下载地址' : '已添加 $added 个下载任务');
      if (added > 0) DownloadManager.I.startPolling();
      if (specific != null) return;
      _exitSelectMode();
    } catch (e) {
      if (!mounted) return;
      _toast('下载失败: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selected.length} 项' : widget.driveName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (_selectMode) {
              _exitSelectMode();
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 面包屑导航
          if (_crumbs.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _crumbs.length; i++) ...[
                      if (i > 0)
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: AppColors.of(context).textSecondary),
                      InkWell(
                        onTap: () => _toBreadcrumb(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
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
            if (widget.drive.supportsDelete) ...[
              TextButton.icon(
                onPressed: _downloading || count == 0 ? null : _deleteSelected,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    disabledForegroundColor:
                        AppColors.of(context).textSecondary),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text('删除($count)'),
              ),
              const SizedBox(width: 10),
            ],
            FilledButton.icon(
              onPressed: _downloading || count == 0 ? null : _batchDownload,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.of(context).accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.of(context).accentDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _downloading
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
    if (_error != null && _files.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(
          onPressed: _load,
          child: const Text('重试'),
        ),
      );
    }
    if (_loading && _files.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_files.isEmpty) {
      return const EmptyView(
          icon: Icons.folder_open_rounded, text: '这里空空如也');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildItem(_files[i]),
      ),
    );
  }

  Widget _buildItem(DriveFile file) {
    final selected = _selected.contains(file.fid);
    return InkWell(
      onTap: () {
        if (_selectMode) {
          _toggleSelect(file);
        } else if (file.isDir) {
          _enterDir(file);
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
                    file.isDir
                        ? '文件夹'
                        : '${formatBytes(file.size)}  ·  ${formatDateTime(file.updatedAt)}',
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

  void _showFileActions(DriveFile file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
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
              leading: Icon(Icons.download_rounded,
                  color: AppColors.of(context).accent),
              title: const Text('立即下载'),
              subtitle: const Text('提取直链，多线程不限速下载'),
              onTap: () {
                Navigator.pop(ctx);
                _singleDownload(file);
              },
            ),
            if (widget.drive.supportsShare) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.link_rounded,
                    color: AppColors.of(context).accent),
                title: const Text('分享链接'),
                subtitle: const Text('自定义时长与提取码，生成分享链接'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareFile(file);
                },
              ),
            ],
            if (widget.drive.supportsRename) ...[
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline_rounded,
                    color: AppColors.of(context).accent),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFile(file);
                },
              ),
            ],
            if (widget.drive.supportsMove) ...[
              ListTile(
                leading: Icon(Icons.drive_file_move_rounded,
                    color: AppColors.of(context).accent),
                title: const Text('移动到'),
                subtitle: const Text('选择目标文件夹，移动该文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveFile(file);
                },
              ),
            ],
            if (widget.drive.supportsDelete) ...[
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: const Text('删除'),
                subtitle: const Text('移到网盘回收站'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteFiles([file.fid]);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- 文件管理操作：分享 / 重命名 / 移动 ----------------

  Future<void> _shareFile(DriveFile file) async {
    try {
      final config = await showShareSetupDialog(context);
      if (config == null || !mounted) return;
      final result = await widget.drive.shareFiles([file.fid],
          pwd: config.hasCustomPwd ? config.pwd : null,
          period: config.period,
          requirePwd: config.requirePwd);
      if (!mounted) return;
      await showShareResultDialog(
          context, buildShareFullUrl(result.url, result.pwd), result.pwd);
    } catch (e) {
      _toast('分享失败: $e');
    }
  }

  Future<void> _renameFile(DriveFile file) async {
    final controller = TextEditingController(text: file.fileName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 1,
          style: TextStyle(color: AppColors.of(ctx).textPrimary),
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == file.fileName) return;
    final err = await widget.drive.renameFile(file.fid, newName);
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else {
      _toast('已重命名为「$newName」');
      _load();
    }
  }

  Future<void> _moveFile(DriveFile file) async {
    final toDirFid = await DriveFolderPicker.show(context, drive: widget.drive);
    if (toDirFid == null || toDirFid.isEmpty) return;
    if (toDirFid == file.pdirFid) {
      _toast('已在目标文件夹中');
      return;
    }
    final err = await widget.drive.moveFiles([file.fid], toDirFid);
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else {
      _toast('已移动「${file.fileName}」');
      _load();
    }
  }

  Future<void> _deleteFiles(List<String> fids) async {
    if (fids.isEmpty) return;
    final names = fids
        .map((fid) {
          final m = _files.where((f) => f.fid == fid).toList();
          return m.isNotEmpty ? m.first.fileName : fid;
        })
        .join('、');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(ctx).card,
        title: const Text('删除文件'),
        content: Text(
          '确定删除「$names」吗？会移到网盘回收站（可恢复）。',
          style: TextStyle(color: AppColors.of(ctx).textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await widget.drive.deleteFiles(fids);
    if (!mounted) return;
    if (err != null) {
      _toast(err);
    } else {
      _toast('已删除 ${fids.length} 项');
      _exitSelectMode();
      _load();
    }
  }

  void _deleteSelected() => _deleteFiles(_selected.toList());
}