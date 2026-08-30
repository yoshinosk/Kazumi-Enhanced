import 'package:kazumi/utils/constants.dart';

/// 超分辨率档位，对应 Anime4K 官方的六种模式。
/// 参见上游 md/GLSL_Instructions_Advanced.md：
///   A = Restore -> Upscale -> Upscale
///   B = Restore_Soft -> Upscale -> Upscale
///   C = Upscale_Denoise -> Upscale
///   A+A / B+B / C+A 为对应的增强模式。
///
/// 枚举声明顺序即为开销递增顺序，UI 直接按 values 顺序展示。
/// storageValue 一旦发布不可变更：老用户本地已存的值会被原样读回，
/// 因此新增档位只能追加新值，off/efficiency/quality 的取值必须保持不变。
enum SuperResolutionMode {
  off(
    storageValue: 1,
    label: '关闭',
    description: '默认禁用超分辨率',
    shaders: [],
  ),
  efficiency(
    storageValue: 2,
    label: '效率档',
    description: '开销最低，适合本身较清晰、退化较少的片源',
    shaders: mpvAnime4KShadersModeC,
  ),
  denoise(
    storageValue: 7,
    label: '降噪档',
    description: '在效率档基础上补一次修复，可抑制轻微压缩噪点',
    shaders: mpvAnime4KShadersModeCA,
    requiresUpscaleRatioWarning: true,
  ),
  balanced(
    storageValue: 4,
    label: '均衡档',
    description: '针对降采样产生的振铃与锯齿优化，适合 720p 番剧',
    shaders: mpvAnime4KShadersModeB,
  ),
  quality(
    storageValue: 3,
    label: '质量档',
    description: '修复模糊与压缩伪影，适合大多数 1080p 番剧与老番',
    shaders: mpvAnime4KShadersModeA,
    requiresPerformanceWarning: true,
  ),
  balancedEnhanced(
    storageValue: 6,
    label: '均衡增强档',
    description: '均衡档的增强版，线条重建更完整，需 x2 以上放大倍率',
    shaders: mpvAnime4KShadersModeBB,
    requiresPerformanceWarning: true,
    requiresUpscaleRatioWarning: true,
  ),
  extreme(
    storageValue: 5,
    label: '极致档',
    description: '感知质量最高，但在 1080p 屏播放 1080p 片源会明显过锐，'
        '仅建议低分辨率片源放大时启用',
    shaders: mpvAnime4KShadersModeAA,
    requiresPerformanceWarning: true,
    requiresUpscaleRatioWarning: true,
  );

  const SuperResolutionMode({
    required this.storageValue,
    required this.label,
    required this.description,
    required this.shaders,
    this.requiresPerformanceWarning = false,
    this.requiresUpscaleRatioWarning = false,
  });

  final int storageValue;
  final String label;
  final String description;

  /// 该档位挂载到 mpv 的 glsl-shaders 列表，按数组顺序串联。
  final List<String> shaders;

  /// 开销较高，首次启用时应提示可能造成卡顿。
  final bool requiresPerformanceWarning;

  /// 属于上游的 secondary mode，仅在放大倍率 x2 及以上时才应启用。
  final bool requiresUpscaleRatioWarning;

  bool get isEnabled => this != SuperResolutionMode.off;

  static SuperResolutionMode fromStorageValue(int value) {
    return SuperResolutionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => SuperResolutionMode.off,
    );
  }
}
