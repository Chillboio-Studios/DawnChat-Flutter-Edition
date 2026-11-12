# Platform Parity Audit — DawnChat-Flutter-Edition

Comparison of the Flutter app (`project/`, ~25k LOC in `lib/`) against:

- **Android**: `DawnChat-For-Android/` — Kotlin/Compose, ~339 files
- **Web/Desktop**: `DawnChat-For-Web/` (SolidJS client) + `Dawnchat-For-DESKTOP/` (Electron shell)

Goal: identify desktop- and mobile-specific features that still need porting.
The Flutter app already covers the bulk of *cross-platform* features; this
document focuses on what is genuinely platform-specific.

---

## Already ported (do not re-do)

- **Desktop shell**: custom titlebar (`Titlebar`), tray icon + menu,
  close-to-tray, launch-at-startup, minimise-to-tray, GitHub-release updater
  (`DesktopUpdater`), window min-size, Sentry (`sentry_flutter`).
- **Voice**: LiveKit voice manager — mute/deafen/camera/screenshare, call
  card, PiP overlay, layouts, ringtones for DM/group calls.
- **Messaging**: markdown, embeds (YouTube/Twitch/Spotify/GIF providers),
  GIF picker (Klipy + Gifbox), emoji picker, replies (up to 5), per-channel
  drafts, editing, pins, member/search/pins sidebars, slowmode, age + geo
  gate (`_AgeGate` in `channel_page.dart`).
- **Navigation (wide layouts)**: server rail with folders + drag/drop,
  home sidebar (DMs/friends/saved notes), server sidebar with categories,
  context menus (message/user/server/channel/notification), unread + mention
  badges, `/i/:host` multi-instance routing.
- **Settings**: account/MFA/sessions/bots/feedback/voice/appearance/
  notifications/language/native(desktop)/advanced, cross-device settings
  sync infrastructure (`syncKeys` in `settings_store.dart`).
- **Push**: FCM + web push + local desktop notifications.
- **Misc**: admin panel, discover, friends, invites, changelog dialog,
  policy-change review dialog, i18n + RTL, report dialogs.

---

## Mobile gaps (Android parity)

### A. Navigation & information architecture — highest priority

The Android app (`MainActivity.kt` + `MainScreen.kt` + `ChatRouterScreen.kt`)
uses a real mobile navigation model that the Flutter app lacks:

1. **Bottom tab bar** — `MainScreen` has 3 tabs: *Communities* (server list),
   *Conversations* (friends/DMs/saved notes), *Overview* (home). Flutter
   phone UI is a single `Drawer` containing rail + sidebar, closed on every
   navigation (`interface_shell.dart:356`).

2. **Server → channel list screen** — tapping a server icon navigates to
   `main/server/{serverId}` → `ServerChannelsScreen.kt`: a full-screen
   channel list with:
   - top app bar: back button, server name + official/verified flags,
     overflow menu (`ServerContextSheet`)
   - banner image, uncategorised channels, **collapsible categories**
     (state persisted per server via `rememberSaveable`)
   - long-press → `ChannelContextSheet` bottom sheet
   - voice channels open the voice sheet instead of navigating
   Flutter equivalent: `/server/:server` (`ServerHome` in `home_page.dart:737`)
   just redirects to the first text channel — the list is never shown.

3. **Back-stack behaviour** — Android conversation route
   (`main/conversation/{channelId}`) pushes `ChannelScreen` with
   `useBackButton`/`popBackStack`, so Back returns to the channel list.
   System back toggles the drawer (`BackHandler` in `ChatRouterScreen.kt:1100`).
   Flutter phone layout has no per-screen app bars or back navigation.

4. **`NoCurrentChannel` / `Overview` / `Friends` destinations** — Android has
   dedicated screens for "server selected but no channel", the overview feed,
   and friends, each with drawer/menu affordances. Flutter has `/app`,
   `/friends`, `/server/:id` routes but no mobile chrome around them.

