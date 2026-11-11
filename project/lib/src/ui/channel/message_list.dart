import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../api/client_store.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../messaging/message_tile.dart';
import '../messaging/time_utils.dart';
import '../../core/i18n.dart';

class MessageListController {
  VoidCallback? _jumpToBottom;
  void jumpToBottom() => _jumpToBottom?.call();
}

sealed class _Entry {}

class _Msg extends _Entry {
  _Msg(this.message, this.tail);
  final Json message;
  final bool tail;
}

class _Divider extends _Entry {
  _Divider({this.date, this.unread = false});
  final String? date;
  final bool unread;
}

class _Blocked extends _Entry {
  _Blocked(this.count);
  final int count;
}

/// Messages in a channel with history paging, jumping and unread markers (`Messages` of the web client).
class MessageList extends StatefulWidget {
  const MessageList({
    super.key,
    required this.channel,
    this.highlightId,
    this.controller,
    this.onAtEndChanged,
  });
  final Json channel;
  final String? highlightId;
  final MessageListController? controller;
  final ValueChanged<bool>? onAtEndChanged;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> with WidgetsBindingObserver {
  static const _initialLimit = 30, _fetchLimit = 50, _displayLimit = 150;

  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  bool loading = true,
      failed = false,
      atStart = false,
      fetchingUp = false,
      fetchingDown = false;
  String? _lastReadId;
  bool _focused = true;
  bool _ackScheduled = false;
  String? _jumpedTo;
  List<_Entry> _entries = const [];

  String get id => widget.channel['_id'] as String;
  String? get serverId => widget.channel['server'] as String?;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?._jumpToBottom = _jumpToBottom;
    _positions.itemPositions.addListener(_onPositions);
    _captureUnread();
    _initialLoad(widget.highlightId);
  }

  @override
  void didUpdateWidget(covariant MessageList old) {
    super.didUpdateWidget(old);
    widget.controller?._jumpToBottom = _jumpToBottom;
    if (old.channel['_id'] != id) {
      _lastReadId = null;
      atStart = false;
      _jumpedTo = null;
      _captureUnread();
      _initialLoad(widget.highlightId);
    } else if (widget.highlightId != null &&
        widget.highlightId != old.highlightId) {
      _jumpToMessage(widget.highlightId!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positions.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _focused = state == AppLifecycleState.resumed;
    if (_focused) _maybeAck();
  }

  void _captureUnread() {
    final store = context.read<ClientStore>();
    final last = store.unreads[id]?['last_id'] as String?;
    _lastReadId = store.isUnread(id) ? last : null;
  }

  bool get _atEnd => !context.read<ClientStore>().detached.contains(id);

  Future<void> _initialLoad(String? nearby) async {
    final store = context.read<ClientStore>();
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final existing = store.messages[id];
      if (nearby == null && existing != null && existing.isNotEmpty) {
        atStart = existing.length < _initialLimit;
      } else if (nearby != null) {
        await store.loadMessages(
          id,
          nearby: nearby,
          limit: _fetchLimit,
          replace: true,
        );
        atStart = false;
      } else {
        final got = await store.loadMessages(id, limit: _initialLimit);
        atStart = got.length < _initialLimit;
      }
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => loading = false);
    widget.onAtEndChanged?.call(_atEnd);
    _maybeAck();
    if (nearby != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToMessage(nearby),
      );
    }
  }

  void _maybeAck() {
    final store = context.read<ClientStore>();
    if (!_focused || !_atEnd) return;
    final last = store.channels[id]?['last_message_id'] as String?;
    if (last != null && store.isUnread(id)) store.ack(id, last);
  }

