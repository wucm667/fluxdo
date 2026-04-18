import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../l10n/s.dart';

/// 底栏导航快捷动作总线
///
/// 底栏点击已选中的 tab 时，由底栏组件按用户偏好派发动作到总线。
/// 目标页面（TopicsScreen / ProfilePage）按 id 监听 [navActionBusProvider] 执行实际动作。
///
/// 分层原因：页面各自维护自己的 ScrollController / 刷新逻辑，底栏不关心细节；
/// 总线保证底栏和页面解耦。

/// 派发到页面的实际动作
enum NavAction {
  scrollToTop,
  refresh,
}

/// 用户可为单击 / 双击配置的动作（含"无"选项）
///
/// 比 [NavAction] 多出 [none]——用户主动把某个手势关掉时使用。
/// 未来扩展通知 / 搜索 / 发帖等面板型动作时加到这里。
enum NavTapAction {
  none,
  scrollToTop,
  refresh,
}

extension NavTapActionX on NavTapAction {
  /// 转换为实际派发的 [NavAction]；[none] 返回 null 表示不派发。
  NavAction? toNavAction() {
    switch (this) {
      case NavTapAction.none:
        return null;
      case NavTapAction.scrollToTop:
        return NavAction.scrollToTop;
      case NavTapAction.refresh:
        return NavAction.refresh;
    }
  }

  /// 对应的反馈图标。用于底栏已选中 tab 滚离顶部时做图标替换。
  /// [none] 没有图标，因为不会切换。
  IconData? get icon {
    switch (this) {
      case NavTapAction.none:
        return null;
      case NavTapAction.scrollToTop:
        return Icons.keyboard_double_arrow_up_rounded;
      case NavTapAction.refresh:
        return Icons.refresh_rounded;
    }
  }

  /// 本地化标签。用于设置页 picker 和副标题。
  /// 不依赖 BuildContext，方便在 defs 中通过 `S.current` 访问。
  String get label {
    final l10n = S.current;
    switch (this) {
      case NavTapAction.none:
        return l10n.navTapAction_none;
      case NavTapAction.scrollToTop:
        return l10n.navTapAction_scrollToTop;
      case NavTapAction.refresh:
        return l10n.navTapAction_refresh;
    }
  }

  /// 持久化的稳定字符串（enum.name 会随 refactor 改变，显式 switch 更稳）
  String toStorageKey() {
    switch (this) {
      case NavTapAction.none:
        return 'none';
      case NavTapAction.scrollToTop:
        return 'scroll_to_top';
      case NavTapAction.refresh:
        return 'refresh';
    }
  }

  static NavTapAction fromStorageKey(
    String? key, {
    NavTapAction fallback = NavTapAction.scrollToTop,
  }) {
    switch (key) {
      case 'none':
        return NavTapAction.none;
      case 'scroll_to_top':
        return NavTapAction.scrollToTop;
      case 'refresh':
        return NavTapAction.refresh;
      default:
        return fallback;
    }
  }
}

/// 一次派发的动作事件
///
/// [nonce] 单调递增，保证连续两次相同事件也能被 Riverpod 监听捕获
/// （StateProvider 会对 == 相等的新旧值去重，nonce 让事件永远不等）。
class NavActionEvent {
  final String targetId;
  final NavAction action;
  final int nonce;

  const NavActionEvent({
    required this.targetId,
    required this.action,
    required this.nonce,
  });
}

/// 内部递增计数器
final _navActionNonceProvider = StateProvider<int>((ref) => 0);

/// 动作事件总线。页面通过 `ref.listen(navActionBusProvider, ...)` 订阅。
final navActionBusProvider = StateProvider<NavActionEvent?>((ref) => null);

/// 派发入口
extension NavActionDispatch on WidgetRef {
  void dispatchNavAction(String targetId, NavAction action) {
    final next = read(_navActionNonceProvider) + 1;
    read(_navActionNonceProvider.notifier).state = next;
    read(navActionBusProvider.notifier).state = NavActionEvent(
      targetId: targetId,
      action: action,
      nonce: next,
    );
  }
}

/// 每个 tab 的"距顶进度"。页面按 id 更新，底栏 watch 用来切换图标。
///
/// 值含义：
///  - 0.0：当前在顶部（或距顶很近）
///  - 1.0：已滚离顶部足够距离，可以显示动作图标
///
/// 页面侧建议用 `(offset / 220).clamp(0.0, 1.0)` 归一化。
final navScrollProgressProvider =
    StateProvider.family<double, String>((ref, id) => 0.0);

/// 已注册的 entry id。未来扩展时加到这里。
class NavEntryIds {
  NavEntryIds._();

  static const String home = 'home';
  static const String profile = 'profile';
}
