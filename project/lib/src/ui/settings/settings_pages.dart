import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../api/transport.dart';
import '../../core/languages.dart';
import '../../core/links.dart';
import '../../push/push_service.dart';
import '../../state/settings_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../voice/voice_manager.dart';
import '../messaging/markdown_view.dart';
import '../messaging/time_utils.dart';
import '../widgets.dart';
import 'settings_page.dart' show isDesktopPlatform;
import 'profile_editor.dart';
import '../../core/i18n.dart';

class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, required this.page, required this.onNavigate});
  final String page;
  final void Function(String) onNavigate;

  @override
  Widget build(BuildContext context) {
    if (page.startsWith('bots/'))
      return BotView(id: page.substring(5), onBack: () => onNavigate('bots'));
    return switch (page) {
      'account' => const AccountPage(),
      'profile' => ProfilePage(onNavigate: onNavigate),
      'sessions' => const SessionsPage(),
      'bots' => BotsPage(onOpen: (id) => onNavigate('bots/$id')),
      'feedback' => const FeedbackPage(),
      'voice' => const VoicePage(),
      'appearance' => const AppearancePage(),
      'notifications' => const NotificationsPage(),
      'language' => const LanguagePage(),
      'native' => const NativePage(),
      'advanced' => const AdvancedPage(),
      _ => const SizedBox.shrink(),
    };
  }
}

Widget _gap([double h = 24]) => SizedBox(height: h);

class _Check extends StatelessWidget {
  const _Check(this.value);
  final bool value;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Checkbox(value: value, onChanged: (_) {}),
  );
}

