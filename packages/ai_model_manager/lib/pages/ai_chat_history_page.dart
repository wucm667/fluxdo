import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_chat_message.dart';
import '../providers/ai_provider_providers.dart';

/// 打开会话回调类型
typedef OpenSessionCallback = void Function(
    BuildContext context, int topicId, String sessionId);

/// AI 会话历史管理页面
/// 两级结构：第一级话题，第二级会话
class AiChatHistoryPage extends ConsumerStatefulWidget {
  /// 点击会话时的回调，由外部实现导航逻辑
  final OpenSessionCallback? onOpenSession;

  const AiChatHistoryPage({super.key, this.onOpenSession});

  @override
  ConsumerState<AiChatHistoryPage> createState() => _AiChatHistoryPageState();
}

class _AiChatHistoryPageState extends ConsumerState<AiChatHistoryPage> {
  late List<TopicSessionGroup> _groups;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final storageService = ref.read(aiChatStorageServiceProvider);
    _groups = storageService.getAllTopicsWithSessions();
  }

  int get _totalSessionCount =>
      _groups.fold(0, (sum, g) => sum + g.sessions.length);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话记录'),
        actions: [
          if (_groups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清除所有对话',
              onPressed: () => _confirmDeleteAll(context),
            ),
        ],
      ),
      body: _groups.isEmpty
          ? _buildEmpty(theme)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return _TopicGroupTile(
                  group: group,
                  onOpenSession: widget.onOpenSession,
                  onDeleteSession: (sessionId) =>
                      _deleteSession(group.topicId, sessionId),
                  onDeleteTopic: () => _deleteTopic(group.topicId),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无会话记录',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSession(int topicId, String sessionId) async {
    final storageService = ref.read(aiChatStorageServiceProvider);
    await storageService.deleteSession(topicId, sessionId);
    setState(() => _reload());
  }

  Future<void> _deleteTopic(int topicId) async {
    final storageService = ref.read(aiChatStorageServiceProvider);
    await storageService.deleteAllTopicSessions(topicId);
    setState(() => _reload());
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除所有对话'),
        content: Text('确定要删除全部 $_totalSessionCount 条会话记录吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final storageService = ref.read(aiChatStorageServiceProvider);
              await storageService.deleteAllSessions();
              if (mounted) {
                setState(() => _reload());
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
  }
}

/// 话题分组 Tile（可展开）
class _TopicGroupTile extends StatelessWidget {
  final TopicSessionGroup group;
  final OpenSessionCallback? onOpenSession;
  final Future<void> Function(String sessionId) onDeleteSession;
  final VoidCallback onDeleteTopic;

  const _TopicGroupTile({
    required this.group,
    this.onOpenSession,
    required this.onDeleteSession,
    required this.onDeleteTopic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topicTitle = group.topicTitle ?? '话题 #${group.topicId}';

    return ExpansionTile(
      leading: Icon(
        Icons.topic_outlined,
        size: 20,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        topicTitle,
        style: theme.textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${group.sessions.length} 条会话',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
            tooltip: '删除此话题所有会话',
            onPressed: () => _confirmDeleteTopic(context, topicTitle),
          ),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
      children: group.sessions.map((session) {
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 56, right: 16),
          leading: Icon(
            Icons.chat_bubble_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            session.title ?? '未命名会话',
            style: theme.textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatTime(session.updatedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              Icons.close,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => onDeleteSession(session.id),
          ),
          onTap: onOpenSession != null
              ? () => onOpenSession!(context, group.topicId, session.id)
              : null,
        );
      }).toList(),
    );
  }

  void _confirmDeleteTopic(BuildContext context, String topicTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除话题会话'),
        content: Text('确定要删除「$topicTitle」的所有会话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              onDeleteTopic();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';

    return '${time.month}/${time.day}';
  }
}
