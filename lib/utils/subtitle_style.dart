import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 播放器字幕样式工具。
///
/// media-kit 播放器的 libass 渲染默认关闭，所有字幕（含 ASS/SRT）
/// 均由 Flutter 侧 `SubtitleView` 以纯文本形式渲染，样式完全由
/// [TextStyle] 决定，此处负责从设置构建该样式。
abstract final class SubtitleStyle {
  /// 从设置读取并构建字幕 [TextStyle]。
  static TextStyle fromSettings() {
    return build(
      fontSize: GStorage.getSetting(SettingsKeys.subtitleFontSize),
      textColor: Color(GStorage.getSetting(SettingsKeys.subtitleTextColor)),
      borderWidth: GStorage.getSetting(SettingsKeys.subtitleBorderWidth),
      borderColor: Color(GStorage.getSetting(SettingsKeys.subtitleBorderColor)),
      backgroundOpacity:
          GStorage.getSetting(SettingsKeys.subtitleBackgroundOpacity),
      bold: GStorage.getSetting(SettingsKeys.subtitleBold),
    );
  }

  /// 按参数构建字幕 [TextStyle]。
  static TextStyle build({
    required double fontSize,
    required Color textColor,
    required double borderWidth,
    required Color borderColor,
    required double backgroundOpacity,
    required bool bold,
  }) {
    return TextStyle(
      height: 1.4,
      fontSize: fontSize,
      color: textColor,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      background: Paint()
        ..color = backgroundOpacity > 0
            ? Colors.black.withValues(alpha: backgroundOpacity)
            : Colors.transparent,
      decoration: TextDecoration.none,
      shadows: buildBorderShadows(borderWidth, borderColor),
    );
  }

  /// 使用 8 方向阴影模拟描边效果，宽度为 0 时返回空列表。
  static List<Shadow> buildBorderShadows(double width, Color color) {
    if (width <= 0) {
      return const <Shadow>[];
    }
    return <Shadow>[
      for (final (int dx, int dy) in const <(int, int)>[
        (-1, -1),
        (0, -1),
        (1, -1),
        (-1, 0),
        (1, 0),
        (-1, 1),
        (0, 1),
        (1, 1),
      ])
        Shadow(
          offset: Offset(dx.toDouble() * width, dy.toDouble() * width),
          blurRadius: width,
          color: color,
        ),
    ];
  }

  /// 订阅字幕样式相关设置变化，用于播放中调整样式实时生效。
  static Stream<void> watch() {
    return GStorage.watchSettings(const [
      SettingsKeys.subtitleFontSize,
      SettingsKeys.subtitleTextColor,
      SettingsKeys.subtitleBorderWidth,
      SettingsKeys.subtitleBorderColor,
      SettingsKeys.subtitleBackgroundOpacity,
      SettingsKeys.subtitleBold,
    ]);
  }
}