class _Select<T> extends StatelessWidget {
  const _Select({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final T value;
  final Map<T, (String, String?)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return CategoryButton(
      icon: Icon(icon),
      title: Text(tr(title)),
      description: Text(tr(options[value]?.$1 ?? '')),
      action: const Icon(Icons.unfold_more),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (c) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .6,
            maxChildSize: .9,
            builder: (c, ctl) => ListView(
              controller: ctl,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final e in options.entries)
                  ListTile(
                    title: Text(tr(e.value.$1)),
                    subtitle: e.value.$2 == null ? null : Text(tr(e.value.$2!)),
                    trailing: e.key == value ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(c, e.key),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

// ---------------- Account ----------------

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String _email = '•••••••••••@•••••••••••';
  Map<String, dynamic>? _mfa;

  @override
  void initState() {
    super.initState();
    _loadMfa();
  }

  Future<void> _loadMfa() async {
    try {
      final r = ((await context.read<ClientStore>().api.get(
        '/auth/mfa/',
      )) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _mfa = r);
    } catch (_) {}
  }

  Future<String?> _ticket() async {
    final store = context.read<ClientStore>();
    final pw = await _password(context, 'Confirm your password');
    if (pw == null) return null;
    final r = await store.api.put('/auth/mfa/ticket', {'password': pw}) as Map;
    return r['token'] as String;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final cs = context.cs;
    final me = store.me;
    final badges = _badgeAssets((me?['badges'] as num?)?.toInt() ?? 0);
    final stillOwn = store.servers.values.any(
      (s) => s['owner'] == store.userId,
    );

    Future<void> guard(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: br(Radius_.lg),
          ),
          child: Row(
            children: [
              UserAvatar(userId: store.userId, size: 64, showStatus: true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.displayName(store.userId),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${me?['username']}#${me?['discriminator']}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    if (badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          children: [
                            for (final b in badges)
                              SvgPicture.asset(
                                'assets/badges/$b.svg',
                                width: 22,
                                height: 22,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _gap(),
        CategoryGroup(
          children: [
            CategoryButton(
              icon: const Icon(Icons.alternate_email),
              title: Text(tr('Username')),
              description: Text('${me?['username']}'),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final name = await promptText(
                  context,
                  tr('Change username'),
                  label: 'New username',
                  initial: me?['username'] as String?,
                );
                if (name == null || name.isEmpty || !context.mounted) return;
                final pw = await _password(context, 'Confirm your password');
                if (pw == null) return;
                await guard(
                  () => store.api.patch('/users/@me/username', {
                    'username': name,
                    'password': pw,
                  }),
                );
              },
            ),
            CategoryButton(
              icon: const Icon(Icons.mail_outline),
              title: Text(tr('Email')),
              description: Row(
                children: [
                  Flexible(
                    child: Text(_email, overflow: TextOverflow.ellipsis),
                  ),
                  if (_email.startsWith('•'))
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: InkWell(
                        onTap: () async {
                          final r =
                              await store.api.get('/auth/account/') as Map;
                          if (mounted)
                            setState(() => _email = r['email'] as String);
                        },
                        child: Text(
                          'Reveal',
                          style: TextStyle(color: cs.primary),
                        ),
                      ),
                    ),
                ],
              ),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final email = await promptText(
                  context,
                  'Change email',
                  label: 'New email',
                );
                if (email == null || email.isEmpty || !context.mounted) return;
                final pw = await _password(context, 'Confirm your password');
                if (pw == null) return;
                await guard(
                  () => store.api.patch('/auth/account/change/email', {
                    'email': email,
                    'current_password': pw,
                  }),
                );
              },
            ),
            CategoryButton(
              icon: const Icon(Icons.password),
              title: Text(tr('Password')),
              description: const Text('•••••••••'),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final newPw = await promptText(
                  context,
                  'Change password',
                  label: tr('New Password'),
                );
                if (newPw == null || newPw.isEmpty || !context.mounted) return;
                final pw = await _password(
                  context,
                  'Confirm your current password',
                );
                if (pw == null) return;
                await guard(
                  () => store.api.patch('/auth/account/change/password', {
                    'password': newPw,
                    'current_password': pw,
                  }),
                );
              },
            ),
          ],
        ),
        _gap(),
        CategoryGroup(
          children: [
            CategoryButton(
              icon: const Icon(Icons.verified_user_outlined),
              title: Text(tr('Recovery Codes')),
              description: Text(
                tr('Configure a way to get back into your account in case your 2FA is lost'),
              ),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final ticket = await _ticket();
                if (ticket == null) return;
                await guard(() async {
                  final enabled = _mfa?['recovery_active'] == true;
                  final codes = enabled
                      ? await store.api.request(
                          'POST',
                          '/auth/mfa/recovery',
                          headers: {'x-mfa-ticket': ticket},
                        )
                      : await store.api.request(
                          'PATCH',
                          '/auth/mfa/recovery',
                          headers: {'x-mfa-ticket': ticket},
                        );
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(tr('Recovery Codes')),
                      content: SelectableText((codes as List).join('\n')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: Text(tr('Close')),
                        ),
                      ],
                    ),
                  );
                  _loadMfa();
                });
              },
            ),
            CategoryButton(
              icon: const Icon(Icons.lock_outline),
              title: Text(tr('Authenticator App')),
              description: Text(
                _mfa?['authenticator_enabled'] == true
                    ? 'Remove one-time password authenticator'
                    : 'Configure one-time password authentication',
              ),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final ticket = await _ticket();
                if (ticket == null) return;
                await guard(() async {
                  final hdr = {'x-mfa-ticket': ticket};
                  if (_mfa?['authenticator_enabled'] == true) {
                    await store.api.request(
                      'DELETE',
                      '/auth/mfa/totp',
                      headers: hdr,
                    );
                  } else {
                    final secret =
                        ((await store.api.request(
                              'POST',
                              '/auth/mfa/totp',
                              headers: hdr,
                            )) as Map)['secret']
                            as String;
                    if (!mounted) return;
                    final code = await promptText(
                      context,
                      'Enable authenticator',
                      label:
                          'Add this secret to your app: $secret — then enter the code',
                      action: 'Enable',
                    );
                    if (code == null || code.isEmpty) return;
                    await store.api.put('/auth/mfa/totp', {'totp_code': code});
                  }
                  _loadMfa();
                });
              },
            ),
          ],
        ),
        _gap(),
        CategoryGroup(
          children: [
            CategoryButton(
              icon: Icon(Icons.block, color: cs.error),
              title: Text(tr('Disable Account')),
              description: Text(
                tr("You won't be able to access your account unless you contact support - however, your data will not be deleted."),
              ),
              action: const Icon(Icons.chevron_right),
              onTap: () async {
                final ticket = await _ticket();
                if (ticket == null) return;
                await guard(() async {
                  await store.api.request(
                    'POST',
                    '/auth/account/disable',
                    headers: {'x-mfa-ticket': ticket},
                  );
                  await store.logout();
                });
              },
            ),
            CategoryButton(
              icon: Icon(Icons.delete_outline, color: cs.error),
              title: Text(
                stillOwn
                    ? 'Cannot delete account until servers are deleted or transferred'
                    : 'Delete Account',
              ),
              description: Text(
                tr('Your account and all of your data (including your messages and friends list) will be queued for deletion. A confirmation email will be sent - you can cancel this within 7 days by contacting support.'),
              ),
              action: stillOwn ? null : const Icon(Icons.chevron_right),
              onTap: stillOwn
                  ? null
                  : () async {
                      final ticket = await _ticket();
                      if (ticket == null) return;
                      await guard(() async {
                        await store.api.request(
                          'POST',
                          '/auth/account/delete',
                          headers: {'x-mfa-ticket': ticket},
                        );
                        await store.logout();
                      });
                    },
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _password(BuildContext context, String title) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(title)),
      content: TextField(
        controller: ctl,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Password')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctl.text),
          child: Text(tr('Confirm')),
        ),
      ],
    ),
  );
}

