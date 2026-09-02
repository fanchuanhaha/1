import 'package:flutter/material.dart';

import '../../state/upload_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/file_icon.dart';

class UploadsPage extends StatefulWidget {
  const UploadsPage({super.key});

  @override
  State<UploadsPage> createState() => _UploadsPageState();
}

class _UploadsPageState extends State<UploadsPage>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0;
  bool _selectMode = false;
  final Set<String> _selected = {};
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  UploadManager get _um => UploadManager.I;

  List<UploadTask> _applyFilter(List<UploadTask> all) {
    return switch (_filter) {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: UploadManager.I,
      builder: (context, _) {
        final um = UploadManager.I;
        final all = um.tasks;
        final active = um.activeCount;
        final paused =
            um.tasks.where((t) => t.status == UploadStatus.paused).length;
        final done = um.doneCount;
        final failed = um.failedCount;

        final filtered = _applyFilter(all);

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 4, 4),
                child: Row(
                  children: [
                    Text(_selectMode ? '批量操作' : '上传管理',
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_selectMode)
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              final allIds =
                                  filtered.map((t) => t.id).toSet();
                              if (_selected.length == allIds.length &&
                                  allIds.isNotEmpty) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(allIds);
                              }
                            }),
                            child: Text(_isAllSelected(filtered) ? '全不选' : '全选',
                                style: TextStyle(
                                    color: AppColors.of(context).accent)),
                          ),
                          IconButton(
                            onPressed: _exitSelectMode,
                            icon: Icon(Icons.close_rounded,
                                color: AppColors.of(context).accent),
                          ),
                        ],
                      )
                    else
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_horiz_rounded,
                            color: AppColors.of(context).accent, size: 26),
                        onSelected: (v) async {
                          switch (v) {
                            case 'clearDone':
                              _um.clearDone();
                              _toast('已清除已完成任务');
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'clearDone', child: Text('清除已完成')),
                        ],
                      ),
                  ],
                ),
              ),
              if (um.hasActive) _buildOverallProgress(um),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    _buildFilterChip(0, '全部', all.length),
                    const SizedBox(width: 8),
                    _buildFilterChip(1, '进行中', active),
                    const SizedBox(width: 8),
                    _buildFilterChip(2, '已完成', done),
                    const SizedBox(width: 8),
                    _buildFilterChip(3, '失败', failed),
                    const SizedBox(width: 8),
                    _buildFilterChip(4, '已暂停', paused),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: all.isEmpty
                    ? const EmptyView(
                        icon: Icons.cloud_upload_outlined,
                        text: '暂无上传任务',
                        subText: '去网盘页点「上传」选择文件或文件夹吧')
                    : filtered.isEmpty
                        ? const EmptyView(
                            icon: Icons.inbox_outlined, text: '没有符合条件的任务')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _buildTaskCard(filtered[i]),
                          ),
              ),
              if (_selectMode) _buildSelectBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverallProgress(UploadManager um) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上传中 ${um.activeCount} 个  ·  ${(um.overallProgress * 100).clamp(0, 100).toStringAsFixed(1)}%',
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

  Widget _buildFilterChip(int index, String label, int count) {
    final selected = _filter == index;
    return InkWell(
      onTap: () => setState(() => _filter = index),
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

  bool _isAllSelected(List<UploadTask> list) {
    return list.isNotEmpty && list.every((t) => _selected.contains(t.id));
  }

  // ---------------- 多选 ----------------

  void _enterSelectMode(UploadTask task) {
    setState(() {
      _selectMode = true;
      _selected.add(task.id);
    });
  }

  void _toggleSelect(UploadTask task) {
    setState(() {
      if (!_selected.remove(task.id)) {
        _selected.add(task.id);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  List<UploadTask> _selectedTasks() =>
      _um.tasks.where((t) => _selected.contains(t.id)).toList();

  void _afterBatch(String msg) {
    setState(() {
      _exitSelectMode();
      _busy = false;
    });
    _toast(msg);
  }

  Future<void> _batchPause() async {
    if (_selected.isEmpty) return;
    final list = _selectedTasks().where((t) => t.isActive).toList();
    _um.pauseAll(list);
    _afterBatch('已暂停 ${list.length} 个任务');
  }

  Future<void> _batchResume() async {
    if (_selected.isEmpty) return;
    final list = _selectedTasks()
        .where((t) => t.status == UploadStatus.paused)
        .toList();
    _um.resumeAll(list);
    _afterBatch('已恢复 ${list.length} 个任务');
  }

  Future<void> _batchDelete() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除上传任务'),
        content: const Text('确定删除选中的任务吗？此操作不会删除本地文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: AppColors.of(context).red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _um.removeAll(_selectedTasks());
    _afterBatch('已删除 $count 个任务');
  }

  Widget _buildSelectBar() {
    final count = _selected.length;
    final hasPause = _selectedTasks().any((t) => t.isActive);
    final hasResume =
        _selectedTasks().any((t) => t.status == UploadStatus.paused);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Color(0xFF12121A),
        border: Border(
            top: BorderSide(color: AppColors.of(context).divider, width: 0.5)),
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
              onPressed: _busy || !hasPause ? null : _batchPause,
              icon: Icon(Icons.pause_rounded,
                  color: hasPause && !_busy
                      ? AppColors.of(context).orange
                      : AppColors.of(context).textSecondary),
            ),
            IconButton(
              onPressed: _busy || !hasResume ? null : _batchResume,
              icon: Icon(Icons.play_arrow_rounded,
                  color: hasResume && !_busy
                      ? AppColors.of(context).accent
                      : AppColors.of(context).textSecondary),
            ),
            IconButton(
              onPressed: _busy || count == 0 ? null : _batchDelete,
              icon: Icon(Icons.delete_outline_rounded,
                  color: _busy || count == 0
                      ? AppColors.of(context).textSecondary
                      : AppColors.of(context).red),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 列表项 ----------------

  Widget _buildTaskCard(UploadTask task) {
    final done = task.status == UploadStatus.done;
    final failed = task.status == UploadStatus.failed;
    final canceled = task.status == UploadStatus.canceled;
    final paused = task.status == UploadStatus.paused;
    final active = task.status == UploadStatus.uploading;
    final selected = _selected.contains(task.id);

    return InkWell(
      onTap: _selectMode ? () => _toggleSelect(task) : null,
      onLongPress: _selectMode ? null : () => _enterSelectMode(task),
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
                        _subtitle(task),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.of(context).textSecondary,
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(task),
                if (_selectMode)
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
                    onSelected: (v) => _onTaskMenu(task, v),
                    itemBuilder: (_) => _menuItems(task),
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
                style: TextStyle(
                    color: AppColors.of(context).red, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(UploadTask task) {
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

  void _onTaskMenu(UploadTask task, String v) {
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

  String _subtitle(UploadTask task) {
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

  Widget _buildStatusBadge(UploadTask task) {
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

  void _toast(String msg) {
    if (!mounted) return;
    AppMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}