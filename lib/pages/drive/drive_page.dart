import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/drive_type.dart';
import '../../api/quark_models.dart';
import '../../state/app_state.dart';
import '../../state/download_manager.dart';
import '../../state/download_service.dart';
import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/format.dart';
import '../../utils/permission.dart';
import '../../utils/upload_picker.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../../widgets/share_dialogs.dart';
import 'album_page.dart';
import 'search_page.dart';

class DrivePage extends StatefulWidget {
  final String initialDirFid;
  final String initialName;

  const DrivePage({
    super.key,
    this.initialDirFid = '0',
    this.initialName = '全部文件',
  });

  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage>
    with AutomaticKeepAliveClientMixin {
  List<QuarkFile> _files = [];
  late String _pdirFid = widget.initialDirFid;
  late String _currentName = widget.initialName;
  late final List<(String, String)> _crumbs = [
    (widget.initialDirFid, widget.initialName)
  ];
  bool _loading = false;
  String? _error;
  bool? _lastLoggedIn;

  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _downloading = false;

  /// Windows 窗口级拖放通道：把 explorer 拖入的文件/文件夹路径交给上传
  static const _dropChannel = MethodChannel('quarklite.com/drop');

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AppState.I.addListener(_onLoginChanged);
    if (!kIsWeb && Platform.isWindows) {
      _dropChannel.setMethodCallHandler(_onDrop);
    }
    _load();
  }

  @override
  void dispose() {
    AppState.I.removeListener(_onLoginChanged);
    super.dispose();
  }