List<String> _badgeAssets(int bits) {
  const map = {
    1: 'developer',
    2: 'translator',
    4: 'supporter',
    8: 'verified',
    16: 'founder',
    32: 'moderation',
    128: 'paw',
    256: 'early_adopter',
    512: 'amog',
    1024: 'amorbus',
    2048: 'raccoon',
  };
  return [
    for (final e in map.entries)
      if (bits & e.key != 0) e.value,
  ];
}

// ---------------- Sessions ----------------

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});
  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await context.read<ClientStore>().sessions();
    if (mounted) setState(() => _list = s);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cs = context.cs;
    final list = _list;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final current = context.read<SettingsStore>().sessionIdFor(store.host);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.tonal(
          onPressed: () async {
            await store.revokeAllSessions();
            _load();
          },
          child: Text(tr('Log out of all other sessions')),
        ),
        _gap(16),
        CategoryGroup(
          children: [
            for (final s in list)
              CategoryButton(
                icon: Icon(
                  s['_id'] == current ? Icons.smartphone : Icons.devices_other,
                ),
                title: Text(
                  '${s['name'] ?? 'Unknown'}${s['_id'] == current ? ' (this device)' : ''}',
                ),
                description: Text(s['_id'] as String),
                action: s['_id'] == current
                    ? null
                    : IconButton(
                        icon: Icon(Icons.logout, color: cs.error),
                        onPressed: () async {
                          await store.revokeSession(s['_id'] as String);
                          _load();
                        },
                      ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Bots ----------------

class BotsPage extends StatefulWidget {
  const BotsPage({super.key, required this.onOpen});
  final void Function(String) onOpen;
  @override
  State<BotsPage> createState() => _BotsPageState();
}

class _BotsPageState extends State<BotsPage> {
  List<Map<String, dynamic>>? _bots;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await context.read<ClientStore>().myBots();
    if (mounted) setState(() => _bots = b);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final bots = _bots;
    if (bots == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.add),
          label: Text(tr('Create Bot')),
          onPressed: () async {
            final name = await promptText(
              context,
              tr('Create Bot'),
              label: 'Bot name',
              action: tr('Create'),
            );
            if (name == null || name.isEmpty) return;
            try {
              await store.api.post('/bots/create', {'name': name});
              _load();
            } catch (e) {
              if (mounted) showSnack(context, errorText(e));
            }
          },
        ),
        _gap(16),
        if (bots.isEmpty)
          const Text("You haven't created any bots yet.")
        else
          CategoryGroup(
            children: [
              for (final b in bots)
                CategoryButton(
                  icon: UserAvatar(userId: b['_id'] as String?, size: 28),
                  title: Text(store.displayName(b['_id'] as String?)),
                  action: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpen(b['_id'] as String),
                ),
            ],
          ),
      ],
    );
  }
}

class BotView extends StatefulWidget {
  const BotView({super.key, required this.id, required this.onBack});
  final String id;
  final VoidCallback onBack;
  @override
  State<BotView> createState() => _BotViewState();
}

class _BotViewState extends State<BotView> {
  String? _token;
  bool _public = false;

