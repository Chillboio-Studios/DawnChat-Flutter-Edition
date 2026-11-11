import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/i18n.dart';
import '../../theme/tokens.dart';
import '../messaging/markdown_view.dart';
import '../modals/app_dialog.dart';
import '../widgets.dart';

/// Admin changelog management — list, create, edit, publish/unpublish, delete.
class ChangelogsView extends StatefulWidget {
  const ChangelogsView({super.key});

  @override
  State<ChangelogsView> createState() => _ChangelogsViewState();
}

class _ChangelogsViewState extends State<ChangelogsView> {
  List<Map<String, dynamic>>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await context.read<ClientStore>().api.get('/admin/changelogs')
          as Map;
      final list = (r['changelogs'] as List?) ?? const [];
      if (mounted) {
        setState(() {
          _entries = list
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _edit([Map<String, dynamic>? entry]) async {
    final saved = await showAppDialog<bool>(
      context,
      title: entry == null ? tr('New changelog') : tr('Edit changelog'),
      content: ChangelogEditor(entry: entry),
      actions: const [],
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await confirm(
      context,
      'Delete changelog?',
      '"{t}" will be permanently deleted.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<ClientStore>().api.delete(
        '/admin/changelogs/${e['id']}',
      );
      _load();
    } catch (err) {
      if (mounted) showSnack(context, errorText(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: cs.error)),
            TextButton(onPressed: _load, child: Text(tr('Retry'))),
          ],
        ),
      );
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('New changelog')),
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(child: Text(tr('No changelogs yet.')))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (c, i) {
                    final e = entries[i];
                    final published = e['published_at'] != null;
                    return ListTile(
                      leading: Icon(
                        published
                            ? Icons.campaign_outlined
                            : Icons.edit_note_outlined,
                        color: published ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(e['title'] as String? ?? ''),
                      subtitle: Text(
                        [
                          if (e['client_version'] != null)
                            'v${e['client_version']}',
                          if (e['published_at'] != null)
                            (e['published_at'] as String).split('T').first,
                        ].join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!published)
                            Chip(
                              label: Text(tr('Draft')),
                              visualDensity: VisualDensity.compact,
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: tr('Edit'),
                            onPressed: () => _edit(e),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: tr('Delete'),
                            onPressed: () => _delete(e),
                          ),
                        ],
                      ),
                      onTap: () => _edit(e),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Markdown editor dialog with formatting toolbar, image upload and preview.
class ChangelogEditor extends StatefulWidget {
  const ChangelogEditor({super.key, this.entry});
  final Map<String, dynamic>? entry;

  @override
  State<ChangelogEditor> createState() => _ChangelogEditorState();
}

class _ChangelogEditorState extends State<ChangelogEditor> {
  late final TextEditingController _title;
  late final TextEditingController _version;
  late final TextEditingController _md;
  late bool _publish;
  bool _preview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _title = TextEditingController(text: e?['title'] as String? ?? '');
    _version = TextEditingController(
      text: e?['client_version'] as String? ?? '',
    );
    _md = TextEditingController(
      text: e?['markdown_content'] as String? ?? '',
    );
    _publish = e?['published_at'] != null;
  }

  @override
  void dispose() {
    _title.dispose();
    _version.dispose();
    _md.dispose();
    super.dispose();
  }

  /// Wraps the current selection (or inserts at cursor) with [prefix]/[suffix].
  void _wrap(String prefix, String suffix, {String placeholder = 'text'}) {
    final c = _md;
    final sel = c.selection;
    final text = c.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = start < end ? text.substring(start, end) : placeholder;
    final replacement = '$prefix$selected$suffix';
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: start + prefix.length + selected.length,
      ),
    );
  }

