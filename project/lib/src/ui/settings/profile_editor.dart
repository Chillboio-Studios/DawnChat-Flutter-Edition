import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/i18n.dart';
import '../../theme/tokens.dart';
import '../image_cropper.dart';
import '../modals/member_modals.dart';
import '../net_image.dart';
import '../widgets.dart';

typedef _Pick = PickedImage;

/// Edit the global profile (`UserProfileEditor` / `EditProfile` in the web client).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.onNavigate, this.userId});
  final void Function(String) onNavigate;
  final String? userId;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ClientStore _store = context.read<ClientStore>();
  final _name = TextEditingController();
  final _pronouns = TextEditingController();
  final _bio = TextEditingController();
  String _name0 = '', _pronouns0 = '', _bio0 = '';
  Map? _bannerFile;
  _Pick? _newAvatar, _newBanner;
  bool _removeAvatar = false, _removeBanner = false;
  bool _loading = true, _busy = false;

  String get _userId => widget.userId ?? _store.userId!;
  Map<String, dynamic> get _me => _store.user(_userId) ?? const {};

  @override
  void initState() {
    super.initState();
    _resetFromUser();
    for (final c in [_name, _pronouns, _bio]) {
      c.addListener(() => setState(() {}));
    }
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _pronouns.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _resetFromUser() {
    final p = _me['pronouns'];
    _name0 = _me['display_name'] as String? ?? '';
    _pronouns0 = p is List ? p.join('/') : (p as String? ?? '');
    _name.text = _name0;
    _pronouns.text = _pronouns0;
    _newAvatar = _newBanner = null;
    _removeAvatar = _removeBanner = false;
  }

  Future<void> _loadProfile() async {
    try {
      final r = (await _store.api.get('/users/$_userId/profile')) as Map;
      _bio0 = r['content'] as String? ?? '';
      _bannerFile = r['background'] as Map?;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _bio.text = _bio0;
      _loading = false;
    });
  }

  bool get _dirty =>
      _name.text != _name0 ||
      _pronouns.text != _pronouns0 ||
      _bio.text != _bio0 ||
      _newAvatar != null ||
      _newBanner != null ||
      _removeAvatar ||
      _removeBanner;

  Future<_Pick?> _pick({
    required CropShape shape,
    double aspectRatio = 1,
    String name = 'image',
  }) => pickImageForUpload(
    context,
    shape: shape,
    aspectRatio: aspectRatio,
    name: name,
  );

  void _reset() => setState(() {
    _resetFromUser();
    _bio.text = _bio0;
  });

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isNotEmpty && name.length < 2) {
      showSnack(context, '${tr('Display Name')}: 2-32');
      return;
    }
    setState(() => _busy = true);
    try {
      final remove = <String>[];
      final body = <String, dynamic>{};
      final profile = <String, dynamic>{};
      if (_name.text != _name0) {
        name.isEmpty ? remove.add('DisplayName') : body['display_name'] = name;
      }
      if (_newAvatar != null) {
        body['avatar'] = await _store.api.uploadFile(
          'avatars',
          _newAvatar!.name,
          mimeFromNameSimple(_newAvatar!.name),
          _newAvatar!.bytes,
        );
      } else if (_removeAvatar) {
        remove.add('Avatar');
      }
      if (_pronouns.text != _pronouns0) {
        final p = _pronouns.text.trim();
        p.isEmpty ? remove.add('Pronouns') : body['pronouns'] = p;
      }
      if (_bio.text != _bio0) {
        _bio.text.isEmpty
            ? remove.add('ProfileContent')
            : profile['content'] = _bio.text;
      }
      if (_newBanner != null) {
        profile['background'] = await _store.api.uploadFile(
          'backgrounds',
          _newBanner!.name,
          mimeFromNameSimple(_newBanner!.name),
          _newBanner!.bytes,
        );
      } else if (_removeBanner) {
        remove.add('ProfileBackground');
      }
      if (profile.isNotEmpty) body['profile'] = profile;
      if (remove.isNotEmpty) body['remove'] = remove;
      if (body.isNotEmpty)
        await _store.api.patch('/users/${widget.userId ?? '@me'}', body);
      await _store.fetchUser(_userId);
      _resetFromUser();
      await _loadProfile();
      if (mounted) showSnack(context, 'Profile saved');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ClientStore>();
    final cs = context.cs;
    final isBot = _me['bot'] != null;
    final servers = [
      for (final s in _store.serverList)
        if (_store.members[s['_id']]?[_store.userId] != null) s,
    ];
    final bannerUrl = _removeBanner
        ? null
        : _store.api.fileUrl('backgrounds', _bannerFile, width: 800);
    final hasAvatar =
        !_removeAvatar && (_newAvatar != null || _me['avatar'] != null);
    final hasBanner = _newBanner != null || bannerUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xl,
      children: [
        _Preview(
          store: _store,
          userId: _userId,
          name: _name.text.trim().isEmpty
              ? (_me['username'] as String? ?? '')
              : _name.text.trim(),
          pronouns: _pronouns.text.trim(),
          newAvatar: _newAvatar?.bytes,
          removeAvatar: _removeAvatar,
          newBanner: _newBanner?.bytes,
          bannerUrl: bannerUrl,
        ),
        if (widget.userId == null && servers.isNotEmpty)
          CategoryGroup(
            children: [
              _IdentityList(
                servers: servers,
                userId: _store.userId!,
                store: _store,
              ),
            ],
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.l,
          children: [
            Text(
              tr('Edit Global Profile'),
              style: context.tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            _ImageField(
              title: tr('Avatar'),
              hint: tr('Square'),
              preview: ClipOval(
                child: SizedBox.square(
                  dimension: 48,
                  child: _newAvatar != null
                      ? Image.memory(_newAvatar!.bytes, fit: BoxFit.cover)
                      : (hasAvatar
                            ? NetImage(
                                _store.avatarUrl(_userId, size: 96) ?? '',
                                fit: BoxFit.cover,
                              )
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.person,
                                  color: cs.onSurfaceVariant,
                                ),
                              )),
                ),
              ),
              hasImage: hasAvatar,
              onUpload: () async {
                final p = await _pick(shape: CropShape.circle, name: 'avatar');
                if (p != null) {
                  setState(() {
                    _newAvatar = p;
                    _removeAvatar = false;
                  });
                }
              },
              onRemove: () => setState(() {
                _newAvatar = null;
                _removeAvatar = true;
              }),
            ),
            _ImageField(
              title: tr('Banner'),
              hint: '232 : 100',
              preview: ClipRRect(
                borderRadius: br(Radius_.sm),
                child: SizedBox(
                  width: 112,
                  height: 48,
                  child: _newBanner != null
                      ? Image.memory(_newBanner!.bytes, fit: BoxFit.cover)
                      : (bannerUrl != null
                            ? NetImage(bannerUrl, fit: BoxFit.cover)
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.image_outlined,
                                  color: cs.onSurfaceVariant,
                                ),
                              )),
                ),
              ),
              hasImage: hasBanner,
              onUpload: () async {
                final p = await _pick(
                  shape: CropShape.rect,
                  aspectRatio: 2.32,
                  name: 'banner',
                );
                if (p != null) {
                  setState(() {
                    _newBanner = p;
                    _removeBanner = false;
                  });
                }
              },
              onRemove: () => setState(() {
                _newBanner = null;
                _removeBanner = true;
              }),
            ),
            TextField(
              controller: _name,
              maxLength: 32,
              decoration: InputDecoration(labelText: tr('Display Name')),
            ),
            TextField(
              controller: _pronouns,
              maxLength: 24,
              decoration: InputDecoration(labelText: tr('Pronouns')),
            ),
            if (!isBot)
              CategoryGroup(
                children: [
                  CategoryButton(
                    icon: const Icon(Icons.badge),
                    title: Text(tr('Want to change username?')),
                    description: Text(
                      tr('Go to account settings to edit your username'),
                    ),
                    action: const Icon(Icons.chevron_right),
                    onTap: () => widget.onNavigate('account'),
                  ),
                ],
              ),
            Text(tr('Profile Bio'), style: context.tt.labelLarge),
            TextField(
              controller: _bio,
              enabled: !_loading,
              minLines: 5,
              maxLines: 14,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: tr('Something cool about me...'),
                alignLabelWithHint: true,
              ),
            ),
            Row(
              spacing: Gap.md,
              children: [
                TextButton(
                  onPressed: _dirty && !_busy ? _reset : null,
                  child: Text(tr('Reset')),
                ),
                FilledButton(
                  onPressed: _dirty && !_busy ? _save : null,
                  child: Text(tr('Save')),
                ),
                if (_busy)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Live preview of how the profile header will look.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.store,
    required this.userId,
    required this.name,
    required this.pronouns,
    required this.newAvatar,
    required this.removeAvatar,
    required this.newBanner,
    required this.bannerUrl,
  });
  final ClientStore store;
  final String userId;
  final String name, pronouns;
  final Uint8List? newAvatar, newBanner;
  final bool removeAvatar;
  final String? bannerUrl;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final me = store.user(userId) ?? const {};
    final username = '${me['username']}#${me['discriminator']}';
    final avatar = newAvatar != null
        ? Image.memory(newAvatar!, fit: BoxFit.cover)
        : NetImage(
            removeAvatar
                ? store.api.defaultAvatar(userId)
                : (store.avatarUrl(userId, size: 128) ?? ''),
            fit: BoxFit.cover,
          );
    return ClipRRect(
      borderRadius: br(Radius_.xl),
      child: Container(
        height: 144,
        color: cs.primaryContainer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (newBanner != null)
              Image.memory(newBanner!, fit: BoxFit.cover)
            else if (bannerUrl != null)
              NetImage(bannerUrl!, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0xB3000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  spacing: Gap.lg,
                  children: [
                    ClipOval(
                      child: SizedBox.square(dimension: 64, child: avatar),
                    ),
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.15,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              pronouns.isEmpty
                                  ? username
                                  : '$username · $pronouns',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w300,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageField extends StatelessWidget {
  const _ImageField({
    required this.title,
    required this.hint,
    required this.preview,
    required this.hasImage,
    required this.onUpload,
    required this.onRemove,
  });
  final String title, hint;
  final Widget preview;
  final bool hasImage;
  final VoidCallback onUpload, onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(Gap.l),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: br(Radius_.lg),
      ),
      child: Row(
        spacing: Gap.l,
        children: [
          preview,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (hasImage)
            TextButton(onPressed: onRemove, child: Text(tr('Remove'))),
          FilledButton.tonal(
            onPressed: onUpload,
            child: Text(tr('Upload Files')),
          ),
        ],
      ),
    );
  }
}

class _IdentityList extends StatefulWidget {
  const _IdentityList({
    required this.servers,
    required this.userId,
    required this.store,
  });
  final List<Map<String, dynamic>> servers;
  final String userId;
  final ClientStore store;
  @override
  State<_IdentityList> createState() => _IdentityListState();
}

class _IdentityListState extends State<_IdentityList> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(
      children: [
        CategoryButton(
          icon: const Icon(Icons.groups_outlined),
          title: Text(tr('Server Identities')),
          description: Text(tr('Change your profile per-server')),
          action: Icon(_open ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ColoredBox(
                    color: cs.surfaceContainer,
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final s in widget.servers)
                          ListTile(
                            dense: true,
                            leading: IconAvatar(
                              url: widget.store.api.fileUrl(
                                'icons',
                                s['icon'] as Map?,
                                width: 48,
                              ),
                              name: s['name'] as String? ?? '?',
                              size: 24,
                            ),
                            title: Text(s['name'] as String? ?? ''),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => showServerIdentity(
                              context,
                              s['_id'] as String,
                              widget.userId,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