  @override
  void initState() {
    super.initState();
    context.read<ClientStore>().api.get('/bots/${widget.id}').then((r) {
      final bot = ((r as Map)['bot'] as Map);
      if (mounted)
        setState(() {
          _token = bot['token'] as String?;
          _public = bot['public'] == true;
        });
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryGroup(
          children: [
            CategoryButton(
              icon: const Icon(Icons.key),
              title: const Text('Token'),
              description: Text(_token == null ? 'Loading…' : '•' * 24),
              action: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: _token == null
                    ? null
                    : () => copyText(context, _token!),
              ),
            ),
            CategoryButton(
              icon: const Icon(Icons.public),
              title: const Text('Public bot'),
              description: const Text(
                'Allow anyone to add this bot to their servers.',
              ),
              action: Switch(
                value: _public,
                onChanged: (v) async {
                  await store.api.patch('/bots/${widget.id}', {'public': v});
                  setState(() => _public = v);
                },
              ),
            ),
            CategoryButton(
              icon: Icon(Icons.delete_outline, color: cs.error),
              title: Text(tr('Delete Bot')),
              destructive: true,
              onTap: () async {
                if (await confirm(
                  context,
                  'Delete bot?',
                  'This cannot be undone.',
                  action: tr('Delete'),
                )) {
                  await store.api.delete('/bots/${widget.id}');
                  widget.onBack();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Feedback ----------------

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final inLounge = store.servers.containsKey(loungeServerId);
    Widget link(IconData i, String t, String d, String url) => CategoryButton(
      icon: Icon(i),
      title: Text(tr(t)),
      description: Text(tr(d)),
      action: const Icon(Icons.open_in_new),
      onTap: () => openUrl(url),
    );
    return CategoryGroup(
      children: [
        link(
          Icons.star_outline,
          tr('Submit feature suggestion'),
          tr('Suggest new DawnChat features on GitHub discussions.'),
          roadmapUrl,
        ),
        link(
          Icons.format_list_numbered,
          tr('Feedback'),
          tr('Submit feedback'),
          feedbackUrl,
        ),
        link(
          Icons.bug_report_outlined,
          tr('Bug Tracker'),
          tr('View currently active bug reports here.'),
          bugTrackerUrl,
        ),
        CategoryButton(
          icon: const Icon(Icons.groups_3),
          title: Text(
            inLounge ? 'Go to the DawnChat Lounge' : 'Join the DawnChat Lounge',
          ),
          description: Text(
            tr('You can report issues and discuss improvements with us directly here.'),
          ),
          onTap: () {
            Navigator.of(context).pop();
            final host = store.host;
            final path = inLounge
                ? '/server/$loungeServerId'
                : '/invite/Testers';
            GoRouterNav.go(context, host == null ? path : '/i/$host$path');
          },
        ),
      ],
    );
  }
}

class GoRouterNav {
  static void go(BuildContext context, String path) => context.go(path);
}

// ---------------- Voice ----------------

class VoicePage extends StatefulWidget {
  const VoicePage({super.key});
  @override
  State<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends State<VoicePage> {
  List<lk.MediaDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await lk.Hardware.instance.enumerateDevices();
      if (mounted) setState(() => _devices = d);
    } catch (_) {}
  }

  Map<String?, (String, String?)> _opts(String kind, String fallback) {
    final out = <String?, (String, String?)>{null: ('Default', null)};
    var n = 0;
    for (final d in _devices.where((d) => d.kind == kind)) {
      if (d.deviceId == 'default') continue;
      n++;
      out[d.deviceId] = (
        d.label.trim().isEmpty ? '$fallback $n' : d.label,
        null,
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final video = context.read<ClientStore>().api.config?.video ?? true;
    String pct(double v) => '${(v * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryGroup(
          children: [
            _Select<String?>(
              icon: Icons.mic,
              title: tr('Select audio input'),
              value: s.audioInput,
              options: _opts('audioinput', 'Microphone'),
              onChanged: (v) => s.audioInput = v,
            ),
            _Select<String?>(
              icon: Icons.speaker,
              title: tr('Select audio output'),
              value: s.audioOutput,
              options: _opts('audiooutput', 'Speaker'),
              onChanged: (v) => s.audioOutput = v,
            ),
            if (video)
              _Select<String?>(
                icon: Icons.videocam_outlined,
                title: tr('Select video input'),
                value: s.videoInput,
                options: _opts('videoinput', 'Camera'),
                onChanged: (v) => s.videoInput = v,
              ),
          ],
        ),
        _gap(16),
        Text(
          'Input Volume  ${pct(s.inputVolume)}',
          style: context.tt.labelLarge,
        ),
        Slider(
          value: s.inputVolume,
          min: 0,
          max: 3,
          divisions: 30,
          onChanged: (v) => s.inputVolume = v,
        ),
        Text(
          'Output Volume  ${pct(s.outputVolume)}',
          style: context.tt.labelLarge,
        ),
        Slider(
          value: s.outputVolume,
          min: 0,
          max: 3,
          divisions: 30,
          onChanged: (v) => s.outputVolume = v,
        ),
        SectionTitle(tr('Voice Processing')),
        CategoryGroup(
          children: [
            _Select<String>(
              icon: Icons.graphic_eq,
              title: tr('Select noise suppression'),
              value: s.noiseSuppression,
              options: const {
                'disabled': ('Disabled', null),
                'browser': ('Browser', null),
                'enhanced': ('Enhanced (RNNoise)', 'Powered by RNNoise'),
              },
              onChanged: (v) => s.noiseSuppression = v,
            ),
            CategoryButton(
              title: Text(tr('Browser Echo Cancellation')),
              action: _Check(s.echoCancellation),
              onTap: () => s.echoCancellation = !s.echoCancellation,
            ),
            CategoryButton(
              title: Text(tr('Automatic Gain Control')),
              action: _Check(s.autoGainControl),
              onTap: () => s.autoGainControl = !s.autoGainControl,
            ),
          ],
        ),
        SectionTitle(tr('Screen Share Settings')),
        CategoryGroup(
          children: [
            _Select<String>(
              icon: Icons.screen_share,
              title: tr('Select screen share quality'),
              value: s.screenShareQuality,
              options: const {
                'low': ('720p at 30fps', null),
                'high': ('1080p at 30fps', null),
                'text': ('Source resolution at 5fps (best for text)', null),
              },
              onChanged: (v) => s.screenShareQuality = v,
            ),
            CategoryButton(
              title: Text(tr('Always Ask for Screen Share Quality')),
              action: _Check(s.screenShareQualityAsk),
              onTap: () => s.screenShareQualityAsk = !s.screenShareQualityAsk,
            ),
            CategoryButton(
              title: const Text('Share Audio with Screen Share'),
              action: _Check(s.screenShareAudio),
              onTap: () => s.screenShareAudio = !s.screenShareAudio,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Appearance ----------------

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final store = context.watch<ClientStore>();
    final cs = context.cs;

    Widget connected<T>(
      List<(String, T)> items,
      T value,
      ValueChanged<T> onSel, {
      bool small = false,
    }) => SegmentedButton<T>(
      showSelectedIcon: false,
      style: small
          ? const ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
            )
          : null,
      segments: [
        for (final i in items) ButtonSegment(value: i.$2, label: Text(tr(i.$1))),
      ],
      selected: {value},
      onSelectionChanged: (v) => onSel(v.first),
    );

    const accents = [
      '#FF5733',
      '#ffdc2f',
      '#9bf088',
      '#54ecc1',
      '#549bec',
      '#5470ec',
      '#8C5FD3',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Text(
            'Welcome to the new appearance menu, custom themes are not available just yet but we are looking for feedback on how to best implement them!',
          ),
        ),
        const SectionTitle('Colours', small: true),
        SizedBox(
          width: double.infinity,
          child: connected<String>(
            const [('Light', 'light'), ('Dark', 'dark'), ('System', 'system')],
            s.mode,
            (v) => s.mode = v,
          ),
        ),
        _gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton.filled(
              icon: const Icon(Icons.palette_outlined),
              onPressed: () async {
                final hex = await promptText(
                  context,
                  'Custom accent',
                  label: 'Hex colour (#RRGGBB)',
                  initial: s.m3Accent,
                );
                if (hex != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex))
                  s.m3Accent = hex;
              },
            ),
            for (final c in accents)
              InkWell(
                borderRadius: br(24),
                onTap: () => s.m3Accent = c,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: parseHex(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: s.m3Accent.toLowerCase() == c.toLowerCase()
                          ? cs.onSurface
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
        _gap(12),
        SizedBox(
          width: double.infinity,
          child: connected<double>(
            const [
              ('Reduced', -1.0),
              ('Normal', 0.0),
              ('More Contrast', 0.5),
              ('High Contrast', 1.0),
            ],
            s.m3Contrast,
            (v) => s.m3Contrast = v,
            small: true,
          ),
        ),
        _gap(8),
        SizedBox(
          width: double.infinity,
          child: connected<String>(
            const [
              ('Monochrome', 'monochrome'),
              ('Neutral', 'neutral'),
              ('Tonal Spot', 'tonal_spot'),
              ('Fruit Salad', 'fruit_salad'),
            ],
            m3Variants.contains(s.m3Variant) &&
                    const {
                      'monochrome',
                      'neutral',
                      'tonal_spot',
                      'fruit_salad',
                    }.contains(s.m3Variant)
                ? s.m3Variant
                : 'tonal_spot',
            (v) => s.m3Variant = v,
            small: true,
          ),
        ),
        SectionTitle(tr('Display & Text'), small: true),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.blur,
          onChanged: (v) => s.blur = v ?? true,
          title: Text(
            tr('Enable transparency glass/blur effects (slow on older machines)'),
          ),
        ),
        Container(
          height: 126,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: br(Radius_.lg),
          ),
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(userId: store.userId, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.displayName(store.userId),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: s.messageSize,
                          ),
                        ),
                        Text(
                          'Sphinx of black quartz, judge my vow',
                          style: TextStyle(fontSize: s.messageSize),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: s.messageGroupSpacing),
              Row(
                children: [
                  const UserAvatar(userId: null, size: 36, fallbackName: 'M'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MysticPixie',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: s.messageSize,
                          ),
                        ),
                        Text(
                          'The quick brown fox jumped over the lazy dog',
                          style: monoStyle(
                            s,
                            TextStyle(fontSize: s.messageSize),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _gap(8),
        Text(tr('Message Size'), style: context.tt.labelLarge),
        Slider(
          value: s.messageSize,
          min: 12,
          max: 24,
          divisions: 12,
          label: '${s.messageSize.round()}',
          onChanged: (v) => s.messageSize = v,
        ),
        Text(tr('Message Group Spacing'), style: context.tt.labelLarge),
        Slider(
          value: s.messageGroupSpacing,
          min: 0,
          max: 16,
          divisions: 16,
          label: '${s.messageGroupSpacing.round()}',
          onChanged: (v) => s.messageGroupSpacing = v,
        ),
        _gap(8),
        DropdownMenu<String>(
          width: 320,
          label: Text(tr('Interface Font')),
          initialSelection: s.interfaceFont,
          dropdownMenuEntries: [
            for (final f in interfaceFonts)
              DropdownMenuEntry(value: f, label: f),
          ],
          onSelected: (v) => v == null ? null : s.interfaceFont = v,
        ),
        _gap(16),
        DropdownMenu<String>(
          width: 320,
          label: Text(tr('Monospace Font')),
          initialSelection: s.monospaceFont,
          dropdownMenuEntries: [
            for (final f in monospaceFonts)
              DropdownMenuEntry(value: f, label: f),
          ],
          onSelected: (v) => v == null ? null : s.monospaceFont = v,
        ),
        SectionTitle(tr('Chat Input'), small: true),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.showSendButton,
          onChanged: (v) => s.showSendButton = v ?? true,
          title: Text(tr('Show send message button')),
        ),
        _gap(8),
        DropdownMenu<String>(
          width: 320,
          label: Text(tr('Emoji Pack (affects your messages only)')),
          initialSelection: s.unicodeEmoji,
          dropdownMenuEntries: [
            for (final p in unicodeEmojiPacks)
              DropdownMenuEntry(
                value: p,
                label:
                    const {
                      'fluent-3d': 'Fluent 3D',
                      'fluent-color': 'Fluent Color',
                      'fluent-flat': 'Fluent Flat',
                      'mutant': 'Mutant Remix',
                      'noto': 'Noto',
                      'twemoji': 'Twemoji',
                    }[p] ??
                    p,
              ),
          ],
          onSelected: (v) => v == null ? null : s.unicodeEmoji = v,
        ),
      ],
    );
  }
}

// ---------------- Notifications ----------------

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final push = context.read<PushService>();
    final sounds = context.read<SoundService>();
    const labels = {
      'message': 'Message Received',
      'mute': 'Mute',
      'unmute': 'Unmute',
      'deafen': 'Deafen',
      'undeafen': 'Undeafen',
      'userJoinVoice': 'User Joined Call',
      'userLeaveVoice': 'User Left Call',
      'streamStart': 'Stream Start',
      'streamEnd': 'Stream End',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryGroup(
          children: [
            if (push.desktopSupported &&
                s.desktopNotifications != 'unsupported')
              CategoryButton(
                icon: const Icon(Icons.notifications_none),
                title: Text(tr('Enable Desktop Notifications')),
                description: Text(
                  isDesktopPlatform || !kIsWeb
                      ? 'Receive notifications while the app is open and in the background.'
                      : 'Receive notifications while the tab is open.',
                ),
                action: _Check(s.desktopNotifications == 'allowed'),
                onTap: () => push.toggleDesktop(context),
              ),
            CategoryButton(
              icon: const Icon(Icons.mark_unread_chat_alt_outlined),
              title: Text(tr('Enable Push Notifications')),
              description: Text(
                tr('Receive push notifications while the app is closed.'),
              ),
              action: _Check(s.pushNotifications == 'allowed'),
              onTap: () => push.togglePush(context),
            ),
          ],
        ),
        if (s.desktopNotifications != 'unsupported' ||
            push.desktopSupported) ...[
          SectionTitle(tr('Sounds')),
          CategoryGroup(
            children: [
              for (final e in labels.entries)
                CategoryButton(
                  title: Text(e.value),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        tooltip: tr('Play sound'),
                        onPressed: () => sounds.play(e.key, force: true),
                      ),
                      _Check(s.soundEnabled(e.key)),
                    ],
                  ),
                  onTap: () => s.toggleSound(e.key),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------- Language ----------------

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    final langs = {
      for (final l in appLanguages)
        l.code: ('${l.emoji}  ${l.display}', null as String?),
    };
    final lastWeek = DateTime.now().subtract(const Duration(days: 7));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryGroup(
          children: [
            _Select<String>(
              icon: Icons.language,
              title: tr('Select your language'),
              value: langs.containsKey(s.lang) ? s.lang : 'en',
              options: langs,
              onChanged: (v) => s.lang = v,
            ),
          ],
        ),
        _gap(24),
        CategoryGroup(
          children: [
            _Select<String>(
              icon: Icons.calendar_month_outlined,
              title: tr('Date format'),
              value: s.dateFormat,
              options: {
                'DD/MM/YYYY': (
                  'Traditional (DD/MM/YYYY) — ${_fmt(lastWeek, 'DD/MM/YYYY')}',
                  null,
                ),
                'MM/DD/YYYY': (
                  'American (MM/DD/YYYY) — ${_fmt(lastWeek, 'MM/DD/YYYY')}',
                  null,
                ),
                'YYYY-MM-DD': (
                  'ISO Standard (YYYY-MM-DD) — ${_fmt(lastWeek, 'YYYY-MM-DD')}',
                  null,
                ),
              },
              onChanged: (v) => s.dateFormat = v,
            ),
            _Select<String>(
              icon: Icons.schedule,
              title: tr('Time format'),
              value: s.timeFormat,
              options: const {
                'HH:mm': ('24 hours', null),
                'h:mm A': ('12 hours', null),
              },
              onChanged: (v) => s.timeFormat = v,
            ),
          ],
        ),
        _gap(24),
        CategoryGroup(
          children: [
            CategoryButton(
              icon: const Icon(Icons.translate),
              title: Text(tr('Contribute a language')),
              description: Text(
                tr('Help contribute to an existing or new language'),
              ),
              action: const Icon(Icons.open_in_new),
              onTap: () => openUrl(translationsUrl),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(DateTime t, String f) {
    final d = t.day.toString().padLeft(2, '0'),
        m = t.month.toString().padLeft(2, '0');
    return f == 'MM/DD/YYYY'
        ? '$m/$d/${t.year}'
        : f == 'YYYY-MM-DD'
        ? '${t.year}-$m-$d'
        : '$d/$m/${t.year}';
  }
}

// ---------------- Native (desktop) ----------------

class NativePage extends StatefulWidget {
  const NativePage({super.key});
  @override
  State<NativePage> createState() => _NativePageState();
}

class _NativePageState extends State<NativePage> {
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    launchAtStartup
        .isEnabled()
        .then((v) {
          if (mounted) setState(() => _autostart = v);
        })
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    Widget toggle(
      String title,
      String desc,
      IconData icon,
      bool v,
      ValueChanged<bool> set,
    ) => CategoryButton(
      icon: Icon(icon),
      title: Text(tr(title)),
      description: Text(tr(desc)),
      action: _Check(v),
      onTap: () => set(!v),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CategoryGroup(
          children: [
            toggle(
              tr('Start with Computer'),
              tr('Launch DawnChat when you log into your computer.'),
              Icons.exit_to_app,
              _autostart,
              (v) async {
                if (v) {
                  await launchAtStartup.enable();
                } else {
                  await launchAtStartup.disable();
                }
                setState(() => _autostart = v);
              },
            ),
            if (_autostart)
              toggle(
                tr('Start Minimised to Tray'),
                tr('DawnChat will start in the system tray.'),
                Icons.minimize,
                s.startMinimisedToTray,
                (v) => s.startMinimisedToTray = v,
              ),
            toggle(
              tr('Minimise to Tray'),
              tr('Instead of closing, DawnChat will hide in your tray.'),
              Icons.cancel_presentation,
              s.minimiseToTray,
              (v) => s.minimiseToTray = v,
            ),
            toggle(
              tr('Custom window frame'),
              tr('Let DawnChat use its own custom titlebar.'),
              Icons.web_asset,
              s.customFrame,
              (v) => s.customFrame = v,
            ),
          ],
        ),
        _gap(24),
        CategoryGroup(
          children: [
            toggle(
              tr('Discord RPC'),
              tr('Rep DawnChat using Discord rich presence.'),
              Icons.groups_2,
              s.discordRpc,
              (v) => s.discordRpc = v,
            ),
            toggle(
              tr('Spellchecker'),
              tr('Show corrections and suggestions as you type.'),
              Icons.spellcheck,
              s.spellchecker,
              (v) => s.spellchecker = v,
            ),
            toggle(
              tr('Hardware Acceleration'),
              tr('Use the graphics card to improve performance.'),
              Icons.speed,
              s.hardwareAcceleration,
              (v) => s.hardwareAcceleration = v,
            ),
          ],
        ),
        _gap(24),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (c, snap) => CategoryGroup(
            children: [
              CategoryButton(
                icon: const Icon(Icons.desktop_windows_outlined),
                title: Text(tr('DawnChat for Desktop')),
                description: Text('Version: ${snap.data?.version ?? ''}'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- Advanced ----------------

class AdvancedPage extends StatelessWidget {
  const AdvancedPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    Widget cb(String t, bool v, ValueChanged<bool> set) => CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: v,
      onChanged: (x) => set(x ?? false),
      title: Text(tr(t)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cb('Compact mode', s.compactMode, (v) => s.compactMode = v),
        cb("Show 'copy ID' in context menus", s.copyId, (v) => s.copyId = v),
        cb(
          'Show admin panel shortcuts in context menus',
          s.adminPanel,
          (v) => s.adminPanel = v,
        ),
        _gap(24),
        CategoryGroup(
          children: [
            CategoryButton(
              title: const Text('GIF Picker Placeholder'),
              description: const Text('Not available yet.'),
              action: const _Check(false),
            ),
            CategoryButton(
              title: const Text('Plugins v2 Placeholder'),
              description: const Text('Not available yet.'),
              action: const _Check(false),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------- Changelog ----------------

Future<void> showChangelog(BuildContext context) async {
  try {
    final res = await sendRequest(
      'GET',
      changelogUrl,
      headers: {'Accept': 'application/json'},
    );
    if (res.status >= 400) return;
    final data = jsonDecode(res.text) as Map;
    if (!context.mounted) return;
    final s = context.read<SettingsStore>();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(data['title'] as String? ?? "What's New"),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data['published_at'] != null)
                  Text(
                    formatDate(
                      s,
                      DateTime.tryParse(data['published_at'] as String)
                              ?.toLocal() ??
                          DateTime.now(),
                    ),
                  ),
                const SizedBox(height: 8),
                RichContent((data['markdown_content'] as String?) ?? ''),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Close')),
          ),
        ],
      ),
    );
  } catch (_) {}
}