5. **Tablet-aware UI** — Android switches to drawer-based UI when
   `widthSizeClass == Expanded && heightSizeClass != Compact`
   (`ChatRouterScreen.kt:479`). Flutter `ScreenClass` has phone/tablet/desktop
   but `interface_shell.dart` only special-cases phone; tablet gets the full
   desktop rail+sidebar layout.

### B. Gestures & sheet-based UX

6. **Swipe-to-reply** — `SwipeToReplySpark.kt` + `SwipeToReplySparkSheet.kt`
   (gesture + one-time onboarding hint). No swipe handling in Flutter
   (`grep swipe` → 0 hits in `lib/`).

7. **Bottom-sheet pattern on phone** — Android presents *all* secondary UI
   as `ModalBottomSheet`s: `ServerContextSheet`, `ChannelContextSheet`,
   `MemberContextSheet`, `MessageContextSheet`, `ReactionInfoSheet`,
   `ReactSheet`, `UserCardSheet`, `UserInfoSheet`, `StatusSheet`,
   `LinkInfoSheet`, `EmoteInfoSheet`, `MemberListSheet`, `WebHookUserSheet`,
   `ServerFolderSheet`/`ServerFolderPickerSheet`, `ColourPickerSheet`,
   `AddServerSheet`, `ChangelogSheet`, `EarlyAccessSheet`,
   `ServerIdentityOptionsSheet`.
   Flutter uses `AlertDialog`/`showModalBottomSheet`/context menus
   inconsistently; several sheets have no Flutter equivalent at all (see C/D).

8. **Catch-up deck** — `CatchUpScreen.kt`: swipeable cards through unread
   channels ("catch up on messages"). No Flutter equivalent.

### C. Mobile media, calls & sharing

9. **Share target** — `ShareTargetActivity.kt` + manifest `SEND`/
   `SEND_MULTIPLE` intent filters let users share text/links/media into a
   channel. Flutter `AndroidManifest.xml` has no share intent-filter.

10. **Voice messages** — `AndroidVoiceRecorder.kt`, `VoiceMessagePlayer.kt`,
    mic button in `MessageField.kt`: record, send, and play voice-message
    attachments. Flutter has no voice-message support (web doesn't either —
    Android-only feature).

11. **Ongoing call UX** — `OngoingCallService.kt` (foreground service +
    notification), `IncomingActivity.kt` (full-screen incoming-call intent),
    `VoiceCallBanner.kt`, `VoiceFloatingPip.kt`. Flutter has in-app ringing +
    `VoiceOverlay` PiP, but no Android foreground service/notification for
    calls and no full-screen incoming-call UI.

12. **Android 14 permission switches** — `VoicePermissionSwitch.kt` (mic/cam
    toggles for the new partial-access permissions). N/A check needed for
    Flutter voice plugin permissions.

13. **Fullscreen media viewers** — `ImageViewActivity.kt`,
    `VideoViewActivity.kt`. Flutter has a zoomable image viewer in
    `embeds.dart:340`; verify video fullscreen parity.

### D. Mobile settings & misc screens

14. **Experiments / Labs / Debug** — `ExperimentsSettingsScreen.kt`,
    `DebugSettingsScreen.kt`, `LabsHomeScreen.kt` (+ sandboxes). Flutter has
    an `AdvancedPage`; verify which toggles exist (feature flags in
    `FeatureFlags.kt`/`Experiments.kt`).

15. **Onboarding sheets** — `EarlyAccessSheet.kt`, `ChangelogSheet.kt`,
    `NotificationRationaleDialog.kt` (push-permission rationale),
    platform-moderation-DM hint (`ChatRouterScreen.kt:585`). Flutter shows a
    changelog dialog but likely lacks the others.

16. **Server identity settings** — `ServerIdentitySettingsScreen.kt` +
    `ServerIdentityOptionsSheet.kt`. Check `server_settings.dart` coverage.

17. **Remaining info sheets** — `LinkInfoSheet` (link preview on tap),
    `EmoteInfoSheet`, `ReactionInfoSheet`, `MemberListSheet`,
    `WebHookUserSheet`, `UserCardSheet`, `UserMutualsTile`. Flutter has
    `profile.dart` and context menus; these specific surfaces are partial or
    missing.

