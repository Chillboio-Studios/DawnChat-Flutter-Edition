import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../widgets.dart';
import 'auth_page.dart';
import '../../core/i18n.dart';

String? _pendingEmail;

/// Shared form that reports typing, submit, success and error state to the bubble.
class _FlowForm extends StatefulWidget {
  const _FlowForm({
    required this.fields,
    required this.submitLabel,
    required this.onSubmit,
    this.extra,
    this.footer,
  });

  final List<String> fields;
  final String submitLabel;
  final Future<void> Function(Map<String, String> data) onSubmit;
  final List<Widget>? extra;
  final List<Widget>? footer;

  @override
  State<_FlowForm> createState() => _FlowFormState();
}

class _FlowFormState extends State<_FlowForm> {
  final _key = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  final Map<String, bool> _obscure = {};
  String? _error;
  bool _busy = false;

  TextEditingController ctl(String f) =>
      _c.putIfAbsent(f, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    final bubble = BubbleControls.of(context);
    final done = bubble.beginSubmit();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit({
        for (final f in widget.fields) f: ctl(f).text.trim(),
      });
      done();
      bubble.flashSuccess();
    } catch (e) {
      done();
      bubble.flashError();
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final bubble = BubbleControls.of(context);
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _field(f, bubble),
            ),
          ...?widget.extra,
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _busy ? null : _submit,
                child: Text(widget.submitLabel),
              ),
            ),
          ),
          ...?widget.footer,
        ],
      ),
    );
  }

  Widget _field(String f, AuthPageState bubble) {
    final isPassword = f == 'password' || f == 'new-password';
    final label = switch (f) {
      'email' => 'Email',
      'password' => 'Password',
      'new-password' => 'Password',
      'username' => 'Username',
      'invite' => 'Invite code',
      'token' => 'Session token',
      _ => f,
    };
    final obscured = isPassword && (_obscure[f] ?? true);
    return TextFormField(
      controller: ctl(f),
      obscureText: obscured,
      onChanged: (_) => bubble.onInput(),
      onFieldSubmitted: (_) => _submit(),
      keyboardType: f == 'email'
          ? TextInputType.emailAddress
          : TextInputType.text,
      autofillHints: [
        switch (f) {
          'email' => AutofillHints.email,
          'password' => AutofillHints.password,
          'new-password' => AutofillHints.newPassword,
          'username' => AutofillHints.username,
          _ => '',
        },
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscured ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure[f] = !obscured),
              )
            : null,
      ),
      validator: (v) =>
          (f == 'invite' || (v != null && v.isNotEmpty)) ? null : 'Required',
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(this.label, this.path, {this.icon});
  final String label, path;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: TextButton(
      onPressed: () => context.go(context.href(path)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 4)],
          Text(tr(label)),
        ],
      ),
    ),
  );
}

class FlowLogin extends StatefulWidget {
  const FlowLogin({super.key});
  @override
  State<FlowLogin> createState() => _FlowLoginState();
}

class _FlowLoginState extends State<FlowLogin> {
  Map<String, dynamic>? _mfa;
  bool _onboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  /// The web client checks `/onboard/hello` after login and asks for a
  /// username when the account has none (`TransitionType.NoUser`).
  Future<void> _checkOnboarding() async {
    final store = context.read<ClientStore>();
    if (store.authState != AuthState.loggedIn) return;
    try {
      final r = await store.api.get('/onboard/hello') as Map;
      if (mounted && r['onboarding'] == true) {
        setState(() => _onboarding = true);
      }
    } catch (_) {}
  }

