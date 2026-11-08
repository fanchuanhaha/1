import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

const _imageExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif', 'avif'
};

const _videoExtensions = {
  'mp4', 'mkv', 'avi', 'mov', 'flv', 'ts', 'webm', 'm4v', 'wmv', 'rmvb',
  'rm', '3gp', 'mpg', 'mpeg'
};

String _extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool isImageFileName(String name) => _imageExtensions.contains(_extOf(name));

bool isVideoFileName(String name) => _videoExtensions.contains(_extOf(name));

/// 预览所需的直链与请求头。
class MediaPreviewSource {
  final String url;
  final Map<String, String> headers;

  const MediaPreviewSource({required this.url, this.headers = const {}});
}

/// 通用图片/视频查看页，直链由调用方按网盘类型异步解析。
class MediaPreviewPage extends StatefulWidget {
  final String title;
  final bool isVideo;
  final Future<MediaPreviewSource?> Function() resolve;

  const MediaPreviewPage({
    super.key,
    required this.title,
    required this.isVideo,
    required this.resolve,
  });

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage> {
  MediaPreviewSource? _source;
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final src = await widget.resolve();
      if (src == null || src.url.isEmpty) {
        throw Exception('无法获取预览地址');
      }
      if (!widget.isVideo) {
        if (!mounted) return;
        setState(() {
          _source = src;
          _loading = false;
        });
        return;
      }
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(src.url),
        httpHeaders: src.headers,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _source = src;
        _controller = ctrl;
        _loading = false;
      });
      ctrl.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '加载失败：$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      );
    }
    if (widget.isVideo) {
      return _buildVideo();
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.network(
          _source!.url,
          headers: _source!.headers,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
                child: CircularProgressIndicator(color: Colors.white70));
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Text('图片加载失败',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final ctrl = _controller;
    if (ctrl == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _togglePlay,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio == 0
                  ? 16 / 9
                  : ctrl.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(ctrl),
                  if (!ctrl.value.isPlaying)
                    const Icon(Icons.play_circle_fill_rounded,
                        color: Colors.white70, size: 64),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: ctrl,
            builder: (context, value, _) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Text(
                      _fmt(value.position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: value.duration.inMilliseconds == 0
                            ? 0
                            : (value.position.inMilliseconds /
                                    value.duration.inMilliseconds)
                                .clamp(0.0, 1.0),
                        activeColor: AppColors.of(context).accent,
                        onChanged: (v) => ctrl.seekTo(Duration(
                            milliseconds:
                                (v * value.duration.inMilliseconds).round())),
                      ),
                    ),
                    Text(
                      _fmt(value.duration),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
      } else {
        ctrl.play();
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