  /// 窗口拖放回调：按文件/文件夹分流后上传到当前网盘目录
  Future<dynamic> _onDrop(MethodCall call) async {
    if (call.method != 'onDropped') return null;
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录夸克账号');
      return null;
    }
    final raw = call.arguments as List<dynamic>?;
    if (raw == null || raw.isEmpty) return null;
    final paths = raw.map((e) => e.toString()).toList();
    if (!mounted) return null;
    // 过滤不存在的路径，按文件/文件夹分流后直接上传到当前网盘目录
    final files = <UploadSource>[];
    final folders = <String>[];
    for (final p in paths) {
      try {
        if (FileSystemEntity.isDirectorySync(p)) {
          folders.add(p);
        } else if (FileSystemEntity.isFileSync(p)) {
          final f = File(p);
          final st = await f.stat();
          files.add(UploadSource(
            path: p,
            name: _basename(p),
            size: st.size,
            modified: st.modified.millisecondsSinceEpoch,
          ));
        }
      } catch (_) {
        // 单个路径不可访问时跳过
      }
    }
    if (files.isEmpty && folders.isEmpty) return null;
    if (folders.isNotEmpty) {
      await _uploadDraggedFolders(folders);
    } else {
      UploadManager.I.addFiles(files, _pdirFid);
      _toast('已加入 ${files.length} 个上传任务，可在「上传」页查看进度');
    }
    return null;
  }

  static String _basename(String path) {
    final norm = path.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx < 0 ? norm : norm.substring(idx + 1);
  }

  /// 拖入文件夹：递归收集（复用 UploadPicker 深度/数量上限），作为批次上传
  Future<void> _uploadDraggedFolders(List<String> folders) async {
    var total = 0;
    for (final f in folders) {
      final root = Directory(f);
      if (!await root.exists()) continue;
      final collected = <UploadSource>[];
      final empties = <String>[];
      try {
        await _walkDrag(root, '', collected, empties, depth: 0);
      } catch (_) {}
      if (collected.isEmpty && empties.isEmpty) {
        _toast('「${_basename(f)}」为空或不可读');
        continue;
      }
      total += collected.length;
      // 每个拖入的文件夹作为独立批次上传（各自建同名根目录）
      UploadManager.I.addFolderBatch(
        files: collected,
        emptyDirs: empties,
        targetDirFid: _pdirFid,
        rootFolderName: _basename(f),
      );
    }
    if (total > 0) {
      _toast('已加入 $total 个上传任务，可在「上传」页查看进度');
    }
  }

  void _onLoginChanged() {
    final logged = AppState.I.isLoggedIn;
    if (logged == _lastLoggedIn) return;
    _lastLoggedIn = logged;
    if (mounted) {
      setState(() {
        _selectMode = false;
        _selected.clear();
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (!AppState.I.isLoggedIn) {
      setState(() {
        _files = [];
        _error = '未登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await AppState.I.quark.listFiles(_pdirFid);
      AppLogger.I.i('drive_page', 'listFiles(pdirFid=$_pdirFid) 成功，返回 ${files.length} 个文件');
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('drive_page', 'listFiles(pdirFid=$_pdirFid) 加载失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _enterDir(QuarkFile dir) async {
    setState(() {
      _crumbs.add((_pdirFid, _currentName));
      _pdirFid = dir.fid;
      _currentName = dir.fileName;
      _files = [];
      _loading = true;
    });
    try {
      final files = await AppState.I.quark.listFiles(_pdirFid);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      AppLogger.I.e('drive_page', 'enterDir listFiles(pdirFid=$_pdirFid) 失败: $e');
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

  void _enterSelectMode(QuarkFile file) {
    setState(() {
      _selectMode = true;
      if (!file.isDir) _selected.add(file.fid);
    });
  }

  void _toggleSelect(QuarkFile file) {
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

  Future<void> _batchDownload() async {
    if (_selected.isEmpty || _downloading) return;
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (!ok) {
      if (!mounted) return;
      final granted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要存储权限'),
          content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, true);
                app.openAllFilesAccess();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (granted != true) return;
      _toast('授权完成后请重新下载');
      return;
    }
    setState(() => _downloading = true);
    try {
      final (infos, cookie) =
          await app.quark.getDownloadInfo(_selected.toList());
      var added = 0;
      for (final info in infos) {
        if (info.url.isEmpty) continue;
        final err = await DownloadService.addDirectUrl(
          url: info.url,
          fileName: info.fileName,
          cookie: cookie,
          connections: app.connectionsFor(DriveType.quark),
        );
        if (err == null) added++;
      }
      _toast('已添加 $added 个下载任务');
      DownloadManager.I.startPolling();
      _exitSelectMode();
    } catch (e) {
      _toast('批量下载失败: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(DriveType.quark.label),
        actions: _selectMode
            ? [
                TextButton(
                  onPressed: _selectAllFiles,
                  child: Text('全选',
                      style: TextStyle(color: AppColors.of(context).accent)),
                ),
                IconButton(
                  onPressed: _exitSelectMode,
                  icon: Icon(Icons.close_rounded,
                      color: AppColors.of(context).accent),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  icon: Icon(Icons.upload_file_rounded,
                      color: AppColors.of(context).accent),
                  tooltip: '上传',
                  onSelected: (v) {
                    if (v == 'file') {
                      _pickUploadFiles();
                    } else if (v == 'folder') {
                      _pickUploadFolder();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'file', child: Text('上传文件')),
                    PopupMenuItem(value: 'folder', child: Text('上传文件夹')),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlbumPage()),
                  ),
                  icon: Icon(Icons.photo_library_rounded,
                      color: AppColors.of(context).accent),
                  tooltip: '相册',
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                  icon: Icon(Icons.search_rounded,
                      color: AppColors.of(context).accent),
                  tooltip: '搜索',
                ),
                IconButton(
                  onPressed: () {
                    _crumbs
                      ..clear()
                      ..add(('0', '全部文件'));
                    _pdirFid = '0';
                    _currentName = '全部文件';
                    _files = [];
                    _load();
                  },
                  icon: Icon(Icons.home_rounded,
                      color: AppColors.of(context).accent),
                ),
                IconButton(
                  onPressed: _load,
                  icon: Icon(Icons.refresh_rounded,
                      color: AppColors.of(context).accent),
                ),
              ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    if (!AppState.I.isLoggedIn) {
      return const EmptyView(
        icon: Icons.lock_outline_rounded,
        text: '登录后查看网盘文件',
        subText: '请在「我的」页面登录夸克账号',
      );
    }
    if (_error != null && _files.isEmpty) {
      return EmptyView(
        icon: Icons.cloud_off_rounded,
        text: '加载失败',
        subText: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('重试')),
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

  Widget _buildItem(QuarkFile file) {
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

  void _showFileActions(QuarkFile file) {
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
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.share_rounded, color: AppColors.of(context).accent),
              title: const Text('分享链接'),
              subtitle: const Text('生成分享链接并复制'),
              onTap: () {
                Navigator.pop(ctx);
                _shareFile(file);
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline_rounded,
                  color: AppColors.of(context).accent),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFile(file);
              },
            ),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _shareFile(QuarkFile file) async {
    try {
      final config = await showShareSetupDialog(context);
      if (config == null || !mounted) return;
      final result = await AppState.I.quark.shareFiles([file.fid],
          passcode: config.hasCustomPwd ? config.pwd : null,
          title: file.fileName,
          expiredType: config.period,
          requirePwd: config.requirePwd);
      if (!mounted) return;
      await showShareResultDialog(
          context, buildShareFullUrl(result.url, result.pwd), result.pwd);
    } catch (e) {
      if (!mounted) return;
      _showSnack('分享失败: $e');
    }
  }

  Future<void> _renameFile(QuarkFile file) async {
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
    final err = await AppState.I.quark.renameFile(file.fid, newName);
    if (!mounted) return;
    _showSnack(err == null ? '已重命名为「$newName」' : err);
    if (err == null) _load();
  }

  Future<void> _moveFile(QuarkFile file) async {
    final toDirFid = await showQuarkFolderPicker(
      context: context,
      listDir: (fid) => AppState.I.quark.listFiles(fid),
    );
    if (toDirFid == null || toDirFid.isEmpty) return;
    if (toDirFid == file.pdirFid) {
      _showSnack('已在目标文件夹中');
      return;
    }
    final err = await AppState.I.quark.moveFiles([file.fid], toDirFid);
    if (!mounted) return;
    _showSnack(err == null ? '已移动「${file.fileName}」' : err);
    if (err == null) _load();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    AppMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _downloadFile(QuarkFile file) async {
    final app = AppState.I;
    final ok = await app.canWriteDownload();
    if (!ok) {
      if (!mounted) return;
      final granted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('需要存储权限'),
          content: const Text('下载文件需要「所有文件访问」权限，请授权后继续。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, true);
                app.openAllFilesAccess();
              },
              child: const Text('去授权'),
            ),
          ],
        ),
      );
      if (granted != true) return;
      _toast('授权完成后请重新点击下载');
      return;
    }
    try {
      final (infos, cookie) =
          await app.quark.getDownloadInfo([file.fid]);
      if (infos.isEmpty) {
        throw Exception('未获取到下载地址');
      }
      final info = infos.first;
      final err = await DownloadService.addDirectUrl(
        url: info.url,
        fileName: info.fileName,
        cookie: cookie,
        connections: app.connectionsFor(DriveType.quark),
      );
      if (err != null) throw Exception(err);
      showDownloadAddedToast(context, '已加入下载队列');
      DownloadManager.I.startPolling();
    } catch (e) {
      _toast('下载失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- 上传 ----------------

  Future<void> _pickUploadFiles() async {
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录夸克账号');
      return;
    }
    final sources = await UploadPicker.pickFiles();
    if (sources.isEmpty) return;
    UploadManager.I.addFiles(sources, _pdirFid);
    _toast('已加入 ${sources.length} 个上传任务，可在「上传」页查看进度');
  }

  Future<void> _pickUploadFolder() async {
    if (!AppState.I.isLoggedIn) {
      _toast('请先登录夸克账号');
      return;
    }
    final app = AppState.I;
    if (Platform.isAndroid && !await app.canWriteDownload()) {
      _toast('上传文件夹需要「所有文件访问」权限');
      app.openAllFilesAccess();
      return;
    }
    final result = await UploadPicker.pickFolder();
    if (result.canceled) return;
    if (result.needPermission) {
      _toast('需要「所有文件访问」权限');
      app.openAllFilesAccess();
      return;
    }
    if (result.error != null) {
      _toast(result.error!);
      return;
    }
    if (result.files.isEmpty && result.emptyDirs.isEmpty) {
      _toast('所选文件夹为空或不可读');
      return;
    }
    UploadManager.I.addFolderBatch(
      files: result.files,
      emptyDirs: result.emptyDirs,
      targetDirFid: _pdirFid,
      rootFolderName: result.rootName,
    );
    _toast('已加入 ${result.files.length} 个上传任务，可在「上传」页查看进度');
  }
}

/// 拖入文件夹的递归遍历：收集文件与空目录（复用 UploadPicker 的规则）。
/// 限制深度/数量，超大目录自动截断避免卡死。
Future<void> _walkDrag(
  Directory dir,
  String rel,
  List<UploadSource> files,
  List<String> emptyDirs, {
  required int depth,
}) async {
  if (depth > UploadPicker.maxDepth || files.length >= UploadPicker.maxFiles) {
    return;
  }
  final children = <FileSystemEntity>[];
  await for (final e in dir.list(followLinks: false)) {
    children.add(e);
  }
  if (children.isEmpty) {
    if (rel.isNotEmpty) emptyDirs.add(rel);
    return;
  }
  for (final e in children) {
    if (files.length >= UploadPicker.maxFiles) break;
    final name = _DrivePageState._basename(e.path);
    if (e is Directory) {
      final childRel = rel.isEmpty ? name : '$rel/$name';
      await _walkDrag(e, childRel, files, emptyDirs, depth: depth + 1);
    } else if (e is File) {
      try {
        final st = await e.stat();
        files.add(UploadSource(
          path: e.path,
          name: name,
          size: st.size,
          modified: st.modified.millisecondsSinceEpoch,
          relDir: rel,
        ));
      } catch (_) {}
    }
  }
}

/// 夸克「移动/复制」目标文件夹选择器：从根目录逐级浏览子文件夹，
/// 点击「移动至此」返回当前目录 fid，取消返回 null。
Future<String?> showQuarkFolderPicker({
  required BuildContext context,
  required Future<List<QuarkFile>> Function(String fid) listDir,
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
      child: _QuarkFolderPicker(listDir: listDir),
    ),
  );
}

class _QuarkFolderPicker extends StatefulWidget {
  final Future<List<QuarkFile>> Function(String fid) listDir;
  const _QuarkFolderPicker({required this.listDir});

  @override
  State<_QuarkFolderPicker> createState() => _QuarkFolderPickerState();
}

class _QuarkFolderPickerState extends State<_QuarkFolderPicker> {
  final List<(String, String)> _crumbs = [('0', '根目录')];
  String _currentFid = '0';
  bool _loading = false;
  List<QuarkFile> _dirs = [];
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
      final files = await widget.listDir(_currentFid);
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

  void _enter(QuarkFile dir) {
    setState(() {
      _crumbs.add((_currentFid, dir.fileName));
      _currentFid = dir.fid;
      _dirs = [];
      _loading = true;
    });
    _load();
  }

  void _go(int i) {
    if (i >= _crumbs.length - 1) return;
    setState(() {
      _crumbs.removeRange(i + 1, _crumbs.length);
      _currentFid = _crumbs.last.$1;
      _dirs = [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _crumbs.length; i++) ...[
                  if (i > 0)
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.of(context).textSecondary),
                  InkWell(
                    onTap: () => _go(i),
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
              ]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _currentFid),
            child: const Text('移动至此'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? EmptyView(
                    icon: Icons.error_outline_rounded, text: '加载失败')
                : _dirs.isEmpty
                    ? const EmptyView(
                        icon: Icons.folder_off_rounded,
                        text: '暂无子文件夹')
                    : ListView.builder(
                        itemCount: _dirs.length,
                        itemBuilder: (c, i) {
                          final d = _dirs[i];
                          return ListTile(
                            leading: Icon(Icons.folder_rounded,
                                color: AppColors.of(context).accent),
                            title: Text(d.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: Icon(Icons.chevron_right_rounded,
                                color: AppColors.of(context).textSecondary),
                            onTap: () => _enter(d),
                          );
                        },
                      ),
      ),
    ]);
  }
}
