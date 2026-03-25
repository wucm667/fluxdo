import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'per_device_cert_service.dart';

/// Proxy CA certificate management
///
/// Configures the app to trust the MITM proxy's CA certificate
/// on all platforms.
class ProxyCertificate {
  ProxyCertificate._();

  static bool _initialized = false;

  /// Initialize the security context to trust the proxy CA
  ///
  /// Call this early in app startup (e.g., in main.dart)
  static Future<void> initialize() async {
    if (_initialized) return;

    if (Platform.isIOS) {
      // iOS: 使用 per-device CA 证书
      await _initializeIos();
    } else if (!Platform.isAndroid) {
      // Android: CA 通过 network_security_config.xml 信任
      // 其他平台: 从 assets 加载编译时 CA
      await _configureSecurityContext();
    }

    _initialized = true;
  }

  /// iOS: 初始化 per-device CA 证书
  static Future<void> _initializeIos() async {
    final certService = PerDeviceCertService.instance;
    final ok = await certService.ensureCaCert();
    if (ok && certService.certPem != null) {
      try {
        final certBytes = Uint8List.fromList(certService.certPem!.codeUnits);
        final context = SecurityContext.defaultContext;
        context.setTrustedCertificatesBytes(certBytes);
        debugPrint('ProxyCertificate: iOS per-device CA loaded');
      } catch (e) {
        debugPrint('ProxyCertificate: Could not load per-device CA: $e');
      }

      // 将 per-device CA 发送到原生层
      await _sendCaCertToNative(certService.certPem!);
    } else {
      debugPrint('ProxyCertificate: iOS per-device CA not ready');
    }
  }

  /// Configure the global security context to trust the proxy CA
  static Future<void> _configureSecurityContext() async {
    try {
      // Load the CA certificate from assets
      final certData = await rootBundle.load('assets/certs/proxy_ca.pem');
      final certBytes = certData.buffer.asUint8List();

      // Get the global security context
      final context = SecurityContext.defaultContext;

      // Add the CA as a trusted certificate
      context.setTrustedCertificatesBytes(certBytes);

      debugPrint('ProxyCertificate: CA certificate loaded successfully');
    } catch (e) {
      // Certificate might already be trusted or file not found
      // This is not fatal - Android uses network_security_config
      debugPrint('ProxyCertificate: Could not load CA certificate: $e');
    }
  }

  static const _proxyCertChannel = MethodChannel('com.fluxdo/proxy_cert');

  /// 将 CA 证书发送到原生层，供 WKWebView SSL challenge 原生拦截使用
  static Future<void> _sendCaCertToNative(String pem) async {
    try {
      await _proxyCertChannel.invokeMethod('setCaCertPem', pem);
      debugPrint('ProxyCertificate: CA cert sent to native handler');
    } catch (e) {
      debugPrint('ProxyCertificate: Failed to send CA cert to native: $e');
    }
  }

  /// Get the CA certificate PEM content for display or export
  static Future<String?> getCertificatePem() async {
    if (Platform.isIOS) {
      final certService = PerDeviceCertService.instance;
      if (certService.isLoaded) return certService.certPem;
      await certService.ensureCaCert();
      return certService.certPem;
    }
    try {
      return await rootBundle.loadString('assets/certs/proxy_ca.pem');
    } catch (e) {
      return null;
    }
  }
}
