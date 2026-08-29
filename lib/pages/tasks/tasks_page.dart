import 'package:flutter/material.dart';

import '../../core/gopeed/gopeed_models.dart';
import '../../state/download_manager.dart';
import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';
import '../downloads/import_download_sheet.dart';

/// 统一「任务」页：将下载与上传任务合并到一个页面管理。
/// 顶部用分段切换「下载 / 上传」，各自保留独立的筛选与操作能力。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage>
    with AutomaticKeepAliveClientMixin {
  /// 0 = 下载，1 = 上传（分段切换，不单独拆「全部」以减少切换成本）
  int _segment = 0;

  // ---- 下载页筛选 ----
  int _dlFilter = 0;

  // ---- 上传页筛选/多选 ----
  int _upFilter = 0;
  bool _upSelectMode = false;
  final Set<String> _upSelected = {};
  bool _upBusy = false;

  @override
  bool get wantKeepAlive => true;

  DownloadManager get _dm => DownloadManager.I;
  UploadManager get _um => UploadManager.I;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 同时监听下载与上传管理器，任务状态变化时刷新计数/列表
    return ListenableBuilder(
      listenable: Listenable.merge([_dm, _um]),
      builder: (context, _) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  Text(_title(),
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  _buildHeaderAction(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _buildSegment(),
            ),
            _buildFilterRow(),
            const SizedBox(height: 8),
            Expanded(
              child: _segment == 0 ? _buildDownloadList() : _buildUploadList(),
            ),
            if (_segment == 1 && _upSelectMode) _buildUploadSelectBar(),
          ],
        ),
      ),
    );
  }

  String _title() => _segment == 1 && _upSelectMode ? '批量操作' : '任务管理';

  // ---------------- 顶部操作 ---------------- //

  Widget _buildHeaderAction() {
    if (_segment == 1 && _upSelectMode) {
      return Row(
        children: [
          TextButton(
            onPressed: () => setState(() {
              final allIds = _uploadFiltered().map((t) => t.id).toSet();
              if (_upSelected.length == allIds.length && allIds.isNotEmpty) {
                _upSelected.clear();
              } else {
                _upSelected
                  ..clear()
                  ..addAll(allIds);
              }
            }),
            child: Text(_isAllUpSelected() ? '全不选' : '全选',
                style: TextStyle(color: AppColors.of(context).accent)),
          ),
          IconButton(
            onPressed: () => setState(() {
              _upSelectMode = false;
              _upSelected.clear();
            }),
            icon: Icon(Icons.close_rounded,
                color: AppColors.of(context).accent),
          ),
        ],
      );
    }
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded,
          color: AppColors.of(context).accent, size: 26),
      onSelected: (v) async {
        switch (v) {
          case 'import':
            final msg = await ImportDownloadSheet.show(context);
            if (msg != null && mounted) _toast(msg);
          case 'pauseAll':
            await _dm.pauseAllActive();
            _toast('已全部暂停');
          case 'clearDoneDl':
            await _dm.clearDone();
            _toast('已清除已完成下载');
          case 'clearDoneUp':
            _um.clearDone();
            _toast('已清除已完成上传');
        }
      },
      itemBuilder: (_) => [
        if (_segment == 0) ...[
          const PopupMenuItem(value: 'import', child: Text('自定义下载')),
          const PopupMenuItem(value: 'pauseAll', child: Text('全部暂停')),
          const PopupMenuItem(value: 'clearDoneDl', child: Text('清除已完成下载')),
        ],
        if (_segment == 1)
          const PopupMenuItem(value: 'clearDoneUp', child: Text('清除已完成上传')),
      ],
    );
  }

  // ---------------- 分段切换 ---------------- //

  Widget _buildSegment() {
    final dlCount = _dm.tasks.length;
    final upCount = _um.tasks.length;
    final activeDl = _dm.tasks.length - _dm.countOf(GopeedStatus.done) -
        _dm.countOf(GopeedStatus.error);
    final activeUp = _um.activeCount;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _segItem(0, '下载', dlCount, activeDl, Icons.download_rounded),
          const SizedBox(width: 3),
          _segItem(1, '上传', upCount, activeUp, Icons.cloud_upload_outlined),
        ],
      ),
    );
  }

  Widget _segItem(int seg, String label, int count, int active,
      IconData icon) {
    final selected = _segment == seg;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _segment = seg;
          _upSelectMode = false;
          _upSelected.clear();
        }),
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.of(context).accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected
                      ? Colors.white
                      : AppColors.of(context).textSecondary),
              const SizedBox(width: 5),
              Text('$label  $count',
                  style: TextStyle(
                    fontSize: 13,
                    color: selected
                        ? Colors.white
                        : AppColors.of(context).textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
              if (active > 0) ...[
                const SizedBox(width: 5),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white
                        : AppColors.of(context).accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 筛选行 ---------------- //

  Widget _buildFilterRow() {
    if (_segment == 0) {
      final all = _dm.tasks;
      final done = _dm.countOf(GopeedStatus.done);
      final failed = _dm.countOf(GopeedStatus.error);
      final active = all.length - done - failed;
      return _filterChips([
        (0, '全部', all.length),
        (1, '进行中', active),
        (2, '已完成', done),
        (3, '失败', failed),
      ], _dlFilter, (i) => setState(() => _dlFilter = i));
    }
    final all = _um.tasks;
    final paused =
        _um.tasks.where((t) => t.status == UploadStatus.paused).length;
    return _filterChips([
      (0, '全部', all.length),
      (1, '进行中', _um.activeCount),
      (2, '已完成', _um.doneCount),
      (3, '失败', _um.failedCount),
      (4, '已暂停', paused),
    ], _upFilter, (i) => setState(() => _upFilter = i));
  }

  Widget _filterChips(List<(int, String, int)> chips, int current,
      ValueChanged<int> onTap) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == chips.length - 1 ? 0 : 8),
              child: _chip(chips[i].$1 == current, chips[i].$2, chips[i].$3,
                  () => onTap(chips[i].$1)),
            ),
        ],
      ),
    );
  }

  Widget _chip(bool selected, String label, int count, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).accent : AppColors.of(context).card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          selected ? '$label $count' : label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : AppColors.of(context).textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ---------------- 下载列表 ---------------- //

  List<GopeedTask> get _downloadFiltered {
    final all = _dm.tasks;
    return switch (_dlFilter) {
      1 => all
          .where((t) =>
              t.status != GopeedStatus.done && t.status != GopeedStatus.error)
          .toList(),
      2 => _dm.byStatus(GopeedStatus.done),
      3 => _dm.byStatus(GopeedStatus.error),
      _ => all,
    };
  }

  Widget _buildDownloadList() {
    final all = _dm.tasks;
    final filtered = _downloadFiltered;
    if (all.isEmpty) {
      return const EmptyView(
        icon: Icons.inventory_2_outlined,
        text: '暂无下载任务',
        subText: '去网盘或解析页添加下载任务吧');
    }
    if (filtered.isEmpty) {
      return const EmptyView(
          icon: Icons.inbox_outlined, text: '没有符合条件的任务');
    }
    return ListenableBuilder(
      listenable: _dm,
      builder: (context, _) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildDownloadCard(filtered[i]),
      ),
    );
  }

  Widget _buildDownloadCard(GopeedTask task) {
    final done = task.status == GopeedStatus.done;
    final failed = task.status == GopeedStatus.error;
    final paused = task.status == GopeedStatus.pause;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.of(context).card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FileIcon(isDir: false, name: task.name, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.of(context).textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _downloadSubtitle(task),
                      style: TextStyle(
                          color: AppColors.of(context).textSecondary,
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              _downloadBadge(task),
              const SizedBox(width: 4),
              _downloadControl(task),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    color: AppColors.of(context).textSecondary, size: 18),
                onSelected: (v) async {
                  switch (v) {
                    case 'pause':
                      await _dm.pauseTask(task);
                    case 'resume':
                      await _dm.resumeTask(task);
                    case 'retry':
                      final err = await _dm.retryTask(task);
                      if (err != null) _toast(err);
                    case 'delete':
                      await _confirmDeleteDl(task);
                    case 'deleteFile':
                      await _confirmDeleteDl(task, deleteFile: true);
                  }
                },
                itemBuilder: (_) => [
                  if (!done && !failed && !paused)
                    const PopupMenuItem(value: 'pause', child: Text('暂停')),
                  if (paused)
                    const PopupMenuItem(value: 'resume', child: Text('继续下载')),
                  if (failed)
                    const PopupMenuItem(value: 'retry', child: Text('重试')),
                  const PopupMenuItem(value: 'delete', child: Text('删除任务')),
                  const PopupMenuItem(value: 'deleteFile', child: Text('删除任务和文件')),
                ],
              ),
            ],
          ),
          if (!done && !failed) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 5,
                backgroundColor: AppColors.of(context).bg,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${formatBytes(task.downloaded)} / ${formatBytes(task.size)}',
                  style: TextStyle(
                      color: AppColors.of(context).textSecondary, fontSize: 11),
                ),
                const Spacer(),
                if (task.status == GopeedStatus.running)
                  Text(
                    formatSpeed(task.speed),
                    style: TextStyle(
                        color: AppColors.of(context).accent, fontSize: 11),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _downloadSubtitle(GopeedTask task) {
    switch (task.status) {
      case GopeedStatus.done:
        return '${formatBytes(task.size)}  ·  已完成';
      case GopeedStatus.error:
        return '下载出错，可点击重试';
      case GopeedStatus.running:
        return '${formatPercent(task.downloaded, task.size)}  ·  ${formatSpeed(task.speed)}';
      case GopeedStatus.pause:
        return '已暂停  ·  ${formatPercent(task.downloaded, task.size)}';
      default:
        return '排队中  ·  ${formatPercent(task.downloaded, task.size)}';
    }
  }

  Widget _downloadBadge(GopeedTask task) {
    final (color, text) = switch (task.status) {
      GopeedStatus.done => (AppColors.of(context).green, '完成'),
      GopeedStatus.error => (AppColors.of(context).red, '失败'),
      GopeedStatus.pause => (AppColors.of(context).orange, '暂停'),
      GopeedStatus.running => (AppColors.of(context).accent, '下载中'),
      _ => (AppColors.of(context).textSecondary, '排队'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  /// 下载卡片旁快捷控制按钮：失败为「重试」，暂停/进行中为「继续/暂停」
  Widget _downloadControl(GopeedTask task) {
    final paused = task.status == GopeedStatus.pause;
    final failed = task.status == GopeedStatus.error;
    final active = task.status == GopeedStatus.running ||
        task.status == GopeedStatus.wait ||
        task.status == GopeedStatus.ready;
    if (failed) {
      return _miniBtn(
        icon: Icons.refresh_rounded,
        label: '重试',
        onTap: () async {
          final err = await _dm.retryTask(task);
          if (err != null) _toast(err);
        },
      );
    }
    if (!paused && !active) return const SizedBox.shrink();
    return _miniBtn(
      icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
      label: paused ? '继续' : '暂停',
      onTap: () async {
        if (paused) {
          await _dm.resumeTask(task);
        } else {
          await _dm.pauseTask(task);
        }
      },
    );
  }

  Widget _miniBtn(
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.of(context).accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.of(context).accent, size: 16),
            const SizedBox(width: 2),
            Text(label,
                style:
                    TextStyle(color: AppColors.of(context).accent, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteDl(GopeedTask task,
      {bool deleteFile = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(deleteFile ? '删除任务和文件' : '删除任务'),
        content: Text(deleteFile
            ? '将删除下载任务和已下载的文件，确定？'
            : '将删除「${task.name}」任务，确定？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _dm.removeTask(task, deleteFile: deleteFile);
    }
  }

  // ---------------- 上传列表 ---------------- //

  List<UploadTask> _uploadFiltered() {
    final all = _um.tasks;
    return switch (_upFilter) {
      1 => all
          .where((t) =>
              t.status == UploadStatus.pending ||
              t.status == UploadStatus.uploading)
          .toList(),
      2 => all.where((t) => t.status == UploadStatus.done).toList(),
      3 => all.where((t) => t.status == UploadStatus.failed).toList(),
      4 => all.where((t) => t.status == UploadStatus.paused).toList(),
      _ => all,
    };
  }

  bool _isAllUpSelected() {
    final filtered = _uploadFiltered();
    return filtered.isNotEmpty && filtered.every((t) => _upSelected.contains(t.id));
  }

  Widget _buildUploadList() {
    final all = _um.tasks;
    final filtered = _uploadFiltered();
    if (all.isEmpty) {
      return const EmptyView(
        icon: Icons.cloud_upload_outlined,
        text: '暂无上传任务',
        subText: '去网盘页点「上传」选择文件或文件夹吧');
    }
    if (filtered.isEmpty) {
      return const EmptyView(
          icon: Icons.inbox_outlined, text: '没有符合条件的任务');
    }
    return ListenableBuilder(
      listenable: _um,
      builder: (context, _) {
        if (_um.hasActive) {
          return Column(
            children: [
              _uploadOverall(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildUploadCard(filtered[i]),
                ),
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _buildUploadCard(filtered[i]),
        );
      },
    );
  }

  Widget _uploadOverall() {
    final um = _um;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上传中 ${um.activeCount} 个  ·  '
            '${(um.overallProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
            style: TextStyle(
                color: AppColors.of(context).accent,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: um.overallProgress,
              minHeight: 4,
              backgroundColor: AppColors.of(context).bg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard(UploadTask task) {
    final done = task.status == UploadStatus.done;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final paused = task.status == UploadStatus.paused;
    final active = task.status == UploadStatus.uploading;
    final selected = _upSelected.contains(task.id);

    return InkWell(
      onTap: _upSelectMode ? () => _toggleUpSelect(task) : null,
      onLongPress: _upSelectMode ? null : () => _enterUpSelectMode(task),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.of(context).accentDeep : AppColors.of(context).card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FileIcon(isDir: task.isDirOnly, name: task.fileName, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.of(context).textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _uploadSubtitle(task),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.of(context).textSecondary,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _uploadBadge(task),
                if (_upSelectMode)
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? AppColors.of(context).accent
                        : AppColors.of(context).textSecondary,
                    size: 22,
                  )
                else
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded,
                        color: AppColors.of(context).textSecondary, size: 18),
                    onSelected: (v) => _onUploadMenu(task, v),
                    itemBuilder: (_) => _uploadMenuItems(task),
                  ),
              ],
            ),
            if (task.isActive || paused) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 5,
                  backgroundColor: AppColors.of(context).bg,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${formatBytes(task.uploadedBytes)} / ${formatBytes(task.size)}',
                    style: TextStyle(
                        color: AppColors.of(context).textSecondary, fontSize: 11),
                  ),
                  const Spacer(),
                  if (active && task.speed > 0)
                    Text(
                      formatSpeed(task.speed),
                      style: TextStyle(
                          color: AppColors.of(context).accent, fontSize: 11),
                    ),
                ],
              ),
            ],
            if (failed && task.error != null) ...[
              const SizedBox(height: 8),
              Text(
                task.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.of(context).red, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _enterUpSelectMode(UploadTask task) {
    setState(() {
      _upSelectMode = true;
      _upSelected.add(task.id);
    });
  }

  void _toggleUpSelect(UploadTask task) {
    setState(() {
      if (!_upSelected.remove(task.id)) {
        _upSelected.add(task.id);
      }
    });
  }

  String _uploadSubtitle(UploadTask task) {
    final base = task.isDirOnly ? '空文件夹' : formatBytes(task.size);
    switch (task.status) {
      case UploadStatus.done:
        return '$base  ·  已上传到夸克网盘';
      case UploadStatus.failed:
        return '$base  ·  上传失败，可重新上传';
      case UploadStatus.canceled:
        return '$base  ·  已取消';
      case UploadStatus.paused:
        return '$base  ·  已暂停，可继续上传';
      case UploadStatus.uploading:
        final stage = switch (task.stage) {
          UploadStage.hashing => '校验中',
          UploadStage.uploading => '上传中',
          UploadStage.merging => '合并中',
          UploadStage.queued => '排队中',
        };
        return '$stage  ·  ${formatPercent(task.uploadedBytes, task.size)}';
      case UploadStatus.pending:
        return '排队中  ·  ${formatPercent(task.uploadedBytes, task.size)}';
    }
  }

  Widget _uploadBadge(UploadTask task) {
    final (color, text) = switch (task.status) {
      UploadStatus.done => (AppColors.of(context).green, '完成'),
      UploadStatus.failed => (AppColors.of(context).red, '失败'),
      UploadStatus.canceled => (AppColors.of(context).textSecondary, '已取消'),
      UploadStatus.paused => (AppColors.of(context).orange, '已暂停'),
      UploadStatus.uploading => switch (task.stage) {
          UploadStage.hashing => (AppColors.of(context).accent, '校验中'),
          UploadStage.merging => (AppColors.of(context).orange, '合并中'),
          _ => (AppColors.of(context).accent, '上传中'),
        },
      UploadStatus.pending => (AppColors.of(context).textSecondary, '排队'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  List<PopupMenuEntry<String>> _uploadMenuItems(UploadTask task) {
    final paused = task.status == UploadStatus.paused;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final done = task.status == UploadStatus.done;
    return <PopupMenuEntry<String>>[
      if (task.isActive)
        const PopupMenuItem(value: 'pause', child: Text('暂停')),
      if (paused)
        const PopupMenuItem(value: 'resume', child: Text('继续上传')),
      if (failed || canceled || done)
        const PopupMenuItem(value: 'retry', child: Text('重新上传')),
      if (task.isActive)
        const PopupMenuItem(value: 'cancel', child: Text('取消上传')),
      const PopupMenuItem(value: 'delete', child: Text('删除任务')),
    ];
  }

  void _onUploadMenu(UploadTask task, String v) {
    switch (v) {
      case 'pause':
        _um.pause(task);
        _toast('已暂停');
      case 'resume':
        _um.resume(task);
        _toast('已恢复上传');
      case 'retry':
        _um.retry(task);
        _toast('已重新加入队列');
      case 'cancel':
        _um.cancel(task);
        _toast('已取消');
      case 'delete':
        _um.remove(task);
    }
  }

  Widget _buildUploadSelectBar() {
    final count = _upSelected.length;
    final upTasks = _um.tasks.where((t) => _upSelected.contains(t.id)).toList();
    final hasPause = upTasks.any((t) => t.isActive);
    final hasResume = upTasks.any((t) => t.status == UploadStatus.paused);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Color(0xFF12121A),
        border:
            Border(top: BorderSide(color: AppColors.of(context).divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text('已选 $count 项',
                style: TextStyle(
                    color: AppColors.of(context).textPrimary, fontSize: 14)),
            const Spacer(),
            IconButton(
              onPressed: _upBusy || !hasPause ? null : _batchUpPause,
              icon: Icon(Icons.pause_rounded,
                  color: hasPause && !_upBusy
                      ? AppColors.of(context).orange
                      : AppColors.of(context).textSecondary),
            ),
            IconButton(
              onPressed: _upBusy || !hasResume ? null : _batchUpResume,
              icon: Icon(Icons.play_arrow_rounded,
                  color: hasResume && !_upBusy
                      ? AppColors.of(context).accent
                      : AppColors.of(context).textSecondary),
            ),
            IconButton(
              onPressed: _upBusy || count == 0 ? null : _batchUpDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: _upBusy || count == 0
                      ? AppColors.of(context).textSecondary
                      : AppColors.of(context).red),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchUpPause() async {
    final list =
        _um.tasks.where((t) => _upSelected.contains(t.id) && t.isActive).toList();
    _um.pauseAll(list);
    _finishUpBatch('已暂停 ${list.length} 个任务');
  }

  Future<void> _batchUpResume() async {
    final list = _um.tasks
        .where((t) =>
            _upSelected.contains(t.id) && t.status == UploadStatus.paused)
        .toList();
    _um.resumeAll(list);
    _finishUpBatch('已恢复 ${list.length} 个任务');
  }

  Future<void> _batchUpDelete() async {
    final count = _upSelected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除上传任务'),
        content: const Text('确定删除选中的任务吗？此操作不会删除本地文件。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('删除', style: TextStyle(color: AppColors.of(context).red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final list =
        _um.tasks.where((t) => _upSelected.contains(t.id)).toList();
    _um.removeAll(list);
    _finishUpBatch('已删除 $count 个任务');
  }

  void _finishUpBatch(String msg) {
    setState(() {
      _upSelectMode = false;
      _upSelected.clear();
      _upBusy = false;
    });
    _toast(msg);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}