  /// Prefixes each selected line with [prefix].
  void _linePrefix(String prefix) {
    final c = _md;
    final sel = c.selection;
    final text = c.text;
    var start = sel.isValid ? sel.start : 0;
    var end = sel.isValid ? sel.end : text.length;
    while (start > 0 && text[start - 1] != '\n') {
      start--;
    }
    while (end < text.length && text[end] != '\n') {
      end++;
    }
    final block = text.substring(start, end);
    final prefixed = block
        .split('\n')
        .map((l) => l.isEmpty ? l : '$prefix$l')
        .join('\n');
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, prefixed),
      selection: TextSelection(baseOffset: start, extentOffset: start + prefixed.length),
    );
  }

  void _insert(String snippet) {
    final c = _md;
    final sel = c.selection;
    final offset = sel.isValid ? sel.extentOffset : c.text.length;
    c.value = TextEditingValue(
      text: c.text.replaceRange(offset, offset, snippet),
      selection: TextSelection.collapsed(offset: offset + snippet.length),
    );
  }

  Future<void> _insertLink() async {
    final url = await promptText(context, 'Link URL', label: 'https://');
    if (url == null || url.isEmpty || !mounted) return;
    final c = _md;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : start;
    final label = start < end ? c.text.substring(start, end) : 'link';
    _md.value = TextEditingValue(
      text: c.text.replaceRange(start, end, '[$label]($url)'),
      selection: TextSelection.collapsed(
        offset: start + label.length + url.length + 4,
      ),
    );
  }

  Future<void> _insertImage() async {
    final store = context.read<ClientStore>();
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    try {
      showSnack(context, tr('Uploading image…'));
      final id = await store.api.uploadFile(
        'changelogs',
        f.name,
        f.extension == 'png' ? 'image/png' : 'image/jpeg',
        bytes,
      );
      final url = store.api.fileUrl('changelogs', {'_id': id});
      if (url == null || !mounted) return;
      _insert('![${f.name}]($url)');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showSnack(context, tr('Title is required.'));
      return;
    }
    setState(() => _saving = true);
    final store = context.read<ClientStore>();
    final e = widget.entry;
    final body = {
      'title': title,
      'markdown_content': _md.text,
      'client_version': _version.text.trim().isEmpty
          ? null
          : _version.text.trim(),
      if (e == null) 'publish': _publish,
    };
    try {
      if (e == null) {
        await store.api.post('/admin/changelogs', body);
      } else {
        await store.api.patch('/admin/changelogs/${e['id']}', {
          ...body,
          'publish': _publish,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, errorText(err));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return SizedBox(
      width: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: tr('Title'),
              isDense: true,
            ),
          ),
          const SizedBox(height: Gap.sm),
          TextField(
            controller: _version,
            decoration: InputDecoration(
              labelText: tr('Client version (optional)'),
              hintText: '1.4.0',
              isDense: true,
            ),
          ),
          const SizedBox(height: Gap.sm),
          // Formatting toolbar
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              _tool(Icons.format_bold, () => _wrap('**', '**'), tip: tr('Bold')),
              _tool(Icons.format_italic, () => _wrap('*', '*'), tip: tr('Italic')),
              _tool(Icons.format_strikethrough, () => _wrap('~~', '~~'), tip: tr('Strikethrough')),
              _tool(Icons.title, () => _linePrefix('# '), tip: tr('Heading 1')),
              _tool(Icons.text_fields, () => _linePrefix('## '), tip: tr('Heading 2')),
              _tool(Icons.format_size, () => _linePrefix('### '), tip: tr('Heading 3')),
              _tool(Icons.format_list_bulleted, () => _linePrefix('- '), tip: tr('Bullet list')),
              _tool(Icons.format_list_numbered, () => _linePrefix('1. '), tip: tr('Numbered list')),
              _tool(Icons.format_quote, () => _linePrefix('> '), tip: tr('Quote')),
              _tool(Icons.link, _insertLink, tip: tr('Insert link')),
              _tool(Icons.image_outlined, _insertImage, tip: tr('Insert image')),
              _tool(
                _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                () => setState(() => _preview = !_preview),
                tip: _preview ? tr('Edit') : tr('Preview'),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          if (_preview)
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: RichContent(_md.text),
              ),
            )
          else
            TextField(
              controller: _md,
              maxLines: 14,
              minLines: 10,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: tr('Write your changelog in Markdown…'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          const SizedBox(height: Gap.sm),
          CheckboxListTile(
            value: _publish,
            onChanged: (v) => setState(() => _publish = v ?? false),
            title: Text(tr('Published')),
            subtitle: Text(
              _publish
                  ? tr('Visible to all users immediately.')
                  : tr('Saved as draft — only visible to admins.'),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
          const SizedBox(height: Gap.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text(tr('Cancel')),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, VoidCallback onTap, {required String tip}) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
