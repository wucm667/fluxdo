import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/s.dart';
import '../../../models/emoji.dart';
import '../../../utils/platform_utils.dart';
import '../../markdown_editor/emoji_picker.dart';

/// 以底部浮层方式显示 Boost 输入框
/// 返回用户输入的文本，用户取消则返回 null
Future<String?> showBoostInputSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const _BoostInputSheet(),
  );
}

class _BoostInputSheet extends ConsumerStatefulWidget {
  const _BoostInputSheet();

  @override
  ConsumerState<_BoostInputSheet> createState() => _BoostInputSheetState();
}

class _BoostInputSheetState extends ConsumerState<_BoostInputSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  // 默认展开表情面板，避免浮层过小
  bool _showEmojiPanel = true;

  static const int _maxVisibleLength = 16;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int get _visibleLength {
    final text = _controller.text;
    return text.replaceAll(RegExp(r':[a-z0-9_+-]+:'), 'x').length;
  }

  bool get _canSubmit => _controller.text.trim().isNotEmpty && _visibleLength <= _maxVisibleLength;

  void _handleSubmit() {
    if (!_canSubmit) return;
    Navigator.pop(context, _controller.text.trim());
  }

  void _insertEmoji(Emoji emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    final shortcode = ':${emoji.name}:';

    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    final newText = text.replaceRange(start, end, shortcode);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: start + shortcode.length,
    );
    setState(() {});
  }

  void _toggleEmojiPanel() {
    setState(() {
      _showEmojiPanel = !_showEmojiPanel;
      if (_showEmojiPanel) {
        _focusNode.unfocus();
      } else {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: _showEmojiPanel ? 0 : bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖拽指示条
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // 输入区域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // 表情按钮
                IconButton(
                  onPressed: _toggleEmojiPanel,
                  icon: Icon(
                    _showEmojiPanel
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                // 输入框
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: theme.textTheme.bodyMedium,
                    maxLength: 30,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      hintText: context.l10n.boost_placeholder,
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      counterText: '',
                      suffixText: '$_visibleLength/$_maxVisibleLength',
                      suffixStyle: theme.textTheme.labelSmall?.copyWith(
                        color: _visibleLength > _maxVisibleLength
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _handleSubmit(),
                    onTap: () {
                      // 移动端：点击输入框时收起表情面板（让虚拟键盘接管）
                      // 桌面端：保持表情面板，因为没有虚拟键盘来填充空间
                      if (_showEmojiPanel && PlatformUtils.isMobile) {
                        setState(() => _showEmojiPanel = false);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // 发送按钮
                IconButton(
                  onPressed: _canSubmit ? _handleSubmit : null,
                  icon: Icon(
                    Icons.send_rounded,
                    color: _canSubmit
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.3),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Emoji 面板
          if (_showEmojiPanel)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (emoji) => _insertEmoji(emoji),
              ),
            ),

          // 底部安全区
          if (!_showEmojiPanel) SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
