import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/client_store.dart';
import '../../core/links.dart';
import '../../router.dart';
import '../../state/settings_store.dart';
import '../../theme/tokens.dart';
import '../modals/app_dialog.dart';
import '../widgets.dart';
import '../../core/i18n.dart';

enum BubbleMood { idle, typing, submitting, success, error }

/// Lets flows drive the shared chat bubble at the top of the form.
class BubbleControls extends InheritedWidget {
  const BubbleControls({super.key, required this.state, required super.child});
  final AuthPageState state;

  static AuthPageState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BubbleControls>()!.state;

  @override
  bool updateShouldNotify(BubbleControls oldWidget) => false;
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.child});
  final Widget child;

  @override
  State<AuthPage> createState() => AuthPageState();
}

class AuthPageState extends State<AuthPage> {
  bool typing = false;
  int pending = 0;
  bool erroring = false;
  bool succeeding = false;
  Timer? _typingTimer, _errorTimer, _successTimer;

  BubbleMood get mood => erroring
      ? BubbleMood.error
      : pending > 0
      ? BubbleMood.submitting
      : succeeding
      ? BubbleMood.success
      : typing
      ? BubbleMood.typing
      : BubbleMood.idle;

  VoidCallback beginSubmit() {
    setState(() => pending++);
    var done = false;
    return () {
      if (done || !mounted) return;
      done = true;
      setState(() => pending--);
    };
  }

