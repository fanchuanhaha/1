import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';

/// 百度「浏览器会话」操作页。
///
/// 背景：百度 filemanager（删除/移动等）对 Dio 的 Cookie 会话会抛 errno=132
/// （风控安全验证，verify_scene 拒绝下发验证），但同样的账号在真实浏览器网页里
/// 删除却完全正常、无任何验证。差异在于请求环境是否“像真实浏览器”。
///
/// 本页用系统 WebView（真实 Chromium 内核，指纹/JS/Canvas 都真实）加载已登录的
/// 百度网盘，并支持两种模式：
///  1. verifyOnly（deletePaths 为空）：载入网盘首页，让用户完成任何安全验证后保存 Cookie。
///  2. 删除模式（deletePaths 非空）：在浏览器会话内直接执行 filemanager 删除，
///     与网页前台同源、携带完整浏览器 Cookie，因此能像网页一样删除成功。
class BaiduVerifyPage extends StatefulWidget {
  /// 当前百度 Cookie（BDUSS=xxx; STOKEN=xxx; ...）
  final String cookie;

  /// 需要删除的文件路径列表（百度 fid 即云盘绝对路径）；为 null 时进入纯验证模式。
  final List<String>? deletePaths;

  const BaiduVerifyPage({super.key, required this.cookie, this.deletePaths});

  @override
  State<BaiduVerifyPage> createState() => _BaiduVerifyPageState();
}

