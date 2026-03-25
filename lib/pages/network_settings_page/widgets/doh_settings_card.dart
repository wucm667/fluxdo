import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/s.dart';
import '../../../services/network/doh/network_settings_service.dart';
import '../../../services/network/doh_proxy/per_device_cert_service.dart';
import '../../../services/network/vpn_auto_toggle_service.dart';
import '../../../services/toast_service.dart';
import '../doh_detail_settings_page.dart';
import 'ios_cert_install_dialog.dart';

/// DOH 设置卡片（简化版：开关 + 状态 + "更多设置"入口）
class DohSettingsCard extends StatelessWidget {
  const DohSettingsCard({
    super.key,
    required this.settings,
    required this.isApplying,
    this.isSuppressedByVpn = false,
  });

  final NetworkSettings settings;
  final bool isApplying;
  final bool isSuppressedByVpn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NetworkSettingsService.instance;
    final proxyService = service.proxyService;
    final isRunning = proxyService.isRunning;
    final port = settings.proxyPort;
    final showLoading = isApplying ||
        service.pendingStart ||
        (settings.dohEnabled && !isRunning && !service.lastStartFailed);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: settings.dohEnabled
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: settings.dohEnabled
            ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Column(
        children: [
          // DOH 开关
          SwitchListTile(
            title: const Text('DNS over HTTPS'),
            subtitle: Text(
              isSuppressedByVpn
                  ? context.l10n.dohSettings_suppressedByVpn
                  : settings.dohEnabled
                      ? context.l10n.dohSettings_enabledDesc
                      : context.l10n.dohSettings_disabledDesc,
            ),
            secondary: Icon(
              settings.dohEnabled ? Icons.shield : Icons.shield_outlined,
              color: settings.dohEnabled ? theme.colorScheme.primary : null,
            ),
            value: settings.dohEnabled,
            onChanged: (value) async {
              await service.setDohEnabled(value);
              if (value && isSuppressedByVpn) {
                VpnAutoToggleService.instance.clearDohSuppression();
              }
            },
          ),

          // 仅在开启 DOH 后显示以下内容
          if (settings.dohEnabled) ...[
            // iOS 证书安装引导
            if (Platform.isIOS) _IosCertGuide(isApplying: isApplying),

            // 状态区域
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
            _buildStatusArea(context, theme, service, proxyService, isRunning, port, showLoading),

            // 启动失败提示
            if (!isRunning && !isApplying && service.lastStartFailed)
              _buildFailureHint(context, theme, service, proxyService),

            // 更多设置入口
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(context.l10n.dohSettings_moreSettings),
              subtitle: Text(context.l10n.dohSettings_moreSettingsDesc),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DohDetailSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusArea(
    BuildContext context,
    ThemeData theme,
    NetworkSettingsService service,
    dynamic proxyService,
    bool isRunning,
    int? port,
    bool showLoading,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showLoading
                ? _buildStatusChip(
                    theme,
                    key: const ValueKey('applying'),
                    customIcon: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    label: service.wasRunningBeforeApply ? context.l10n.dohSettings_restarting : context.l10n.dohSettings_starting,
                    color: theme.colorScheme.primary,
                  )
                : _buildStatusChip(
                    theme,
                    key: ValueKey('status_${isRunning}_${service.lastStartFailed}'),
                    icon: isRunning
                        ? Icons.check_circle
                        : service.lastStartFailed
                            ? Icons.error
                            : Icons.hourglass_top,
                    label: isRunning ? context.l10n.dohSettings_proxyRunning : context.l10n.dohSettings_proxyNotStarted,
                    color: isRunning ? Colors.green : theme.colorScheme.error,
                  ),
          ),
          const SizedBox(width: 12),
          if (port != null && isRunning)
            _buildStatusChip(
              theme,
              icon: Icons.lan,
              label: context.l10n.dohSettings_port(port),
              color: theme.colorScheme.secondary,
            ),
          if (isRunning) ...[
            const Spacer(),
            IconButton(
              onPressed: isApplying ? null : service.restartProxy,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: context.l10n.dohSettings_restartProxy,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFailureHint(
    BuildContext context,
    ThemeData theme,
    NetworkSettingsService service,
    dynamic proxyService,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.dohSettings_proxyStartFailed,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: isApplying ? null : service.restartProxy,
                child: Text(context.l10n.common_retry),
              ),
            ],
          ),
          if (proxyService.lastError != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      proxyService.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: proxyService.lastError!));
                      ToastService.showInfo(S.current.dohSettings_errorCopied);
                    },
                    child: Icon(
                      Icons.copy,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    ThemeData theme, {
    Key? key,
    IconData? icon,
    Widget? customIcon,
    required String label,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (customIcon != null)
            customIcon
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// iOS 证书安装引导 Widget
///
/// 显示一个提示条，点击后打开证书安装对话框
class _IosCertGuide extends StatefulWidget {
  const _IosCertGuide({required this.isApplying});

  final bool isApplying;

  @override
  State<_IosCertGuide> createState() => _IosCertGuideState();
}

class _IosCertGuideState extends State<_IosCertGuide> {
  bool _installed = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkInstalled();
  }

  Future<void> _checkInstalled() async {
    final installed = await PerDeviceCertService.instance.isCertInstalled();
    if (mounted) setState(() { _installed = installed; _loading = false; });
  }

  Future<void> _showDialog() async {
    final result = await showIosCertInstallDialog(context);
    if (result == true && mounted) {
      setState(() => _installed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
        ListTile(
          leading: Icon(
            _installed ? Icons.verified_user : Icons.security,
            color: _installed ? Colors.green : theme.colorScheme.error,
          ),
          title: Text(_installed ? 'CA 证书已安装' : '需要安装 CA 证书'),
          subtitle: Text(
            _installed ? '点击可重新安装或更换证书' : 'HTTPS 拦截需要安装并信任证书',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
          ),
          trailing: _installed
              ? OutlinedButton(
                  onPressed: _showDialog,
                  child: const Text('重新安装'),
                )
              : FilledButton(
                  onPressed: _showDialog,
                  child: const Text('安装'),
                ),
        ),
      ],
    );
  }
}