18. **Auth/onboarding flow** — Android has dedicated `LoginGreetingScreen`,
    `MfaScreen`, `AccountRecoveryScreens`, `OnboardingScreen`, register
    screens. Flutter `flows.dart` covers login/MFA/reset/create; verify
    greeting/onboarding parity (low priority — functional parity exists).

---

## Desktop / web gaps

### E. Keyboard & input

1. **Keybind system** — web client has a full keybind layer
   (`components/keybinds/`): navigate channel/server up/down, jump to end,
   mark server read, focus composer, remove composition element, cancel
   editing, close modal/floating/sidebar — with configurable sequences and
   priority. Flutter has only Escape→dismiss (`app.dart:99`,
   `channel_page.dart:174`). **Biggest desktop gap.**

2. **`TextEditor2` (CodeMirror)** — web composer is a CodeMirror editor with
   markdown marks, widgets, autocomplete sources, line wrap. Flutter composer
   is a `TextField` with a custom autocomplete popup — functional but lacks
   rich-text marks/preview affordances.

### F. Desktop-native features (Electron → Flutter)

3. **Unread count badges** — `Dawnchat-For-DESKTOP/src/native/badges.ts`:
   overlay icon on Windows/Linux taskbar + Unity/dock badge on Linux.
   Flutter has no equivalent (would need `window_manager`/`tray_manager`
   APIs or platform channels).

4. **Discord Rich Presence** — `native/discordRpc.ts`; the Flutter settings
   UI already exposes a "Discord RPC" toggle (`settings_pages.dart:1708`)
   but **nothing implements it**.

5. **Virtual microphone** — `native/virtualMic.ts` (virtual audio device for
   voice). Not present in Flutter.

6. **Single-instance enforcement** — Electron `app.on('second-instance')`
   focuses the existing window (`main.ts:83`). Flutter desktop has no
   single-instance lock.

7. **Native context menu** — Electron `contents.on('context-menu')` provides
   edit-role menu (window.ts:191). Flutter desktop uses Flutter's own
   context menus — mostly covered by app menus; verify text-field edit menu.

8. **macOS titlebar details** — Electron positions traffic lights at (8,8)
   with hidden titlebar; Flutter `Titlebar`/`customFrame` covers Windows/
   Linux — verify macOS traffic-light inset.

### G. Web-client features possibly missing in Flutter

9. **Unread mention callout** — `UnreadCallout.tsx`: floating pill showing
   unread/mention counts when scrolling (`features/navigation/`). Flutter
   `message_list.dart` has unread dividers + jump-to-bottom but no
   directional unread callout.

10. **Draft list UI** — web shows per-channel drafts
    (`DraftMessages.tsx`, `DraftMessageContextMenu.tsx`). Flutter
    `DraftStore` persists draft text but nothing lists drafts in the UI.

11. **Message caching / large-server optimisations** —
    `MessageCache.tsx`, `largeServer.ts`. Check Flutter `message_list.dart`
    pagination performance on large channels.

12. **Floating user card** — `components/ui/components/floating/UserCard.tsx`
    (hover card). Flutter opens profile on click; hover preview likely
    missing (minor).

13. **Custom CSS theme** — web theme settings support custom CSS
    (`ui/themes/`). Flutter uses generated Material theme tokens — custom
    CSS is not portable; decide whether to support an equivalent
    (custom theme JSON?) or drop.

14. **PWA/service worker** — web-only; Flutter web has `web_push.dart`.
    N/A unless Flutter web needs install prompt.

---

## Suggested port order

1. **Mobile navigation rework** (A1–A5): bottom tabs or drawer→channel-list
   stack so tapping a server shows channels — the user's headline issue.
   Includes `ServerChannelsScreen` port (collapsible categories, banner,
   app bar, back nav).
2. **Phone sheet UX** (B7 + D17): convert dialogs/context menus to
   bottom sheets on `ScreenClass.phone`; add missing info sheets.
3. **Gestures** (B6, B8): swipe-to-reply + catch-up deck.
4. **Mobile platform features** (C9–C12): share target, voice messages,
   call service/notification.