  Future<void> _selectUsername(String username) async {
    final store = context.read<ClientStore>();
    await store.api.post('/onboard/complete', {'username': username});
    // Re-fetch user data so the sidebar/profile show the new username.
    final me = await store.api.get('/users/@me') as Map;
    final id = me['_id'] as String?;
    if (id != null) {
      store.users[id] = me.cast<String, dynamic>();
      store.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClientStore>();
    final settings = context.read<SettingsStore>();

    if (_onboarding) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTitle(
            tr('Choose a username'),
            subtitle: tr(
              'Pick a username that you want people to be able to find you by. This can be changed later in your user settings.',
            ),
          ),
          const SizedBox(height: 16),
          _FlowForm(
            fields: const ['username'],
            submitLabel: tr('Confirm'),
            onSubmit: (d) => _selectUsername(d['username']!),
            footer: [
              _LinkButton(tr('Cancel'), '/login/auth', icon: Icons.arrow_back),
            ],
          ),
        ],
      );
    }

    if (store.authState == AuthState.loggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final next = settings.nextPath ?? '/app';
        settings.nextPath = null;
        context.go(context.href(next));
      });
      return FlowTitle(tr('Logging you in…'));
    }

    if (_mfa != null) {
      return _MfaStep(
        ticket: _mfa!['ticket'] as String,
        methods: ((_mfa!['allowed_methods'] as List?) ?? ['Totp'])
            .cast<String>(),
        onCancel: () => setState(() => _mfa = null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowTitle(
          tr('Welcome back'),
          subtitle: tr('Log in to pick up right where you left off.'),
        ),
        const SizedBox(height: 16),
        _FlowForm(
          fields: const ['email', 'password'],
          submitLabel: tr('Log in'),
          extra: [
            _LinkButton(tr('Forgot password?'), '/login/reset'),
            _LinkButton(tr('Resend verification'), '/login/resend'),
          ],
          onSubmit: (d) async {
            final mfa = await store.login(d['email']!, d['password']!);
            if (mfa != null && mounted) setState(() => _mfa = mfa);
          },
        ),
      ],
    );
  }
}

class _MfaStep extends StatefulWidget {
  const _MfaStep({
    required this.ticket,
    required this.methods,
    required this.onCancel,
  });
  final String ticket;
  final List<String> methods;
  final VoidCallback onCancel;
  @override
  State<_MfaStep> createState() => _MfaStepState();
}

class _MfaStepState extends State<_MfaStep> {
  late String method = widget.methods.first;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final label = method == 'Totp'
        ? 'Authenticator code'
        : method == 'Recovery'
        ? 'Recovery code'
        : 'Password';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FlowTitle(
          'Two-factor authentication',
          subtitle: 'Enter your second factor to continue.',
        ),
        const SizedBox(height: 16),
        if (widget.methods.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SegmentedButton<String>(
              segments: [
                for (final m in widget.methods)
                  ButtonSegment(value: m, label: Text(tr(m))),
              ],
              selected: {method},
              onSelectionChanged: (s) => setState(() => method = s.first),
            ),
          ),
        _FlowForm(
          fields: const ['token'],
          submitLabel: tr('Continue'),
          onSubmit: (d) async {
            final v = d['token']!;
            await store.loginMfa(widget.ticket, switch (method) {
              'Totp' => {'totp_code': v},
              'Recovery' => {'recovery_code': v},
              _ => {'password': v},
            });
          },
        ),
        TextButton(onPressed: widget.onCancel, child: Text('Cancel ($label)')),
      ],
    );
  }
}

class FlowToken extends StatelessWidget {
  const FlowToken({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FlowTitle(
          'Use a session token',
          subtitle: 'Paste an existing session token to log in.',
        ),
        const SizedBox(height: 16),
        _FlowForm(
          fields: const ['token'],
          submitLabel: tr('Log in'),
          onSubmit: (d) => store.loginWithToken(d['token']!),
          footer: [
            _LinkButton(tr('Back'), '/login/auth', icon: Icons.arrow_back),
          ],
        ),
      ],
    );
  }
}

class FlowCreate extends StatelessWidget {
  const FlowCreate({super.key, required this.code});
  final String? code;

  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    final cfg = store.api.config;
    final cs = context.cs;
    final inviteOnly = cfg?.invite_only ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowTitle(
          tr('Join DawnChat'),
          subtitle: tr('Set up your account and make yourself at home.'),
        ),
        const SizedBox(height: 16),
        _FlowForm(
          fields: ['email', 'new-password', if (inviteOnly) 'invite'],
          submitLabel: tr('Create account'),
          extra: [
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: br(Radius_.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Your email stays private'),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            "We only use it to verify your account and help you get back in if you're ever locked out. We'll never sell it or send you spam.",
                          ),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => openUrl(termsUrl),
                          child: Text(
                            tr('Privacy policy'),
                            style: TextStyle(color: cs.primary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          onSubmit: (d) async {
            if (cfg?.captchaEnabled ?? false) {
              await openUrl('$dawnchatChatUrl/login/create');
              throw 'Account creation requires a captcha; finish signing up in your browser.';
            }
            await store.api.post('/auth/account/create', {
              'email': d['email'],
              'password': d['new-password'],
              if ((d['invite'] ?? code ?? '').isNotEmpty)
                'invite': d['invite']?.isNotEmpty == true ? d['invite'] : code,
            });
            if (!context.mounted) return;
            if (cfg?.emailVerification ?? false) {
              _pendingEmail = d['email'];
              context.go(context.href('/login/check'));
            } else {
              await store.login(d['email']!, d['new-password']!);
            }
          },
          footer: [
            _LinkButton(tr('Back'), '/login/auth', icon: Icons.arrow_back),
          ],
        ),
      ],
    );
  }
}

