import 'package:kazumi/services/player/syncplay_endpoint.dart';

enum SettingGroup {
  player,
  danmaku,
  theme,
  interface,
  proxy,
  webdav,
  download,
  bangumi,
  collect,
  sync,
  update,
  misc,
  magnet,
  media,
}

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

// Add new settings here. SettingsKeys is the public typed registry used by
// callers; new keys can use literal string names directly.
class SettingsKeys {
  static const hAenable = SettingKey<bool>(
    _SettingBoxKey.hAenable,
    true,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    _SettingBoxKey.hardwareDecoder,
    'auto-safe',
    group: SettingGroup.player,
  );
  static const searchEnhanceEnable = SettingKey<bool>(
    _SettingBoxKey.searchEnhanceEnable,
    true,
    group: SettingGroup.misc,
  );
  static const autoUpdate = SettingKey<bool>(
    _SettingBoxKey.autoUpdate,
    true,
    group: SettingGroup.update,
  );
  static const checkPluginUpdateOnStartup = SettingKey<bool>(
    'checkPluginUpdateOnStartup',
    true,
    group: SettingGroup.update,
  );
  static const alwaysOntop = SettingKey<bool>(
    _SettingBoxKey.alwaysOntop,
    false,
    group: SettingGroup.misc,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultPlaySpeed,
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    _SettingBoxKey.defaultShortcutForwardPlaySpeed,
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    _SettingBoxKey.defaultAspectRatioType,
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    _SettingBoxKey.buttonSkipTime,
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    _SettingBoxKey.arrowKeySkipTime,
    10,
    group: SettingGroup.player,
  );
  static const danmakuEnhance = SettingKey<bool>(
    _SettingBoxKey.danmakuEnhance,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorder = SettingKey<bool>(
    _SettingBoxKey.danmakuBorder,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBorderSize = SettingKey<double>(
    _SettingBoxKey.danmakuBorderSize,
    1.5,
    group: SettingGroup.danmaku,
  );
  static const danmakuOpacity = SettingKey<double>(
    _SettingBoxKey.danmakuOpacity,
    1.0,
    group: SettingGroup.danmaku,
  );
  static final danmakuFontSize = SettingKey<double>(
    _SettingBoxKey.danmakuFontSize,
    25.0,
    group: SettingGroup.danmaku,
    defaultResolver: (context) => context.compactLayout ? 16.0 : 25.0,
  );
  static const danmakuTop = SettingKey<bool>(
    _SettingBoxKey.danmakuTop,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuScroll = SettingKey<bool>(
    _SettingBoxKey.danmakuScroll,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuBottom = SettingKey<bool>(
    _SettingBoxKey.danmakuBottom,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuMassive = SettingKey<bool>(
    _SettingBoxKey.danmakuMassive,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuDeduplication = SettingKey<bool>(
    _SettingBoxKey.danmakuDeduplication,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuArea = SettingKey<double>(
    _SettingBoxKey.danmakuArea,
    1.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuColor = SettingKey<bool>(
    _SettingBoxKey.danmakuColor,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDuration = SettingKey<double>(
    _SettingBoxKey.danmakuDuration,
    8.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuLineHeight = SettingKey<double>(
    _SettingBoxKey.danmakuLineHeight,
    1.6,
    group: SettingGroup.danmaku,
  );
  static const danmakuTimeOffset = SettingKey<double>(
    _SettingBoxKey.danmakuTimeOffset,
    0.0,
    group: SettingGroup.danmaku,
  );
  static const danmakuEnabledByDefault = SettingKey<bool>(
    _SettingBoxKey.danmakuEnabledByDefault,
    false,
    group: SettingGroup.danmaku,
  );
  static const danmakuBiliBiliSource = SettingKey<bool>(
    _SettingBoxKey.danmakuBiliBiliSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuGamerSource = SettingKey<bool>(
    _SettingBoxKey.danmakuGamerSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuDanDanSource = SettingKey<bool>(
    _SettingBoxKey.danmakuDanDanSource,
    true,
    group: SettingGroup.danmaku,
  );
  static const danmakuFontWeight = SettingKey<int>(
    _SettingBoxKey.danmakuFontWeight,
    4,
    group: SettingGroup.danmaku,
  );
  static const danmakuFollowSpeed = SettingKey<bool>(
    _SettingBoxKey.danmakuFollowSpeed,
    true,
    group: SettingGroup.danmaku,
  );
  static const themeMode = SettingKey<String>(
    _SettingBoxKey.themeMode,
    'system',
    group: SettingGroup.theme,
  );
  static const themeColor = SettingKey<String>(
    _SettingBoxKey.themeColor,
    'default',
    group: SettingGroup.theme,
  );
  static const privateMode = SettingKey<bool>(
    _SettingBoxKey.privateMode,
    false,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    _SettingBoxKey.autoPlay,
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    _SettingBoxKey.autoPlayNext,
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    _SettingBoxKey.playResume,
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    _SettingBoxKey.showPlayerError,
    true,
    group: SettingGroup.player,
  );
  static const oledEnhance = SettingKey<bool>(
    _SettingBoxKey.oledEnhance,
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    _SettingBoxKey.displayMode,
    null,
    group: SettingGroup.interface,
  );
  static const enableGitProxy = SettingKey<bool>(
    _SettingBoxKey.enableGitProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableBangumiProxy = SettingKey<bool>(
    _SettingBoxKey.enableBangumiProxy,
    true,
    group: SettingGroup.proxy,
  );
  static const enableSystemProxy = SettingKey<bool>(
    _SettingBoxKey.enableSystemProxy,
    false,
    group: SettingGroup.proxy,
  );
  static const defaultStartupPage = SettingKey<String>(
    _SettingBoxKey.defaultStartupPage,
    '/tab/popular/',
    group: SettingGroup.interface,
  );
  static const isWideScreen = SettingKey<bool>(
    _SettingBoxKey.isWideScreen,
    false,
    group: SettingGroup.interface,
  );
  static const webDavEnable = SettingKey<bool>(
    _SettingBoxKey.webDavEnable,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableHistory = SettingKey<bool>(
    _SettingBoxKey.webDavEnableHistory,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavEnableCollect = SettingKey<bool>(
    _SettingBoxKey.webDavEnableCollect,
    false,
    group: SettingGroup.webdav,
  );
  static const webDavURL = SettingKey<String>(
    _SettingBoxKey.webDavURL,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavUsername = SettingKey<String>(
    _SettingBoxKey.webDavUsername,
    '',
    group: SettingGroup.webdav,
  );
  static const webDavPassword = SettingKey<String>(
    _SettingBoxKey.webDavPassword,
    '',
    group: SettingGroup.webdav,
  );
  static const lowMemoryMode = SettingKey<bool>(
    _SettingBoxKey.lowMemoryMode,
    false,
    group: SettingGroup.player,
  );
  static const showWindowButton = SettingKey<bool>(
    _SettingBoxKey.showWindowButton,
    false,
    group: SettingGroup.theme,
  );
  static const useDynamicColor = SettingKey<bool>(
    _SettingBoxKey.useDynamicColor,
    false,
    group: SettingGroup.theme,
  );
  static const exitBehavior = SettingKey<int>(
    _SettingBoxKey.exitBehavior,
    2,
    group: SettingGroup.interface,
  );
  static const playerDebugMode = SettingKey<bool>(
    _SettingBoxKey.playerDebugMode,
    false,
    group: SettingGroup.player,
  );
  static const syncPlayEndPoint = SettingKey<String>(
    _SettingBoxKey.syncPlayEndPoint,
    defaultSyncPlayEndPoint,
    group: SettingGroup.player,
  );
  static const syncPlayUserName = SettingKey<String>(
    'syncPlayUserName',
    '',
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    _SettingBoxKey.androidEnableOpenSLES,
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    _SettingBoxKey.androidVideoRenderer,
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    _SettingBoxKey.androidAutoEnterPIP,
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    _SettingBoxKey.defaultSuperResolutionMode,
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    _SettingBoxKey.disableSuperResolutionWarning,
    false,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    _SettingBoxKey.playerDisableAnimations,
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    _SettingBoxKey.playerLogLevel,
    2,
    group: SettingGroup.player,
  );
  static const timelineNotShowAbandonedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowAbandonedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineNotShowWatchedBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineNotShowWatchedBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const timelineOnlyShowWatchingBangumis = SettingKey<bool>(
    _SettingBoxKey.timelineOnlyShowWatchingBangumis,
    false,
    group: SettingGroup.collect,
  );
  static const useSystemFont = SettingKey<bool>(
    _SettingBoxKey.useSystemFont,
    false,
    group: SettingGroup.theme,
  );
  static const forceAdBlocker = SettingKey<bool>(
    _SettingBoxKey.forceAdBlocker,
    false,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    _SettingBoxKey.backgroundPlayback,
    false,
    group: SettingGroup.player,
  );
  static const proxyEnable = SettingKey<bool>(
    _SettingBoxKey.proxyEnable,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyConfigured = SettingKey<bool>(
    _SettingBoxKey.proxyConfigured,
    false,
    group: SettingGroup.proxy,
  );
  static const proxyUrl = SettingKey<String>(
    _SettingBoxKey.proxyUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const proxyTestUrl = SettingKey<String>(
    _SettingBoxKey.proxyTestUrl,
    '',
    group: SettingGroup.proxy,
  );
  static const showRating = SettingKey<bool>(
    _SettingBoxKey.showRating,
    true,
    group: SettingGroup.interface,
  );
  static const showAnimeCounter = SettingKey<bool>(
    _SettingBoxKey.showAnimeCounter,
    false,
    group: SettingGroup.interface,
  );
  static const downloadParallelEpisodes = SettingKey<int>(
    _SettingBoxKey.downloadParallelEpisodes,
    2,
    group: SettingGroup.download,
  );
  static const downloadParallelSegments = SettingKey<int>(
    _SettingBoxKey.downloadParallelSegments,
    3,
    group: SettingGroup.download,
  );
  static const downloadDanmaku = SettingKey<bool>(
    _SettingBoxKey.downloadDanmaku,
    true,
    group: SettingGroup.download,
  );
  static const downloadDirectory = SettingKey<String>(
    _SettingBoxKey.downloadDirectory,
    '',
    group: SettingGroup.download,
  );
  // macOS only: security-scoped bookmark that keeps downloadDirectory
  // writable across app restarts under the sandbox.
  static const downloadDirectoryBookmark = SettingKey<String>(
    'downloadDirectoryBookmark',
    '',
    group: SettingGroup.download,
  );
  static const shortcutDialogShown = SettingKey<bool>(
    _SettingBoxKey.shortcutDialogShown,
    false,
    group: SettingGroup.misc,
  );
  static const bangumiSyncEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiSyncEnable,
    false,
    group: SettingGroup.bangumi,
  );
  static const bangumiAccessToken = SettingKey<String>(
    _SettingBoxKey.bangumiAccessToken,
    '',
    group: SettingGroup.bangumi,
  );
  static const bangumiSyncPriority = SettingKey<int>(
    _SettingBoxKey.bangumiSyncPriority,
    0,
    group: SettingGroup.bangumi,
  );
  static const bangumiImmediateSyncToastEnable = SettingKey<bool>(
    _SettingBoxKey.bangumiImmediateSyncToastEnable,
    true,
    group: SettingGroup.bangumi,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    _SettingBoxKey.brightnessVolumeGesture,
    true,
    group: SettingGroup.player,
  );
  static const historySyncDeviceId = SettingKey<String>(
    _SettingBoxKey.historySyncDeviceId,
    '',
    group: SettingGroup.sync,
  );
  static const historySyncSequence = SettingKey<int>(
    _SettingBoxKey.historySyncSequence,
    0,
    group: SettingGroup.sync,
  );
  static const historySyncSnapshotInitialized = SettingKey<bool>(
    _SettingBoxKey.historySyncSnapshotInitialized,
    false,
    group: SettingGroup.sync,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );

  // 磁力搜索 / 下载 / RSS 订阅相关设置
  static const mikanBaseUrl = SettingKey<String>(
    'mikanBaseUrl',
    'https://mikanani.me',
    group: SettingGroup.magnet,
  );
  /// 启用的搜索源 id 列表，逗号分隔；为空时使用全部内置源。
  static const magnetSearchSources = SettingKey<String>(
    'magnetSearchSources',
    '',
    group: SettingGroup.magnet,
  );
  /// 默认搜索源 id（单选）。
  static const magnetDefaultSource = SettingKey<String>(
    'magnetDefaultSource',
    'mikan',
    group: SettingGroup.magnet,
  );
  /// Animes Garden 搜索条件：字幕组名称（可空）。
  static const animesGardenFansub = SettingKey<String>(
    'animesGardenFansub',
    '',
    group: SettingGroup.magnet,
  );
  /// Animes Garden 搜索条件：资源类型（可空，如 动画 / 合集 / 音乐）。
  static const animesGardenType = SettingKey<String>(
    'animesGardenType',
    '',
    group: SettingGroup.magnet,
  );
  static const magnetAria2Enable = SettingKey<bool>(
    'magnetAria2Enable',
    false,
    group: SettingGroup.magnet,
  );
  static const magnetAria2RpcUrl = SettingKey<String>(
    'magnetAria2RpcUrl',
    'http://localhost:6800/jsonrpc',
    group: SettingGroup.magnet,
  );
  static const magnetAria2Secret = SettingKey<String>(
    'magnetAria2Secret',
    '',
    group: SettingGroup.magnet,
  );
  static const magnetSubscriptions = SettingKey<String>(
    'magnetSubscriptions',
    '[]',
    group: SettingGroup.magnet,
  );
  static const magnetDownloadEntries = SettingKey<String>(
    'magnetDownloadEntries',
    '[]',
    group: SettingGroup.magnet,
  );

  // ---------- 内置磁力引擎（Windows） ----------
  /// 引擎模式：builtin（内置 Aria2，随应用启动/停止） | remote（连接外部 Aria2 RPC）。
  static const magnetEngineMode = SettingKey<String>(
    'magnetEngineMode',
    'builtin',
    group: SettingGroup.magnet,
  );
  /// 内置 aria2c 可执行文件路径，留空则自动查找（应用目录、PATH）。
  static const aria2ExecutablePath = SettingKey<String>(
    'aria2ExecutablePath',
    '',
    group: SettingGroup.magnet,
  );
  /// 内置引擎 RPC 监听端口，0 表示自动选择。
  static const aria2RpcPort = SettingKey<int>(
    'aria2RpcPort',
    0,
    group: SettingGroup.magnet,
  );
  /// 默认下载目录，留空使用系统“下载”目录。
  static const aria2DownloadDir = SettingKey<String>(
    'aria2DownloadDir',
    '',
    group: SettingGroup.magnet,
  );
  /// 最大并发下载任务数。
  static const aria2MaxConcurrentDownloads = SettingKey<int>(
    'aria2MaxConcurrentDownloads',
    5,
    group: SettingGroup.magnet,
  );
  /// BitTorrent 与 DHT 的 TCP/UDP 监听端口，0 表示自动。
  static const aria2ListenPort = SettingKey<int>(
    'aria2ListenPort',
    6881,
    group: SettingGroup.magnet,
  );
  /// 单个任务最大对等节点数，0 表示不限。
  static const aria2MaxPeers = SettingKey<int>(
    'aria2MaxPeers',
    60,
    group: SettingGroup.magnet,
  );
  /// 全局最大上传速度（KiB/s），0 表示不限。
  static const aria2MaxUploadLimitKb = SettingKey<int>(
    'aria2MaxUploadLimitKb',
    0,
    group: SettingGroup.magnet,
  );
  /// 是否启用 IPv4 DHT。
  static const aria2EnableDht = SettingKey<bool>(
    'aria2EnableDht',
    true,
    group: SettingGroup.magnet,
  );
  /// 是否启用 IPv6 DHT。
  static const aria2EnableDht6 = SettingKey<bool>(
    'aria2EnableDht6',
    true,
    group: SettingGroup.magnet,
  );
  /// 是否启用 UPnP 端口映射。
  static const aria2EnableUpnp = SettingKey<bool>(
    'aria2EnableUpnp',
    true,
    group: SettingGroup.magnet,
  );
  /// 是否启用 NAT-PMP 端口映射。
  static const aria2EnableNatPmp = SettingKey<bool>(
    'aria2EnableNatPmp',
    true,
    group: SettingGroup.magnet,
  );
  /// 做种时间（分钟）。0 表示下载完成后立即停止做种；-1 表示不限时。
  static const aria2SeedTime = SettingKey<int>(
    'aria2SeedTime',
    -1,
    group: SettingGroup.magnet,
  );
  /// 做种分享率，达到该比例后停止做种。0 表示不限。
  static const aria2SeedRatio = SettingKey<double>(
    'aria2SeedRatio',
    1.0,
    group: SettingGroup.magnet,
  );
  /// 是否自动更新 tracker 列表。
  static const aria2TrackerAutoUpdate = SettingKey<bool>(
    'aria2TrackerAutoUpdate',
    true,
    group: SettingGroup.magnet,
  );
  /// tracker 自动更新间隔（小时）。
  static const aria2TrackerUpdateHours = SettingKey<int>(
    'aria2TrackerUpdateHours',
    24,
    group: SettingGroup.magnet,
  );
  /// tracker 更新源，每行一个 URL。
  static const aria2TrackerSources = SettingKey<String>(
    'aria2TrackerSources',
    'https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt\n'
        'https://raw.githubusercontent.com/XIU2/TrackersListCollection/master/best.txt\n'
        'https://newtrackon.com/api/stable',
    group: SettingGroup.magnet,
  );
  /// tracker 最近一次成功更新时间（epoch 毫秒），0 表示从未更新。
  static const aria2TrackerLastUpdated = SettingKey<int>(
    'aria2TrackerLastUpdated',
    0,
    group: SettingGroup.magnet,
  );
  /// 缓存的 tracker 列表（每行一个 announce URL）。
  static const aria2TrackersCache = SettingKey<String>(
    'aria2TrackersCache',
    '',
    group: SettingGroup.magnet,
  );
  /// 是否自动封禁吸血节点。
  static const aria2BanLeecher = SettingKey<bool>(
    'aria2BanLeecher',
    true,
    group: SettingGroup.magnet,
  );
  /// 是否自动封禁行为异常 IP（连接抖动、peerId 频繁变化等）。
  static const aria2BanAbnormalIp = SettingKey<bool>(
    'aria2BanAbnormalIp',
    true,
    group: SettingGroup.magnet,
  );
  /// 对等节点行为扫描间隔（秒）。
  static const aria2BanScanInterval = SettingKey<int>(
    'aria2BanScanInterval',
    30,
    group: SettingGroup.magnet,
  );
  /// 触发封禁所需的行为得分（越大越保守）。
  static const aria2BanThreshold = SettingKey<int>(
    'aria2BanThreshold',
    3,
    group: SettingGroup.magnet,
  );
  /// 单个对等节点被判定为“吸血”的最短累计观察时长（秒）。
  static const aria2BanObserveSeconds = SettingKey<int>(
    'aria2BanObserveSeconds',
    120,
    group: SettingGroup.magnet,
  );
  /// 吸血判定：我方已上传量需超过该值（KiB）且对端回传不足其 5% 时才计一次。
  static const aria2BanUploadThresholdKb = SettingKey<int>(
    'aria2BanUploadThresholdKb',
    2048,
    group: SettingGroup.magnet,
  );
  /// 被封禁的 IP 列表（JSON 数组），持久化保存。
  static const aria2BannedIps = SettingKey<String>(
    'aria2BannedIps',
    '[]',
    group: SettingGroup.magnet,
  );

  // 本地媒体库相关设置
  static const localMediaFolders = SettingKey<String>(
    'localMediaFolders',
    '[]',
    group: SettingGroup.media,
  );
  static const localMediaGroupByFolder = SettingKey<bool>(
    'localMediaGroupByFolder',
    true,
    group: SettingGroup.media,
  );
  static const localMediaScrapeResults = SettingKey<String>(
    'localMediaScrapeResults',
    '{}',
    group: SettingGroup.media,
  );
  static const localMediaViewMode = SettingKey<String>(
    'localMediaViewMode',
    'folder',
    group: SettingGroup.media,
  );
  /// 图片识别兜底：ffmpeg 可执行文件路径，留空则自动从 PATH/常见目录查找。
  static const localMediaFfmpegPath = SettingKey<String>(
    'localMediaFfmpegPath',
    '',
    group: SettingGroup.media,
  );
  /// 是否启用「抽帧 → trace.moe 以图搜番」兜底。
  static const localMediaTraceFallback = SettingKey<bool>(
    'localMediaTraceFallback',
    true,
    group: SettingGroup.media,
  );

  static final List<SettingKey<Object?>> all = [
    hAenable,
    hardwareDecoder,
    searchEnhanceEnable,
    autoUpdate,
    checkPluginUpdateOnStartup,
    alwaysOntop,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    danmakuEnhance,
    danmakuBorder,
    danmakuBorderSize,
    danmakuOpacity,
    danmakuFontSize,
    danmakuTop,
    danmakuScroll,
    danmakuBottom,
    danmakuMassive,
    danmakuDeduplication,
    danmakuArea,
    danmakuColor,
    danmakuDuration,
    danmakuLineHeight,
    danmakuTimeOffset,
    danmakuEnabledByDefault,
    danmakuBiliBiliSource,
    danmakuGamerSource,
    danmakuDanDanSource,
    danmakuFontWeight,
    danmakuFollowSpeed,
    themeMode,
    themeColor,
    privateMode,
    autoPlay,
    autoPlayNext,
    playResume,
    showPlayerError,
    oledEnhance,
    displayMode,
    enableGitProxy,
    enableBangumiProxy,
    enableSystemProxy,
    defaultStartupPage,
    isWideScreen,
    webDavEnable,
    webDavEnableHistory,
    webDavEnableCollect,
    webDavURL,
    webDavUsername,
    webDavPassword,
    lowMemoryMode,
    showWindowButton,
    useDynamicColor,
    exitBehavior,
    playerDebugMode,
    syncPlayEndPoint,
    syncPlayUserName,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    playerDisableAnimations,
    playerLogLevel,
    timelineNotShowAbandonedBangumis,
    timelineNotShowWatchedBangumis,
    timelineOnlyShowWatchingBangumis,
    useSystemFont,
    forceAdBlocker,
    backgroundPlayback,
    proxyEnable,
    proxyConfigured,
    proxyUrl,
    proxyTestUrl,
    showRating,
    showAnimeCounter,
    downloadParallelEpisodes,
    downloadParallelSegments,
    downloadDanmaku,
    downloadDirectory,
    downloadDirectoryBookmark,
    shortcutDialogShown,
    bangumiSyncEnable,
    bangumiAccessToken,
    bangumiSyncPriority,
    bangumiImmediateSyncToastEnable,
    brightnessVolumeGesture,
    historySyncDeviceId,
    historySyncSequence,
    historySyncSnapshotInitialized,
    playerControllerLayerDisappearTime,
    defaultVolume,
    playerMuted,
    mikanBaseUrl,
    magnetSearchSources,
    magnetDefaultSource,
    magnetAria2Enable,
    magnetAria2RpcUrl,
    magnetAria2Secret,
    magnetSubscriptions,
    magnetDownloadEntries,
    magnetEngineMode,
    aria2ExecutablePath,
    aria2RpcPort,
    aria2DownloadDir,
    aria2MaxConcurrentDownloads,
    aria2ListenPort,
    aria2MaxPeers,
    aria2MaxUploadLimitKb,
    aria2EnableDht,
    aria2EnableDht6,
    aria2EnableUpnp,
    aria2EnableNatPmp,
    aria2SeedTime,
    aria2SeedRatio,
    aria2TrackerAutoUpdate,
    aria2TrackerUpdateHours,
    aria2TrackerSources,
    aria2TrackerLastUpdated,
    aria2TrackersCache,
    aria2BanLeecher,
    aria2BanAbnormalIp,
    aria2BanScanInterval,
    aria2BanThreshold,
    aria2BanObserveSeconds,
    aria2BanUploadThresholdKb,
    aria2BannedIps,
    localMediaFolders,
    localMediaGroupByFolder,
    localMediaScrapeResults,
    localMediaViewMode,
    localMediaFfmpegPath,
    localMediaTraceFallback,
  ];

  static List<SettingKey<Object?>> byGroup(SettingGroup group) {
    return [
      for (final key in all)
        if (key.group == group) key
    ];
  }

  SettingsKeys._();
}

// Historical Hive key names used by settings created before the typed registry.
// Keep these strings stable so existing users keep their saved settings.
// New settings do not need to be added here unless they intentionally reuse an
// existing persisted key.
class _SettingBoxKey {
  static const String hAenable = 'hAenable',
      hardwareDecoder = 'hardwareDecoder',
      searchEnhanceEnable = 'searchEnhanceEnable',
      autoUpdate = 'autoUpdate',
      alwaysOntop = 'alwaysOntop',
      defaultPlaySpeed = 'defaultPlaySpeed',
      defaultShortcutForwardPlaySpeed = 'defaultShortcutForwardPlaySpeed',
      defaultAspectRatioType = 'defaultAspectRatioType',
      buttonSkipTime = 'buttonSkipTime',
      arrowKeySkipTime = 'arrowKeySkipTime',
      danmakuEnhance = 'danmakuEnhance',
      danmakuBorder = 'danmakuBorder',
      danmakuBorderSize = 'danmakuBorderSize',
      danmakuOpacity = 'danmakuOpacity',
      danmakuFontSize = 'danmakuFontSize',
      danmakuTop = 'danmakuTop',
      danmakuScroll = 'danmakuScroll',
      danmakuBottom = 'danmakuBottom',
      danmakuMassive = 'danmakuMassive',
      danmakuDeduplication = 'danmakuDeduplication',
      danmakuArea = 'danmakuArea',
      danmakuColor = 'danmakuColor',
      danmakuDuration = 'danmakuDuration',
      danmakuLineHeight = 'danmakuLineHeight',
      danmakuTimeOffset = 'danmakuTimeOffset',
      danmakuEnabledByDefault = 'danmakuEnabledByDefault',
      danmakuBiliBiliSource = 'danmakuBiliBiliSource',
      danmakuGamerSource = 'danmakuGamerSource',
      danmakuDanDanSource = 'danmakuDanDanSource',
      danmakuFontWeight = 'danmakuFontWeight',
      danmakuFollowSpeed = 'danmakuFollowSpeed',
      themeMode = 'themeMode',
      themeColor = 'themeColor',
      privateMode = 'privateMode',
      autoPlay = 'autoPlay',
      autoPlayNext = 'autoPlayNext',
      playResume = 'playResume',
      showPlayerError = 'showPlayerError',
      oledEnhance = 'oledEnhance',
      displayMode = 'displayMode',
      enableGitProxy = 'enableGitProxy',
      enableBangumiProxy = 'enableBangumiProxy',
      enableSystemProxy = 'enableSystemProxy',
      defaultStartupPage = 'defaultStartupPage',

      /// Deprecated
      isWideScreen = 'isWideScreen',
      webDavEnable = 'webDavEnable',
      webDavEnableHistory = 'webDavEnableHistory',
      webDavEnableCollect = 'webDavEnableCollect',
      webDavURL = 'webDavURL',
      webDavUsername = 'webDavUsername',
      webDavPassword = 'webDavPasswd',
      lowMemoryMode = 'lowMemoryMode',
      showWindowButton = 'showWindowButton',
      useDynamicColor = 'useDynamicColor',
      exitBehavior = 'exitBehavior',
      playerDebugMode = 'playerDebugMode',
      syncPlayEndPoint = 'syncPlayEndPoint',
      androidEnableOpenSLES = 'androidEnableOpenSLES',
      androidVideoRenderer = 'androidVideoRenderer',
      androidAutoEnterPIP = 'androidAutoEnterPIP',
      defaultSuperResolutionMode = 'defaultSuperResolutionType',
      disableSuperResolutionWarning = 'superResolutionWarn',
      playerDisableAnimations = 'playerDisableAnimations',
      playerLogLevel = 'playerLogLevel',
      timelineNotShowAbandonedBangumis = 'timelineNotShowAbandonedBangumis',
      timelineNotShowWatchedBangumis = 'timelineNotShowWatchedBangumis',
      timelineOnlyShowWatchingBangumis = 'timelineOnlyShowWatchingBangumis',
      useSystemFont = 'useSystemFont',
      forceAdBlocker = 'forceAdBlocker',
      backgroundPlayback = 'backgroundPlayback',
      proxyEnable = 'proxyEnable',
      proxyConfigured = 'proxyConfigured',
      proxyUrl = 'proxyUrl',
      proxyTestUrl = 'proxyTestUrl',
      showRating = 'showRating',
      showAnimeCounter = 'showAnimeCounter',
      downloadParallelEpisodes = 'downloadParallelEpisodes',
      downloadParallelSegments = 'downloadParallelSegments',
      downloadDanmaku = 'downloadDanmaku',
      downloadDirectory = 'downloadDirectory',
      shortcutDialogShown = 'shortcutDialogShown',
      bangumiSyncEnable = 'bangumiSyncEnable',
      bangumiAccessToken = 'bangumiAccessToken',
      bangumiSyncPriority = 'bangumiSyncPriority',
      bangumiImmediateSyncToastEnable = 'bangumiImmediateSyncToastEnable',
      brightnessVolumeGesture = 'brightnessVolumeGesture',
      historySyncDeviceId = 'historySyncDeviceId',
      historySyncSequence = 'historySyncSequence',
      historySyncSnapshotInitialized = 'historySyncSnapshotInitialized';
}
