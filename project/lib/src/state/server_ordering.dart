import 'dart:math';

import 'settings_store.dart';

const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
String newUlid() {
  var t = DateTime.now().millisecondsSinceEpoch;
  final time = StringBuffer();
  for (var i = 0; i < 10; i++) {
    time.write(_alphabet[t % 32]);
    t ~/= 32;
  }
  final r = Random.secure();
  return time.toString().split('').reversed.join() + List.generate(16, (_) => _alphabet[r.nextInt(32)]).join();
}

class ServerFolder {
  ServerFolder({required this.id, required this.name, this.colour, this.collapsed = false, required this.servers});
  final String id;
  String name;
  String? colour;
  bool collapsed;
  List<String> servers;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'colour': ?colour, if (collapsed) 'collapsed': true, 'servers': servers};

  static ServerFolder? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || (j['id'] as String).isEmpty) return null;
    return ServerFolder(
      id: j['id'] as String,
      name: j['name'] as String? ?? '',
      colour: j['colour'] as String?,
      collapsed: j['collapsed'] == true,
      servers: [if (j['servers'] is List) for (final s in j['servers'] as List) if (s is String) s],
    );
  }
}

/// A resolved sidebar entry: a server or a folder with its (known) servers.
class RailEntry {
  RailEntry.server(this.id) : folder = null, servers = const [];
  RailEntry.folder(this.folder, this.servers) : id = folder!.id;
  final String id;
  final ServerFolder? folder;
  final List<String> servers;
  bool get isFolder => folder != null;
}

/// Server ordering and folders (`Ordering` + `ServerFolders` stores).
class ServerOrdering {
  ServerOrdering(this.s);
  final SettingsStore s;

  List<ServerFolder> folders() {
    final seenFolders = <String>{}, seenServers = <String>{};
    final out = <ServerFolder>[];
    for (final j in s.raw<List>('folders.list') ?? const []) {
      final f = ServerFolder.fromJson(j);
      if (f == null || !seenFolders.add(f.id)) continue;
      f.servers = f.servers.where(seenServers.add).toList();
      out.add(f);
    }
    return out;
  }

  void _write(List<ServerFolder> folders) =>
      s.setRaw('folders.list', [for (final f in folders) if (f.servers.isNotEmpty) f.toJson()], syncKey: 'server-folders');

  ServerFolder? folderOf(String serverId) => folders().where((f) => f.servers.contains(serverId)).firstOrNull;

  String createFolder(String name, List<String> serverIds) {
    final id = 'folder-${newUlid()}';
    final claimed = serverIds.toSet();
    final list = folders();
    for (final f in list) {
      f.servers = f.servers.where((x) => !claimed.contains(x)).toList();
    }
    list.add(ServerFolder(id: id, name: name, servers: [...serverIds]));
    _write(list);
    return id;
  }

  void editFolder(String id, {String? name, String? colour}) {
    final list = folders();
    for (final f in list) {
      if (f.id == id) {
        if (name != null) f.name = name;
        if (colour != null) f.colour = colour.isEmpty ? null : colour;
      }
    }
    _write(list);
  }

  void deleteFolder(String id) => _write(folders().where((f) => f.id != id).toList());

  void toggleFolder(String id) {
    final list = folders();
    for (final f in list) {
      if (f.id == id) f.collapsed = !f.collapsed;
    }
    _write(list);
  }

  void addToFolder(String folderId, String serverId) {
    final list = folders();
    for (final f in list) {
      if (f.id == folderId) {
        if (!f.servers.contains(serverId)) f.servers = [...f.servers, serverId];
      } else {
        f.servers = f.servers.where((x) => x != serverId).toList();
      }
    }
    _write(list);
  }

  void placeInFolder(String folderId, String serverId, String? before) {
    final list = folders();
    for (final f in list) {
      final servers = f.servers.where((x) => x != serverId).toList();
      if (f.id != folderId) {
        f.servers = servers;
        continue;
      }
      final at = before == null ? -1 : servers.indexOf(before);
      servers.insert(at == -1 ? servers.length : at, serverId);
      f.servers = servers;
    }
    _write(list);
  }

  void removeFromFolder(String serverId) {
    final list = folders();
    for (final f in list) {
      f.servers = f.servers.where((x) => x != serverId).toList();
    }
    _write(list);
  }

  List<String> _sidebar() => s.raw<List>('ordering.serverSidebar')?.cast<String>() ?? s.raw<List>('ordering.servers')?.cast<String>() ?? const [];

  /// Entries to draw, with folder contents grouped and unordered servers appended.
  List<RailEntry> orderedEntries(Iterable<String> knownServers) {
    final known = knownServers.toSet();
    final byId = <String, ServerFolder>{};
    final folderOf = <String, ServerFolder>{};
    for (final f in folders()) {
      byId[f.id] = f;
      for (final id in f.servers) {
        folderOf.putIfAbsent(id, () => f);
      }
    }
    final out = <RailEntry>[];
    final drawn = <String>{};

    void take(String id) {
      final f = byId[id] ?? folderOf[id];
      if (f != null) {
        if (!drawn.add(f.id)) return;
        final servers = f.servers.where(known.remove).toList();
        if (servers.isNotEmpty) out.add(RailEntry.folder(f, servers));
        return;
      }
      if (known.remove(id)) out.add(RailEntry.server(id));
    }

    _sidebar().forEach(take);
    known.toList().forEach(take);
    return out;
  }

  List<String> orderedServers(Iterable<String> knownServers) => [
    for (final e in orderedEntries(knownServers)) ...(e.isFolder ? e.servers : [e.id]),
  ];

  /// Sets the order of top-level entries (folder members trail their folder).
  void setServerOrder(List<String> ids) {
    final byId = {for (final f in folders()) f.id: f};
    s.setRaw(
      'ordering.serverSidebar',
      [for (final id in ids) ...[id, ...(byId[id]?.servers ?? const [])]],
      syncKey: 'ordering',
    );
  }
}
