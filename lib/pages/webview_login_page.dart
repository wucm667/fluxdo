import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/preferences_provider.dart';
import '../services/credential_store_service.dart';
import '../services/discourse/discourse_service.dart';
import '../services/preloaded_data_service.dart';
import '../services/network/cookie/cookie_jar_service.dart';
import '../services/network/cookie/cookie_sync_service.dart';
import '../services/toast_service.dart';
import '../services/webview_settings.dart';

/// WebView 登录页面（统一使用 flutter_inappwebview）
class WebViewLoginPage extends ConsumerStatefulWidget {
  const WebViewLoginPage({super.key});

  @override
  ConsumerState<WebViewLoginPage> createState() => _WebViewLoginPageState();
}

class _WebViewLoginPageState extends ConsumerState<WebViewLoginPage> {
  final _service = DiscourseService();
  final _cookieJar = CookieJarService();
  final _credentialStore = CredentialStoreService();
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String _url = 'https://linux.do/';
  double _progress = 0;
  String? _savedUsername;

  @override
  void initState() {
    super.initState();
    _cookieJar.syncToWebView();
    _loadSavedUsername();
  }

  Future<void> _loadSavedUsername() async {
    final credentials = await _credentialStore.load();
    if (mounted && credentials.username != null && credentials.username!.isNotEmpty) {
      setState(() => _savedUsername = credentials.username);
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
      appBar: AppBar(
        title: const Text('登录 Linux.do'),
        actions: [
          if (_savedUsername != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.key_rounded),
              tooltip: '已保存的密码',
              onSelected: (value) {
                if (value == 'clear') _clearCredentials();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text('上次登录: @$_savedUsername'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('清除已保存的密码'),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _controller?.reload(), tooltip: '刷新'),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading) LinearProgressIndicator(value: _progress),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Icon(Icons.lock, size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_url, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('https://linux.do/login')),
              initialSettings: WebViewSettings.visible,
              onWebViewCreated: (controller) {
                _controller = controller;
                // 注册 JS Handler，用于在登录按钮点击时接收凭证
                controller.addJavaScriptHandler(
                  handlerName: 'onLoginCredentials',
                  callback: (args) {
                    if (args.isNotEmpty && ref.read(preferencesProvider).autoFillLogin) {
                      try {
                        final data = args[0] as Map<String, dynamic>;
                        final username = data['username'] as String?;
                        final password = data['password'] as String?;
                        if (username != null && username.isNotEmpty && password != null && password.isNotEmpty) {
                          _credentialStore.save(username, password);
                          if (mounted) setState(() => _savedUsername = username);
                        }
                      } catch (_) {}
                    }
                  },
                );
              },
              onLoadStart: (controller, url) => setState(() { _isLoading = true; _url = url?.toString() ?? ''; }),
              onProgressChanged: (controller, progress) => setState(() => _progress = progress / 100),
              onLoadStop: (controller, url) async {
                setState(() { _isLoading = false; _url = url?.toString() ?? ''; });
                // 自动填充登录表单
                await _autoFillLoginForm(controller, url);
                // 自动检测登录状态
                await _checkLoginStatus(controller);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除已保存的密码'),
        content: const Text('确定要清除已保存的登录凭证吗？下次登录时需要手动输入。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('清除')),
        ],
      ),
    );
    if (confirmed == true) {
      await _credentialStore.clear();
      if (mounted) setState(() => _savedUsername = null);
    }
  }

  /// 自动填充登录表单 + 注入凭证捕获脚本
  Future<void> _autoFillLoginForm(InAppWebViewController controller, WebUri? url) async {
    final autoFill = ref.read(preferencesProvider).autoFillLogin;
    if (!autoFill) return;

    final urlStr = url?.toString() ?? '';
    if (!urlStr.contains('linux.do')) return;

    final credentials = await _credentialStore.load();
    final hasCredentials = credentials.username != null && credentials.username!.isNotEmpty
        && credentials.password != null && credentials.password!.isNotEmpty;

    // 转义特殊字符防止 JS 注入
    final escapedUsername = hasCredentials ? jsonEncode(credentials.username!) : 'null';
    final escapedPassword = hasCredentials ? jsonEncode(credentials.password!) : 'null';

    await controller.evaluateJavascript(source: '''
      (function() {
        var savedUser = $escapedUsername;
        var savedPass = $escapedPassword;
        var filled = false;
        var hooked = false;
        var attempts = 0;
        var timer = setInterval(function() {
          var userInput = document.getElementById('login-account-name');
          var passInput = document.getElementById('login-account-password');
          if (userInput && passInput) {
            // 自动填充（仅一次）
            if (!filled && savedUser && savedPass) {
              filled = true;
              userInput.value = savedUser;
              passInput.value = savedPass;
              userInput.dispatchEvent(new Event('input', {bubbles: true}));
              passInput.dispatchEvent(new Event('input', {bubbles: true}));
            }
            // 监听登录按钮点击，在提交前捕获凭证
            if (!hooked) {
              hooked = true;
              var loginBtn = document.getElementById('login-button');
              if (loginBtn) {
                loginBtn.addEventListener('click', function() {
                  var u = document.getElementById('login-account-name');
                  var p = document.getElementById('login-account-password');
                  if (u && p && u.value && p.value) {
                    window.flutter_inappwebview.callHandler('onLoginCredentials', {
                      username: u.value,
                      password: p.value
                    });
                  }
                }, true);
              }
            }
            clearInterval(timer);
          }
          if (++attempts > 30) clearInterval(timer);
        }, 300);
      })();
    ''');
  }

  /// 检测登录状态，登录成功自动关闭
  Future<void> _checkLoginStatus(InAppWebViewController controller) async {
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(url: WebUri('https://linux.do/'));

    String? tToken;

    for (final cookie in cookies) {
      if (cookie.name == '_t') { tToken = cookie.value; break; }
    }

    if (tToken == null || tToken.isEmpty) return;

    // 尝试从页面获取用户名
    String? username;
    try {
      final result = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            var meta = document.querySelector('meta[name="current-username"]');
            if (meta && meta.content) return meta.content;
            if (typeof Discourse !== 'undefined' && Discourse.User && Discourse.User.current()) {
              return Discourse.User.current().username;
            }
            return null;
          } catch(e) { return null; }
        })();
      ''');

      if (result != null && result.toString().isNotEmpty && result.toString() != 'null') {
        username = result.toString();
      }
    } catch (_) {}

    // 保存用户名
    if (username != null && username.isNotEmpty) {
      await _service.saveUsername(username);
    }
    // 同步 CSRF（从页面 meta 获取）
    try {
      final csrf = await controller.evaluateJavascript(source: '''
        (function() {
          var meta = document.querySelector('meta[name="csrf-token"]');
          return meta && meta.content ? meta.content : null;
        })();
      ''');
      if (csrf != null && csrf.toString().isNotEmpty && csrf.toString() != 'null') {
        CookieSyncService().setCsrfToken(csrf.toString());
      }
    } catch (_) {}
    // 登录后从 WebView 同步所有 Cookie 到 CookieJar（包括 _t、cf_clearance 等）
    await _cookieJar.syncFromWebView();
    // 更新内存状态并通知监听者
    _service.onLoginSuccess(tToken);
    // 登录后重新加载预热数据
    await PreloadedDataService().refresh();

    if (mounted) {
      ToastService.showSuccess('登录成功！${username != null ? '用户: $username' : ''}');
      Navigator.of(context).pop(true);
    }
  }
}