5. **Desktop parity** (E1, F3–F6): keybinds, badges, Discord RPC impl,
   virtual mic, single-instance.
6. **Polish** (G9–G13): unread callout, drafts UI, hover card, perf.

---

## Ported (first pass)

- **Mobile navigation (A1–A5)** — new `ServerChannelsScreen`
  (`project/lib/src/ui/interface/server_channels_screen.dart`) at
  `/server/:serverId/channels`: app bar with back + server actions,
  banner, uncategorized channels, collapsible categories, channel context
  menus. Phone server-rail taps route there; channel page has a phone
  back button; `/server/:id` no longer force-redirects on phone.
- **Phone sheet UX (partial B7)** — `showContextMenu` renders as a
  modal bottom sheet on `ScreenClass.phone` with stacked sub-sheets,
  covering message/user/server/channel/category menus at once.
- **Gestures (partial)** — swipe-right-to-reply on message tiles on
  phones via `Dismissible` (replies through `DraftStore`).
- **Keybinds (partial F3)** — Alt+↑/↓ cycles text channels, Ctrl+Alt+↑/↓
  cycles servers (matches web `NAVIGATION_CHANNEL/SERVER_UP/DOWN`).
- **Deep links** — Android manifest intent filters for
  `chat.dawn-chat.com` / `app.dawn-chat.com` (`/channel/...`,
  `/server/...`, `/login/reset|verify`, `/verify`, `/delete`) plus
  `app_links` handling and a `/dc/:code` invite shortlink route.
- **Android fixes since `a390f30`** — blank-URL guard in `NetImage` /
  `NetSvg` / `netImageProvider` (RemoteImage fix), login response
  hardening for 2xx error-shaped bodies. GIF picker + standalone-GIF
  rendering were already present. `network_security_config.xml` not
  ported — Dart `HttpClient` doesn't use it (native Coil/Glide only).

## Still open

- Bottom tabs (Communities/Conversations/Overview), catch-up deck,
  voice messages, share-target activity, call foreground service /
  incoming-call UI, PiP polish.
- Discord RPC implementation (settings toggle exists, no backend),
  taskbar unread badges, virtual mic, single-instance lock.
- Remaining web polish: unread jump callout, drafts list UI, hover
  user card, custom theme CSS.

## Ported (second pass — voice & calls)

- **Voice messages** — `record` 7.1.2 (pinned; 7.2.0 was <1 day old).
  `lib/src/media/voice_recorder.dart` records mono 44.1kHz AAC/M4A with
  amplitude sampling → 64-bucket sqrt-scaled waveform, same
  `chat.stoat.VoiceMessage` content JSON as Android (1s min, 15min max,
  auto-send at cap). Composer mic button swaps to a recording bar
  (timer/cancel/send). `VoiceMessageView` renders waveform + progress +
  playback via media_kit; Android-sent voice messages render too.
- **Ongoing-call foreground service** — `CallService.kt` (CallStyle
  notification, chronometer, mute + hang-up actions,
  `phoneCall|microphone` FGS type) + `dawnchat/call_service` MethodChannel
  and `dawnchat/call_events` EventChannel wired through `MainActivity`,
  `lib/src/call/call_service.dart`, and `VoiceManager` (start on
  connect, stop on disconnect, mic-state sync, hang-up/mute handling).
  Telecom `CallsManager` integration intentionally skipped (would need
  an androidx.core bump; MANAGE_OWN_CALLS declared for later).
- **Incoming-call UI** — `VoiceCallUpdate` gateway events now drive
  `PushService.incomingCall` + `IncomingCallOverlay` (caller avatar,
  name, decline/accept → join DM call), ringtone loop, 45s timeout,
  clears on `ended`. Works on all platforms, not just Android.

## Verification status

- `flutter analyze` clean; `flutter test` 27/27 pass.
- Kotlin service NOT compile-verified — no Android SDK on this machine
  (`ANDROID_HOME` unset). Needs `flutter build apk` on a machine with
  the SDK before release.