class _BaiduVerifyPageState extends State<BaiduVerifyPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _busy = false;
  String _status = '';
  bool _done = false;
  String _currentCookie = '';

  static const _domainHosts = [
    'passport.baidu.com',
    'pan.baidu.com',
    'yun.baidu.com',
  ];

  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  bool get _deleteMode => (widget.deletePaths?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _buildController();
    // 先注入登录 Cookie，再加载页面，确保 WebView 里是已登录的百度网盘。
    _injectCookies().then((_) {
      _controller.loadRequest(Uri.parse('https://pan.baidu.com/disk/main'));
    });
    if (_deleteMode) {
      _status = '网页会话已就绪后自动删除';
    } else {
      _status = '请在下方完成的验证后点「保存」';
    }
  }

  Future<void> _injectCookies() async {
    final pairs = _cookieToMap(widget.cookie);
    if (pairs.isEmpty) return;
    for (final host in _domainHosts) {
      for (final e in pairs.entries) {
        try {
          await WebViewCookieManager().setCookie(WebViewCookie(
            name: e.key,
            value: e.value,
            domain: host,
            path: '/',
          ));
        } catch (err) {
          AppLogger.I.w('baidu_session', '注入 cookie 失败 $host/${e.key}: $err');
        }
      }
    }
  }

  void _buildController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_desktopUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _refreshCookie();
          // 页面就绪且为删除模式时自动执行删除。
          if (_deleteMode && !_busy && !_done) {
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted && !_busy && !_done) _runDelete();
            });
          }
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ));
  }

  static Map<String, String> _cookieToMap(String cookie) {
    final map = <String, String>{};
    for (final seg in cookie.split(';')) {
      final idx = seg.indexOf('=');
      if (idx <= 0) continue;
      final k = seg.substring(0, idx).trim();
      final v = seg.substring(idx + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) map[k] = v;
    }
    return map;
  }

  Future<void> _refreshCookie() async {
    try {
      final allParts = <String>{};
      for (final host in _domainHosts) {
        final cookies = await WebViewCookieManager()
            .getCookies(domain: Uri.parse('https://$host/'));
        for (final c in cookies) {
          if (c.name.isNotEmpty && c.value.isNotEmpty) {
            allParts.add('${c.name}=${c.value}');
          }
        }
      }
      _currentCookie = allParts.isNotEmpty
          ? allParts.join('; ')
          : widget.cookie;
      if (!_currentCookie.contains('BDUSS') && widget.cookie.contains('BDUSS')) {
        _currentCookie = widget.cookie;
      }
    } catch (e) {
      AppLogger.I.w('baidu_session', '读取 cookie 失败: $e');
      _currentCookie = widget.cookie;
    }
  }

  // ---------------- 删除执行 ----------------

  String _buildDeleteJs() {
    // 网页端真实删除走 pan.baidu.com/api/filemanager（不是 rest/2.0/xpan/file）。
    // 关键点：与前端一致携带 opera=delete & async=0 & onnest=fail & channel=chunlei
    // & web=1 & clienttype=0 & app_id & bdstoken & logid，且 filelist 为对象数组。
    final list = widget.deletePaths!.map((p) => {'path': p}).toList();
    final filelistJson = jsonEncode(list);
    return '''
(async function(){
  var bt = "";
  var logid = "";
  try {
    var r = await (await fetch("/api/gettemplatevariable?fields=[\"bdstoken\",\"logid\"]&clienttype=0&web=1", {credentials:"same-origin"})).json();
    var res = (r && r.result) || {};
    bt = res.bdstoken || "";
    logid = res.logid || "";
  } catch(e){}
  var fd = new URLSearchParams();
  fd.set("async","0");
  fd.set("onnest","fail");
  fd.set("filelist", $filelistJson);
  var q = new URLSearchParams();
  q.set("opera","delete");
  q.set("channel","chunlei");
  q.set("web","1");
  q.set("clienttype","0");
  q.set("app_id","250528");
  if (bt) q.set("bdstoken", bt);
  if (logid) q.set("logid", logid);
  try {
    var resp = await fetch("/api/filemanager?"+q.toString(), {
      method:"POST",
      credentials:"same-origin",
      headers:{"Content-Type":"application/x-www-form-urlencoded","X-Requested-With":"XMLHttpRequest","Referer": location.href},
      body: fd.toString()
    });
    return await resp.text();
  } catch(e){ return "__ERR__"+e; }
})()
''';
  }

  String _unwrapResult(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      try {
        s = jsonDecode(s) as String;
      } catch (_) {
        s = s.substring(1, s.length - 1);
      }
    }
    return s.trim();
  }

  Future<void> _runDelete() async {
    if (_busy || _done || !_deleteMode) return;
    setState(() {
      _busy = true;
      _status = '正在通过网页会话删除…';
    });
    try {
      final raw = await _controller.runJavaScriptReturningResult(_buildDeleteJs());
      final text = _unwrapResult(raw.toString());
      AppLogger.I.i('baidu_session', '删除结果=$text');
      int errno = -1;
      String msg = '';
      try {
        final map = jsonDecode(text) as Map<String, dynamic>;
        errno = (map['errno'] as num?)?.toInt() ?? -1;
        msg = map['errno_msg']?.toString() ?? '';
      } catch (_) {
        if (text.startsWith('__ERR__')) {
          msg = '页面脚本异常: ${text.replaceFirst('__ERR__', '')}';
        } else {
          msg = '无法解析删除结果';
        }
      }
      await _refreshCookie();
      if (!mounted) return;
      if (errno == 0) {
        setState(() {
          _done = true;
          _busy = false;
          _status = '删除成功';
        });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            Navigator.of(context)
                .pop((ok: true, cookie: _currentCookie, msg: '删除成功'));
          }
        });
      } else if (errno == 132) {
        setState(() {
          _busy = false;
          _status = '仍被安全验证拦截，请在下方网页完成验证后点「重试删除」';
        });
      } else {
        setState(() {
          _busy = false;
          _status = '删除未成功(errno=$errno ${msg.isEmpty ? '' : '· $msg'})，可点「重试删除」';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '执行出错: $e';
      });
    }
  }

  // ---------------- 纯验证模式保存 ----------------

  void _onSave() {
    if (widget.cookie.isEmpty && _currentCookie.isEmpty) {
      return;
    }
    if (mounted) {
      Navigator.of(context).pop((ok: false, cookie: _currentCookie, msg: '已保存'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_deleteMode ? '百度网盘 · 网页删除' : '百度网盘 · 安全验证'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () => _controller.reload(),
          ),
          if (!_deleteMode)
            TextButton.icon(
              onPressed: _onSave,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('保存',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).accent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _statusBanner(),
          const SizedBox(height: 6),
          Expanded(child: WebViewWidget(controller: _controller)),
          if (_deleteMode)
            _deleteActionBar(),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    final accent = AppColors.of(context).accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: accent.withOpacity(0.25),
      child: Row(
        children: [
          if (_busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_done)
            Icon(Icons.check_circle_rounded, size: 16, color: accent)
          else
            Icon(Icons.verified_user_outlined, size: 16, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _status,
              style: TextStyle(
                  color: AppColors.of(context).textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deleteActionBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy || _done
                    ? null
                    : () => _controller.reload(),
                child: const Text('刷新页面'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy || _done ? null : _runDelete,
                child: Text(_done ? '已完成' : '重试删除'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}