  /// Schedules an ack check after the current frame. Used when the store
  /// reports unread state (e.g. a live message arrived while viewing).
  void _scheduleAck() {
    if (_ackScheduled) return;
    _ackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ackScheduled = false;
      if (mounted) _maybeAck();
    });
  }

  void _onPositions() {
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty || loading) return;
    final maxIndex = pos.map((p) => p.index).reduce((a, b) => a > b ? a : b);
    final minIndex = pos.map((p) => p.index).reduce((a, b) => a < b ? a : b);
    if (maxIndex >= _entries.length - 3) _fetchUp();
    if (minIndex <= 2 && !_atEnd) _fetchDown();
  }

  Future<void> _fetchUp() async {
    if (atStart || fetchingUp || loading) return;
    final store = context.read<ClientStore>();
    final list = store.messages[id];
    if (list == null || list.isEmpty) return;
    final oldest = list.firstWhere(
      (m) => m['pending'] != true && m['failed'] != true,
      orElse: () => list.first,
    );
    fetchingUp = true;
    setState(() {});
    try {
      final got = await store.loadMessages(
        id,
        before: oldest['_id'] as String,
        limit: _fetchLimit,
      );
      if (got.length < _fetchLimit) atStart = true;
      final over = (store.messages[id]?.length ?? 0) - _displayLimit;
      if (over > 0) {
        // Trim from the newest end; we are no longer attached to the present.
        store.messages[id]!.removeRange(
          store.messages[id]!.length - over,
          store.messages[id]!.length,
        );
        store.detached.add(id);
        widget.onAtEndChanged?.call(false);
      }
    } catch (_) {}
    fetchingUp = false;
    if (mounted) setState(() {});
  }

  Future<void> _fetchDown() async {
    if (fetchingDown || _atEnd) return;
    final store = context.read<ClientStore>();
    final list = store.messages[id];
    if (list == null || list.isEmpty) return;
    fetchingDown = true;
    try {
      final got = await store.loadMessages(
        id,
        after: list.last['_id'] as String,
        limit: _fetchLimit,
      );
      if (got.length < _fetchLimit) {
        store.detached.remove(id);
        widget.onAtEndChanged?.call(true);
        _maybeAck();
      }
      final over = (store.messages[id]?.length ?? 0) - _displayLimit;
      if (over > 0) {
        store.messages[id]!.removeRange(0, over);
        atStart = false;
      }
    } catch (_) {}
    fetchingDown = false;
    if (mounted) setState(() {});
  }

  Future<void> _jumpToBottom() async {
    final store = context.read<ClientStore>();
    if (_atEnd) {
      if (_scroll.isAttached)
        _scroll.scrollTo(index: 0, duration: const Duration(milliseconds: 250));
      return;
    }
    setState(() => loading = true);
    try {
      final got = await store.loadMessages(
        id,
        limit: _fetchLimit,
        replace: true,
      );
      atStart = got.length < _fetchLimit;
      store.detached.remove(id);
    } catch (_) {}
    if (!mounted) return;
    setState(() => loading = false);
    widget.onAtEndChanged?.call(true);
    _maybeAck();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.isAttached) _scroll.jumpTo(index: 0);
    });
  }

  Future<void> _jumpToMessage(String messageId) async {
    final store = context.read<ClientStore>();
    if (store.messages[id]?.any((m) => m['_id'] == messageId) ?? false) {
      _scrollToMessage(messageId);
      return;
    }
    setState(() => loading = true);
    try {
      await store.loadMessages(
        id,
        nearby: messageId,
        limit: _fetchLimit,
        replace: true,
      );
      atStart = false;
    } catch (_) {}
    if (!mounted) return;
    setState(() => loading = false);
    widget.onAtEndChanged?.call(_atEnd);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToMessage(messageId),
    );
  }

  void _scrollToMessage(String messageId) {
    final idx = _entries.indexWhere(
      (e) => e is _Msg && e.message['_id'] == messageId,
    );
    if (idx < 0 || !_scroll.isAttached) return;
    setState(() => _jumpedTo = messageId);
    _scroll.scrollTo(
      index: idx,
      alignment: .4,
      duration: const Duration(milliseconds: 300),
    );
  }

  List<_Entry> _build(ClientStore store, List<Json> list) {
    final out = <_Entry>[];
    final lastRead = _lastReadId ?? '0';
    var blocked = 0;
    var firstReadIndex = -1;
    for (var i = list.length - 1; i >= 0; i--) {
      if ((list[i]['_id'] as String).compareTo(lastRead) < 0) {
        firstReadIndex = i;
        break;
      }
    }
    void flushBlocked() {
      if (blocked > 0) {
        out.add(_Blocked(blocked));
        blocked = 0;
      }
    }

    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      final prev = i > 0 ? list[i - 1] : null;
      var tail = prev != null;
      DateTime? dateBreak;
      if (prev != null) {
        final a = _t(m), b = _t(prev);
        if (a.year != b.year || a.month != b.month || a.day != b.day) {
          dateBreak = a;
          tail = false;
        }
        if (m['author'] != prev['author'] ||
            (a.millisecondsSinceEpoch - b.millisecondsSinceEpoch).abs() >=
                420000 ||
            jsonEncode(m['masquerade']) != jsonEncode(prev['masquerade']) ||
            m['system'] != null ||
            prev['system'] != null ||
            (m['replies'] as List?)?.isNotEmpty == true ||
            ((prev['_id'] as String).compareTo(lastRead) < 0 &&
                i >= firstReadIndex)) {
          tail = false;
        }
      }
      if (dateBreak != null) {
        flushBlocked();
        out.add(_Divider(date: formatLongDate(dateBreak)));
      }
      if (store.user(m['author'] as String?)?['relationship'] == 'Blocked') {
        blocked++;
      } else {
        flushBlocked();
        out.add(_Msg(m, tail));
      }
      if (i == firstReadIndex && firstReadIndex < list.length - 1) {
        flushBlocked();
        out.add(_Divider(unread: true));
      }
    }
    flushBlocked();
    return out.reversed.toList();
  }

  static DateTime _t(Json m) {
    try {
      return ulidTime(m['_id'] as String);
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    context.watch<SettingsStore>();
    final cs = Theme.of(context).colorScheme;
    final list = store.messages[id] ?? const <Json>[];
    _entries = _build(store, list);

    if (loading && list.isEmpty) return const _Skeleton();
    if (failed && list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Failed to load messages'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _initialLoad(widget.highlightId),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final itemCount = _entries.length + 1; // + header
    final detached = store.detached.contains(id);

    // Ack live arrivals: a message event may have marked this channel unread
    // while the user is sitting at the bottom looking at it.
    if (store.isUnread(id)) _scheduleAck();

    final listView = ScrollablePositionedList.builder(
      itemScrollController: _scroll,
      itemPositionsListener: _positions,
      reverse: true,
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: itemCount,
      itemBuilder: (c, i) {
        if (i == _entries.length) {
          if (atStart) return ConversationStart(channel: widget.channel);
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final e = _entries[i];
        switch (e) {
          case _Msg():
            return MessageTile(
              key: ValueKey(e.message['_id']),
              message: e.message,
              serverId: serverId,
              tail: e.tail,
              highlight: e.message['_id'] == (_jumpedTo ?? widget.highlightId),
            );
          case _Divider():
            return MessageDivider(date: e.date, unread: e.unread);
          case _Blocked():
            return BlockedMessages(count: e.count);
        }
      },
    );

    return Stack(
      children: [
        Positioned.fill(child: listView),
        if (_lastReadId != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: _Indicator(
                onTap: () {
                  final sid = serverId;
                  context.goPath(
                    '${sid != null ? '/server/$sid' : ''}/channel/$id/$_lastReadId',
                  );
                },
                label:
                    'New messages since ${formatRelative(_ulid(_lastReadId!), hideSuffix: false)}',
                action: tr('Jump to the beginning'),
                trailing: GestureDetector(
                  onTap: () => setState(() => _lastReadId = null),
                  child: const Icon(Icons.close, size: 16),
                ),
              ),
            ),
          ),
        if (detached)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
              child: _Indicator(
                onTap: _jumpToBottom,
                label: tr('Viewing older messages'),
                action: tr('Jump to present'),
                trailing: const Icon(Icons.arrow_forward, size: 16),
              ),
            ),
          ),
        if (loading)
          Positioned.fill(
            child: ColoredBox(
              color: cs.surface.withValues(alpha: .4),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  static DateTime _ulid(String id) {
    try {
      return ulidTime(id);
    } catch (_) {
      return DateTime.now();
    }
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({
    required this.onTap,
    required this.label,
    required this.action,
    required this.trailing,
  });
  final VoidCallback onTap;
  final String label, action;
  final Widget trailing;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Color.alphaBlend(
        cs.primary.withValues(alpha: .55),
        Colors.transparent,
      ).withValues(alpha: .55),
      borderRadius: br(Radius_.lg),
      child: InkWell(
        borderRadius: br(Radius_.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: cs.onPrimary),
            child: IconTheme(
              data: IconThemeData(color: cs.onPrimary),
              child: Row(
                spacing: Gap.md,
                children: [
                  Expanded(child: Text(tr(label))),
                  Text(tr(action)),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = cs.surfaceContainerHighest;
    return ClipRect(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < 9; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 80.0 + (i * 23 % 60),
                        height: 12,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: br(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var j = 0; j < 1 + i % 3; j++) ...[
                        Container(
                          width: 160.0 + ((i + j) * 41 % 200),
                          height: 12,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: br(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
