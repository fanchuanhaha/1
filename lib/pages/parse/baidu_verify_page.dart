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

  /// errno=132 时百度返回的人机验证地址。非空则先让用户在下面的 WebView 里
  /// 完成安全验证，之后自动回到网盘页面重试删除。
  final String? verifyUrl;

  const BaiduVerifyPage({
    super.key,
    required this.cookie,
    this.deletePaths,
    this.verifyUrl,
  });

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

  /// 当前是否处于「先完成人机验证」阶段；验证完成回到网盘后置为 false。
  bool _verifyMode = false;

  /// 网页自动删除是否被百度 errno=132 拦截（此时把真实网盘网页留给用户操作/完成验证）。
  bool _blocked132 = false;

  static const _domainHosts = [
    'passport.baidu.com',
    'pan.baidu.com',
    'yun.baidu.com',
  ];

  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  bool get _deleteMode => (widget.deletePaths?.isNotEmpty ?? false);

  /// 是否已进入「人机验证」：先在验证页完成验证，完成后再回网盘删除。
  bool get _awaitingVerify =>
      _deleteMode && (widget.verifyUrl?.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    _buildController();
    _verifyMode = _awaitingVerify;
    _injectCookies().then((_) {
      // 有验证地址则先加载验证页（真正的安全验证界面），让用户当场完成；
      // 否则直接进网盘首页，自动执行删除。
      final start =
          _awaitingVerify ? widget.verifyUrl! : 'https://pan.baidu.com/disk/main';
      _controller.loadRequest(Uri.parse(start));
    });
    if (_deleteMode) {
      _status = _awaitingVerify
          ? '请先在下方的安全验证页面完成人机验证'
          : '网页会话已就绪后自动删除';
    } else {
      _status = '请在下方完成的验证后点「保存」';
    }
  }

  Future<void> _injectCookies() async {
    final pairs = _cookieToMap(widget.cookie);
    if (pairs.isEmpty) return;
    for (final host in _domainHosts) {
      for (final e in pairs.entries) {
        // BAIDUID/BAIDUID_BFESS 是设备指纹 Cookie。App 登录 Cookie 里它们常是
        // 占位值(=1)，注入后百度风控会将 filemanager 判为可疑而回 132。
        // 这里跳过占位 BAIDUID，让 pan 网页加载时自己生成真实值再用于删除。
        final name = e.key.toLowerCase();
        if ((name == 'baiduid' || name == 'baiduid_bfess') &&
            e.value.trim().length <= 3) {
          continue;
        }
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
          // 正在等人机验证时，不在验证页自动删除；等用户完成验证后点了按钮再回网盘删。
          if (_verifyMode && !_busy && !_done) {
            if (mounted) {
              setState(() {
                _status = '请在下方的安全验证页面完成人机验证；完成后点「验证完成·回网盘删除」';
              });
            }
            return;
          }
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
    // 真实网页端删除走 pan.baidu.com/api/filemanager，参数必须与前台完全一致：
    //   async=2（异步删除）& onnest=fail & opera=delete & channel=chunlei
    //   & web=1 & clienttype=0 & app_id & bdstoken & logid & newVerify=1
    // 且 body 的 filelist 是「路径字符串数组」如 ["/a","/b"]（不是对象数组）。
    // 早期用 async=0 + 对象数组导致即便在 WebView 真实浏览器里也返回 132，
    // 现按实测抓包修正。
    final filelistJson = jsonEncode(widget.deletePaths!); // ["/a","/b"]
    // 必须作为「字符串字面量」传入 URLSearchParams：若直接传数组会变成
    // String(array)="a,b"，传对象数组更会变成 "[object Object]"，导致接口拿不到
    // 真正的 filelist。用 jsonEncode 再包一层生成 JS 字符串字面量。
    final filelistJsString = jsonEncode(filelistJson);
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
  fd.set("filelist", $filelistJsString);
  fd.set("async", "2");
  fd.set("onnest", "fail");
  var q = new URLSearchParams();
  q.set("opera", "delete");
  q.set("async", "2");
  q.set("onnest", "fail");
  q.set("channel", "chunlei");
  q.set("web", "1");
  q.set("clienttype", "0");
  q.set("app_id", "250528");
  q.set("newVerify", "1");
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
      String verifyScene = '';
      String authwidgetText = '';
      try {
        final map = jsonDecode(text) as Map<String, dynamic>;
        errno = (map['errno'] as num?)?.toInt() ?? -1;
        msg = map['errno_msg']?.toString() ?? '';
        // 日志里 132 响应是 {verify_scene, authwidget:{safetpl/…}}，没有可直开的验证 URL。
        verifyScene = map['verify_scene']?.toString() ?? '';
        final aw = map['authwidget'];
        if (aw is Map) authwidgetText = 'safetpl=${aw['safetpl'] ?? '?'}';
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
        // 没有可直接打开的验证 URL，因此保留真实网盘网页，让百度自己的“安全验证”
        // 窗口有机会由 SPA 触发弹出，用户可当场完成或直接在页面里勾选删除。
        AppLogger.I.w('baidu_session',
            '网页删除仍被132拦截 verify_scene=$verifyScene authwidget=$authwidgetText');
        setState(() {
          _busy = false;
          _blocked132 = true;
          _status = '百度仍要求安全验证（$authwidgetText）。下方为真实网盘网页：请完成弹出的安全验证，'
              '或直接在页面里勾选目标文件删除；点「重新加载网页完成验证」看是否弹出验证窗口';
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
    // 被 132 拦截：优先引导重新加载网页完成验证。
    if (_blocked132) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy || _done ? null : _reloadForVerify,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text('重新加载网页完成验证'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy || _done ? null : _onManualDone,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('我已在网页手动删除（点此收尾）'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 处于人机验证阶段：只显示「验证完成·回网盘删除」，不显示删除/手动按钮避免误操作。
    if (_verifyMode && !_done) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || _done ? null : _onVerifyDone,
              icon: const Icon(Icons.verified_user_rounded, size: 20),
              label: const Text('验证完成 · 回到网盘并删除'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy || _done ? null : () => _controller.reload(),
                    child: const Text('刷新页面'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _done ? null : _runDelete,
                    child: const Text('重试删除'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || _done ? null : _onManualDone,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('我已在网页手动删除（点此收尾）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onManualDone() {
    if (_busy || _done) return;
    if (mounted) {
      Navigator.of(context)
          .pop((ok: true, cookie: _currentCookie, msg: '我已在网页手动删除'));
    }
  }

  /// 被 132 拦截后，重新加载真实网盘网页，让百度 SPA 有机会弹出安全验证窗口。
  void _reloadForVerify() {
    if (_busy || _done) return;
    setState(() {
      _blocked132 = false;
      _status = '正在重新加载网页…如有安全验证窗口请完成，完成后可重试删除';
    });
    _controller.reload();
  }

  // ---------------- 验证完成·回网盘删除 ----------------

  /// 用户在验证页完成人机验证后，回到网盘首页并自动执行删除。
  void _onVerifyDone() {
    if (_busy || _done) return;
    setState(() {
      _verifyMode = false;
      _busy = false;
      _status = '验证完成，回到网盘并重试删除…';
      _loading = true;
    });
    _controller
        .loadRequest(Uri.parse('https://pan.baidu.com/disk/main'));
  }
}