class FlowCheck extends StatelessWidget {
  const FlowCheck({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowTitle(tr('Check your email')),
      const SizedBox(height: 12),
      Text(
        _pendingEmail == null
            ? "We've sent you a verification link."
            : "We've sent a verification link to $_pendingEmail.",
      ),
      const SizedBox(height: 16),
      const _LinkButton('Back to login', '/login/auth', icon: Icons.arrow_back),
    ],
  );
}

class FlowResend extends StatelessWidget {
  const FlowResend({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowTitle(
          tr('Resend verification'),
          subtitle: "We'll send a new verification link to your email.",
        ),
        const SizedBox(height: 16),
        _FlowForm(
          fields: const ['email'],
          submitLabel: tr('Resend'),
          onSubmit: (d) async {
            await store.api.post('/auth/account/reverify', {
              'email': d['email'],
            });
            _pendingEmail = d['email'];
            if (context.mounted) context.go(context.href('/login/check'));
          },
          footer: [
            _LinkButton(tr('Back'), '/login/auth', icon: Icons.arrow_back),
          ],
        ),
      ],
    );
  }
}

class FlowReset extends StatelessWidget {
  const FlowReset({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FlowTitle(
          tr('Reset password'),
          subtitle: "Enter your email and we'll send you a reset link.",
        ),
        const SizedBox(height: 16),
        _FlowForm(
          fields: const ['email'],
          submitLabel: 'Send reset link',
          onSubmit: (d) async {
            await store.api.post('/auth/account/reset_password', {
              'email': d['email'],
            });
            _pendingEmail = d['email'];
            if (context.mounted) context.go(context.href('/login/check'));
          },
          footer: [
            _LinkButton(tr('Back'), '/login/auth', icon: Icons.arrow_back),
          ],
        ),
      ],
    );
  }
}

class FlowConfirmReset extends StatelessWidget {
  const FlowConfirmReset({super.key, required this.token});
  final String token;
  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FlowTitle('Choose a new password'),
        const SizedBox(height: 16),
        _FlowForm(
          fields: const ['new-password'],
          submitLabel: tr('Reset password'),
          onSubmit: (d) async {
            await store.api.patch('/auth/account/reset_password', {
              'token': token,
              'password': d['new-password'],
              'remove_sessions': true,
            });
            if (context.mounted) context.go(context.href('/login/auth'));
          },
        ),
      ],
    );
  }
}

class FlowVerify extends StatefulWidget {
  const FlowVerify({super.key, required this.token});
  final String token;
  @override
  State<FlowVerify> createState() => _FlowVerifyState();
}

class _FlowVerifyState extends State<FlowVerify> {
  Future<void>? _f;

  @override
  void initState() {
    super.initState();
    _f = context.read<ClientStore>().api.post(
      '/auth/account/verify/${widget.token}',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _f,
    builder: (c, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const FlowTitle('Verifying…');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FlowTitle(
            snap.hasError ? 'Verification failed' : 'Email verified',
            subtitle: snap.hasError
                ? 'The link may have expired. Request a new one.'
                : 'Your email has been verified. You can now log in.',
          ),
          const SizedBox(height: 16),
          _LinkButton(
            snap.hasError ? 'Resend verification' : 'Log in',
            snap.hasError ? '/login/resend' : '/login/auth',
          ),
        ],
      );
    },
  );
}

class DeleteAccountFlow extends StatelessWidget {
  const DeleteAccountFlow({super.key, required this.token});
  final String token;
  @override
  Widget build(BuildContext context) {
    final store = context.read<ClientStore>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FlowTitle(
          'Delete your account',
          subtitle: 'This confirms the deletion of your account. This cannot be undone.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.cs.error,
            foregroundColor: context.cs.onError,
            minimumSize: const Size(0, 54),
          ),
          onPressed: () async {
            try {
              await store.api.put('/auth/account/delete', {'token': token});
              if (context.mounted) context.go(context.href('/login/auth'));
            } on ApiException catch (e) {
              if (context.mounted) showSnack(context, e.toString());
            }
          },
          child: Text(tr('Delete Account')),
        ),
      ],
    );
  }
}
