import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/background_provider.dart';

/// 背景启用时，页面 / 导航等「表面」使用的半透明底色：
/// 主题 scaffoldBackgroundColor 乘以 (1 - 背景不透明度)。
///
/// 统一用它而非全透明，既能透出背景图，又保证文字在图片上的可读性；
/// 固定头部（媒体库 / 时间表）以 scaffoldBackgroundColor 铺底，会自动跟随。
Color backgroundVeilColor(BuildContext context, BackgroundProvider background) {
  final scaffoldColor = Theme.of(context).scaffoldBackgroundColor;
  return scaffoldColor.withValues(alpha: (1.0 - background.opacity).clamp(0.0, 1.0));
}

/// 主界面自定义背景图层：铺满父级，按设置绘制图片与毛玻璃（高斯模糊）。
///
/// 未设置背景图时渲染为空；透明度由页面侧的 [backgroundVeilColor]
/// 半透明底色实现，本组件只负责图片本身。
class AppBackgroundLayer extends StatelessWidget {
  const AppBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final background = context.watch<BackgroundProvider>();
    final path = background.imagePath;
    if (path == null) {
      return const SizedBox.shrink();
    }

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      cacheWidth: _decodeWidth(context),
    );
    if (background.blurEnabled) {
      // ImageFiltered 只模糊图片本身，开销远小于对整页实时 BackdropFilter；
      // 静态内容会被光栅缓存，滑动页面时不重复计算。
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: background.blurSigma,
          sigmaY: background.blurSigma,
        ),
        child: image,
      );
    }

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 图片解码完成前先垫上默认背景色，避免闪白 / 闪黑。
          ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          image,
        ],
      ),
    );
  }

  /// 按屏幕最长边限制解码尺寸，控制整屏背景图的内存占用；
  /// 覆盖裁切下该尺寸已足够清晰，毛玻璃模式下更看不出差异。
  int _decodeWidth(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (size.longestSide * dpr).round().clamp(640, 4096);
  }
}
