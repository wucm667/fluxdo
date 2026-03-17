import 'package:dio/dio.dart';

import '../adapters/platform_adapter.dart';
import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import '../rhttp/rhttp_settings_service.dart';

/// Gateway 反向代理拦截器
///
/// 将 HTTPS 请求改写为 HTTP 指向 localhost gateway 代理，
/// 消除 MITM 双重 TLS 开销。
///
/// **必须放在拦截器链的最后**（cookie/header 等拦截器之后），
/// 确保其他拦截器按原始 URL 正常工作（cookie 域名匹配等）。
/// 响应路径中最先恢复原始 URL，避免 cookie 管理器存到错误域名。
class GatewayProxyInterceptor extends Interceptor {
  static const _originalUriKey = '_gateway_original_uri';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final service = NetworkSettingsService.instance;
    final proxyService = ProxySettingsService.instance;
    final rhttpService = RhttpSettingsService.instance;
    final currentAdapter = getCurrentAdapterType();

    // rhttp 直连时保留原始 https URL
    final shouldUseRhttp = currentAdapter == AdapterType.rhttp ||
        rhttpService.shouldUseRhttp(service.current, proxyService.current);
    if (shouldUseRhttp) {
      handler.next(options);
      return;
    }

    if (!service.isGatewayMode) {
      handler.next(options);
      return;
    }

    final port = service.current.proxyPort;
    if (port == null) {
      handler.next(options);
      return;
    }

    final uri = options.uri;
    if (uri.scheme != 'https') {
      handler.next(options);
      return;
    }

    // 保存原始 URI，响应时恢复（确保 cookie 管理器按正确域名处理）
    options.extra[_originalUriKey] = uri.toString();

    // 始终按当前请求 URL 设置 Host（重定向后 URL 可能变化）
    options.headers['Host'] = uri.host;

    // 改写为明文 HTTP 指向 localhost gateway
    final gatewayUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: uri.path,
      query: uri.query.isEmpty ? null : uri.query,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
    options.baseUrl = '';
    options.path = gatewayUri.toString();

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _restoreOriginalUri(response.requestOptions);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _restoreOriginalUri(err.requestOptions);
    handler.next(err);
  }

  void _restoreOriginalUri(RequestOptions options) {
    final originalUri = options.extra.remove(_originalUriKey) as String?;
    if (originalUri != null) {
      options.baseUrl = '';
      options.path = originalUri;
    }
  }
}
