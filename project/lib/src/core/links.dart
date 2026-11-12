const playStoreUrl = '#';
const desktopDownloadUrl =
    'https://github.com/Chillboio-Studios/DawnChat-Flutter-Edition/releases/latest';
const roadmapUrl = '#';
const feedbackUrl =
    'https://github.com/Chillboio-Studios/DawnChat-Flutter-Edition/issues';
const bugTrackerUrl =
    'https://github.com/Chillboio-Studios/DawnChat-Flutter-Edition/issues';
const githubUrl = 'https://github.com/Chillboio-Studios';
const donationUrl = 'https://www.chillboiostudios.com/donate';
const sourceCodeUrl = 'https://github.com/Chillboio-Studios';

const loungeServerId = '01M3615E99PYEQZ26AQ9RV6WJG';

const dawnchatHost = 'chat.dawn-chat.com';
const dawnchatApiHost = 'api.dawn-chat.com';
const dawnchatApiUrl = 'https://$dawnchatApiHost';
const dawnchatChatUrl = 'https://chat.dawn-chat.com';
const dawnchatAppUrl = 'https://app.dawn-chat.com';
const dawnchatOfficialHosts = <String>[
  dawnchatHost,
  'https://csinvite.net',
  dawnchatApiHost,
  'chat.dawn-chat.com',
  'app.dawn-chat.com',
  'beta.dawn-chat.com',
];

const statusUrl = 'https://status.dawn-chat.com';
const supportUrl = 'https://support.chillboiostudios.com';
const termsUrl = 'https://www.chillboiostudios.com/terms';
const privacyUrl = 'https://www.chillboiostudios.com/terms';
const acceptableUseUrl = 'https://www.chillboiostudios.com/terms';
const translationsUrl = 'https://translate.stoat.chat/projects/revolt/';
const changelogUrl =
    'https://git.chillboiostudios.com/Chillboio-Studios/DawnChat-Static-Files/raw/branch/main/changelog.json';

const gifboxUrl = 'https://gifbox.dawn-chat.com';
const gifProviderOrigins = [
  'https://tenor.com',
  'https://giphy.com',
  'https://gifbox.me',
  'https://klipy.com',
  'https://static.klipy.com',
  'https://static1.klipy.com',
  'https://static2.klipy.com',
];
const gifboxOrigin = 'https://gifbox.me';
const klipyUrl = 'https://klipy.com';
const klipyApiBaseUrl = 'https://api.klipy.com/api/v1';
const inviteShortenerUrl = 'https://csinvite.net/dc/';
const discoverUrl = 'https://csinvite.net';

const unicodeEmojiBaseUrl = 'https://static.stoat.chat/emoji';
const customEmojiBaseUrl = 'https://autumn.dawn-chat.com/emojis';


/// CI-injected label for non-release builds (`BE-<sha>` on bleeding edge,
/// `pr-<id>` on pull requests). Empty on release builds — show the real
/// package version then.
const appVersionLabel = String.fromEnvironment('APP_VERSION_LABEL');

String normalizeHost(String host) =>
    dawnchatOfficialHosts.contains(host) ? dawnchatHost : host;

const gifboxInfoUrl = 'https://gifbox.me/';
const gifboxUploadUrl = 'https://gifbox.me/upload';
