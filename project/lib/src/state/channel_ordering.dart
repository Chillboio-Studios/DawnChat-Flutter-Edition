import '../api/client_store.dart';

class OrderedCategory {
  OrderedCategory({
    required this.id,
    required this.title,
    required this.channelIds,
  });

  final String id;
  String title;
  List<String> channelIds;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'id': id,
    'title': title,
    'channels': List<String>.from(channelIds),
  };
}

/// Port of `orderedCategories` from `ordering.ts`.
List<OrderedCategory> orderedCategories(
  List<dynamic>? categories,
  List<String> knownChannelIds,
) {
  final known = knownChannelIds.toSet();
  final uncategorised = knownChannelIds.toSet();

  final ordered = <OrderedCategory>[];
  for (final raw in categories ?? const <dynamic>[]) {
    if (raw is! Map) continue;
    final id = (raw['id'] as String?) ?? 'default';
    final title = (raw['title'] as String?) ?? '';
    final channels = ((raw['channels'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where(known.contains)
        .toList();
    for (final cid in channels) {
      uncategorised.remove(cid);
    }
    if (id != 'default' || channels.any(known.contains)) {
      ordered.add(OrderedCategory(id: id, title: title, channelIds: channels));
    }
  }

  final uncategorisedIds = uncategorised.toList();
  final defaultCategory = ordered.where((c) => c.id == 'default').firstOrNull;
  if (defaultCategory != null) {
    defaultCategory.channelIds = [
      ...defaultCategory.channelIds,
      ...uncategorisedIds,
    ];
  } else {
    ordered.insert(
      0,
      OrderedCategory(
        id: 'default',
        title: 'Default',
        channelIds: uncategorisedIds,
      ),
    );
  }

  return ordered;
}

/// Port of `applyChannelOrdering` from `ordering.ts`.
List<String> applyChannelOrdering(
  List<String> channelIds,
  List<String> visibleIds,
  List<String> reorderedIds,
) {
  final newOrdering = <String>[];
  final visible = visibleIds.toSet();
  final remaining = <String>[...channelIds];

  for (final orderedId in reorderedIds) {
    final index = remaining.indexOf(orderedId);

    if (index == -1) {
      newOrdering.add(orderedId);
      continue;
    }

    final leading = remaining.sublist(0, index);
    remaining.removeRange(0, index);

    newOrdering.addAll(leading.where((id) => !visible.contains(id)));

    // invariant: remaining[0] == orderedId
    newOrdering.add(remaining.removeAt(0));

    remaining.insertAll(0, leading.where(visible.contains));
  }

  return <String>[
    ...newOrdering,
    ...remaining.where((id) => !visible.contains(id)),
  ];
}

Future<void> saveServerCategories(
  ClientStore store,
  String serverId,
  List<OrderedCategory> categories,
) async {
  final server = store.servers[serverId];
  if (server == null) return;
  final payload = <Map<String, dynamic>>[
    for (final cat in categories)
      if (cat.id != 'default' || cat.channelIds.isNotEmpty)
        <String, dynamic>{
          'id': cat.id,
          'title': cat.title,
          'channels': List<String>.from(cat.channelIds),
        },
  ];
  final allOrderedIds = <String>[
    for (final cat in categories) ...cat.channelIds,
  ];
  final existingChannels = ((server['channels'] as List?) ?? const <dynamic>[])
      .whereType<String>()
      .toList();
  for (final id in existingChannels) {
    if (!allOrderedIds.contains(id)) allOrderedIds.add(id);
  }
  server['categories'] = payload;
  server['channels'] = allOrderedIds;
  store.refresh();
  await store.api.patch('/servers/$serverId', {'categories': payload});
}