  void flashError() {
    _successTimer?.cancel();
    setState(() {
      succeeding = false;
      erroring = true;
    });
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => erroring = false);
    });
  }

  void flashSuccess() {
    _errorTimer?.cancel();
    setState(() {
      erroring = false;
      succeeding = true;
    });
    _successTimer?.cancel();
    _successTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => succeeding = false);
    });
  }

  void onInput() {
    if (!typing) setState(() => typing = true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) setState(() => typing = false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _errorTimer?.cancel();
    _successTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSignedOut());
  }

  void _maybeSignedOut() {
    final store = context.read<ClientStore>();
    if (store.sessionExpired && mounted) {
      store.sessionExpired = false;
      showSignedOutDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final store = context.watch<ClientStore>();
    final settings = context.watch<SettingsStore>();
    if (store.sessionExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSignedOut());
    }
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 900;
    final isCreate = GoRouterState.of(context).uri.path
        .contains('/login/create');
    final pad = (size.width * 0.025).clamp(18.0, 36.0);

    final content = _Content(
      isCreate: isCreate,
      wide: wide,
      mood: mood,
      onInput: onInput,
      settings: settings,
      child: widget.child,
    );

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: wide
            ? Padding(
                padding: EdgeInsets.all(size.width <= 980 ? 18 : pad),
                child: Row(
                  children: [
                    Expanded(
                      flex: size.width <= 980 ? 78 : 92,
                      child: const _Hero(),
                    ),
                    SizedBox(width: (size.width * 0.03).clamp(18.0, 48.0)),
                    Expanded(
                      flex: size.width <= 980 ? 122 : 108,
                      child: content,
                    ),
                  ],
                ),
              )
            : content,
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final radius = (size.width * 0.03).clamp(28.0, 48.0);
    final isMobile = defaultTargetPlatformIsMobile(context);
    final promo = kIsWebOrDesktop(context) && !isMobile;
    return ClipRRect(
      borderRadius: br(radius),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF33294B), Color(0xFF262038), Color(0xFF211B31)],
            stops: [0, .62, 1],
          ),
        ),
        padding: EdgeInsets.all((size.width * 0.04).clamp(32.0, 62.0)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wordmark(width: 148, color: Colors.white),
            if (promo) ...[
              SizedBox(height: (size.height * 0.05).clamp(28.0, 64.0)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Take your communities '),
                          TextSpan(
                            text: 'with you.',
                            style: const TextStyle(color: Color(0xFF08D3EF)),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        color: const Color(0xFFF8F6FF),
                        fontSize: (size.width * 0.026).clamp(30.4, 43.2),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.9,
                        height: 1.02,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Get DawnChat for desktop and keep up with your friends wherever you are.',
                      style: TextStyle(
                        color: const Color(0xFFF8F6FF).withValues(alpha: .72),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF8F6FF),
                        foregroundColor: const Color(0xFF211B31),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => openUrl(desktopDownloadUrl),
                      child: Text(
                        tr('Download for desktop'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      top: 8,
                      left: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: br(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .1),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x73000000),
                              blurRadius: 60,
                              offset: Offset(0, 24),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: br(14),
                          child: Image.asset(
                            'assets/promo/desktop-app.webp',
                            height: 520,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

bool defaultTargetPlatformIsMobile(BuildContext c) {
  final p = Theme.of(c).platform;
  return p == TargetPlatform.android || p == TargetPlatform.iOS;
}

bool kIsWebOrDesktop(BuildContext c) => !defaultTargetPlatformIsMobile(c);

class _Content extends StatelessWidget {
  const _Content({
    required this.isCreate,
    required this.wide,
    required this.mood,
    required this.onInput,
    required this.settings,
    required this.child,
  });

  final bool isCreate, wide;
  final BubbleMood mood;
  final VoidCallback onInput;
  final SettingsStore settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final w = MediaQuery.sizeOf(context).width;
    final hp = wide
        ? (w * 0.025).clamp(12.0, 42.0)
        : (w * 0.06).clamp(20.0, 44.0);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, wide ? 8 : 20, hp, 4),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: wide
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.spaceBetween,
              children: [
                if (!wide) Wordmark(width: w <= 460 ? 102 : 116),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wide)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            isCreate
                                ? 'Already have an account?'
                                : 'New to DawnChat?',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      Flexible(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: const StadiumBorder(),
                            side: BorderSide(color: cs.outlineVariant),
                            foregroundColor: cs.primary,
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 16 : 12,
                              vertical: wide ? 10 : 8,
                            ),
                          ),
                          onPressed: () => context.go(
                            context.href(
                              isCreate ? '/login/auth' : '/login/create',
                            ),
                          ),
                          child: Text(
                            isCreate ? 'Log in' : 'Create account',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: w <= 460 ? 12.5 : 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        tooltip: 'Toggle color theme',
                        onPressed: () =>
                            settings.mode = dark ? 'light' : 'dark',
                        icon: const Icon(Icons.dark_mode, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowBubble(mood: mood),
                      Listener(
                        onPointerUp: (_) {},
                        child: NotificationListener<Notification>(
                          onNotification: (_) {
                            onInput();
                            return false;
                          },
                          child: BubbleControls(
                            state: context
                                .findAncestorStateOfType<AuthPageState>()!,
                            child: child,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    for (final l in [
                      ('Terms', termsUrl),
                      ('Privacy', privacyUrl),
                      ('Help', supportUrl),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: InkWell(
                          onTap: () => openUrl(l.$2),
                          child: Text(
                            l.$1,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => openUrl(githubUrl),
                      icon: SvgPicture.asset(
                        'assets/auth/github.svg',
                        width: 20,
                        colorFilter: ColorFilter.mode(
                          cs.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: SvgPicture.asset(
                        'assets/auth/bluesky.svg',
                        width: 20,
                        colorFilter: ColorFilter.mode(
                          cs.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
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

class FlowBubble extends StatefulWidget {
  const FlowBubble({super.key, required this.mood});
  final BubbleMood mood;
  @override
  State<FlowBubble> createState() => _FlowBubbleState();
}

class _FlowBubbleState extends State<FlowBubble>
    with SingleTickerProviderStateMixin {
  static const _spacing = 11.0, _spinRadius = 8.0, _loopMs = 600000.0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600000),
  )..repeat();
  double _moodStart = 0;

  double get _now => _c.value * _loopMs;

  @override
  void didUpdateWidget(FlowBubble old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _moodStart = _now;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Per-dot motion mirroring the web client's idle float, typing pulse and loading ring.
  ({Offset offset, double opacity, double scale}) _dot(
    int i,
    BubbleMood mood,
    double now,
  ) {
    double phase(double period, double stagger) =>
        ((((now - i * stagger) % period) + period) % period) / period;
    final entry = ((now - (80 + i * 120)) / 420).clamp(0.0, 1.0);
    final scale = Curves.easeOutBack.transform(entry);
    switch (mood) {
      case BubbleMood.idle:
        final p = phase(1600, 240);
        return (
          offset: Offset(0, -3 * (0.5 - 0.5 * math.cos(2 * math.pi * p))),
          opacity: 1,
          scale: scale,
        );
      case BubbleMood.typing:
        final p = phase(1200, 200);
        final o = p < .4 ? .3 + .7 * (p / .4) : 1 - .7 * ((p - .4) / .6);
        return (offset: Offset.zero, opacity: o, scale: scale);
      case BubbleMood.submitting:
        final p = phase(900, 0);
        final angle = 2 * math.pi * (p + (i - 1) / 3) - math.pi / 2;
        return (
          offset: Offset(
            (1 - i) * _spacing + _spinRadius * math.cos(angle),
            _spinRadius * math.sin(angle),
          ),
          opacity: 1,
          scale: 1,
        );
      case BubbleMood.success:
        return (offset: Offset((1 - i) * _spacing, 0), opacity: 0, scale: 1);
      case BubbleMood.error:
        return (offset: Offset.zero, opacity: 1, scale: 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final mood = widget.mood;
    final bg = switch (mood) {
      BubbleMood.error => cs.errorContainer,
      BubbleMood.success => cs.primaryContainer,
      _ => cs.secondaryContainer,
    };
    final dot = mood == BubbleMood.error
        ? cs.onErrorContainer
        : cs.onSecondaryContainer;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final now = _now;
        var shake = 0.0;
        if (mood == BubbleMood.error) {
          final u = ((now - _moodStart) / 450).clamp(0.0, 1.0);
          shake = 6 * math.sin(2 * math.pi * 3 * u) * (1 - u);
        }
        return Transform.translate(
          offset: Offset(shake, 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            width: 62,
            height: 50,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(5),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Builder(
                        builder: (_) {
                          final d = _dot(i, mood, now);
                          return Transform.translate(
                            offset: d.offset,
                            child: Opacity(
                              opacity: d.opacity.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: d.scale,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2.5,
                                  ),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: dot,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                AnimatedOpacity(
                  duration: Duration(
                    milliseconds: mood == BubbleMood.success ? 200 : 150,
                  ),
                  opacity: mood == BubbleMood.success ? 1 : 0,
                  child: Icon(
                    Icons.check,
                    color: cs.onPrimaryContainer,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Heading used at the top of each flow.
class FlowTitle extends StatelessWidget {
  const FlowTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: w <= 460 ? 32 : (w * 0.03).clamp(32.0, 43.2),
              fontWeight: FontWeight.w700,
              letterSpacing: -1.6,
              height: 1.08,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Text(
                  subtitle!,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
