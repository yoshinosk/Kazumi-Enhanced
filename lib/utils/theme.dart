import 'package:flutter/material.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/surface_theme.dart';

/// 应用主题的唯一构造入口：启动初始化与外观设置共用，
/// 避免运行时切换主题色后丢失主题扩展（如卡片描边）。
ThemeData buildAppTheme({
  required Brightness brightness,
  required String? fontFamily,
  Color? color,
  ColorScheme? colorScheme,
}) {
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    brightness: brightness,
    colorSchemeSeed: color,
    colorScheme: colorScheme,
    progressIndicatorTheme: progressIndicatorTheme2024,
    sliderTheme: sliderTheme2024,
    pageTransitionsTheme: pageTransitionsTheme2024,
    // 卡片描边的默认值；主界面启用自定义背景图时由
    // backgroundSurfaceTheme 换成半透明表面 + 描边。
    extensions: const <ThemeExtension<dynamic>>[KazumiSurfaces.solid()],
  );
}

ThemeData oledDarkTheme(ThemeData defaultDarkTheme) {
  return defaultDarkTheme.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: defaultDarkTheme.colorScheme.copyWith(
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
    ),
  );
}
