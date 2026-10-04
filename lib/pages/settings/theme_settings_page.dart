import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/palette_card.dart';
import 'package:kazumi/bean/settings/background_provider.dart';
import 'package:kazumi/bean/widget/app_background_layer.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/bean/settings/color_type.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/utils/theme.dart';
import 'package:path/path.dart' as p;

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  late dynamic defaultThemeMode;
  late dynamic defaultThemeColor;
  late bool oledEnhance;
  late bool useDynamicColor;
  late bool showWindowButton;
  late bool useSystemFont;
  late final ThemeProvider themeProvider;
  late final BackgroundProvider backgroundProvider;
  bool _pickingBackground = false;

  @override
  void initState() {
    super.initState();
    defaultThemeMode = GStorage.getSetting(SettingsKeys.themeMode);
    defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    useDynamicColor = GStorage.getSetting(SettingsKeys.useDynamicColor);
    showWindowButton = GStorage.getSetting(SettingsKeys.showWindowButton);
    useSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    themeProvider = context.read<ThemeProvider>();
    backgroundProvider = context.read<BackgroundProvider>();
  }

  void setTheme(Color? color) {
    final defaultDarkTheme = buildAppTheme(
        brightness: Brightness.dark,
        fontFamily: themeProvider.currentFontFamily,
        color: color);
    final oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      buildAppTheme(
          brightness: Brightness.light,
          fontFamily: themeProvider.currentFontFamily,
          color: color),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = color?.toARGB32().toRadixString(16) ?? 'default';
    GStorage.putSetting(SettingsKeys.themeColor, defaultThemeColor);
  }

  void resetTheme() {
    final defaultDarkTheme = buildAppTheme(
        brightness: Brightness.dark,
        fontFamily: themeProvider.currentFontFamily,
        color: Colors.green);
    final oledTheme = oledDarkTheme(defaultDarkTheme);
    themeProvider.setTheme(
      buildAppTheme(
          brightness: Brightness.light,
          fontFamily: themeProvider.currentFontFamily,
          color: Colors.green),
      oledEnhance ? oledTheme : defaultDarkTheme,
    );
    defaultThemeColor = 'default';
    GStorage.putSetting(SettingsKeys.themeColor, 'default');
  }

  void updateTheme(String theme) async {
    if (theme == 'dark') {
      themeProvider.setThemeMode(ThemeMode.dark);
    }
    if (theme == 'light') {
      themeProvider.setThemeMode(ThemeMode.light);
    }
    if (theme == 'system') {
      themeProvider.setThemeMode(ThemeMode.system);
    }
    await GStorage.putSetting(SettingsKeys.themeMode, theme);
    setState(() {
      defaultThemeMode = theme;
    });

    // Update Windows title bar theme
    if (Platform.isWindows) {
      await windowManager.setBrightness(
          themeProvider.isEffectiveDark() ? Brightness.dark : Brightness.light);
    }
  }

  void updateOledEnhance() {
    dynamic color;
    oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    if (defaultThemeColor == 'default') {
      color = Colors.green;
    } else {
      color = Color(int.parse(defaultThemeColor, radix: 16));
    }
    setTheme(color);
  }

  Future<void> pickBackgroundImage() async {
    if (_pickingBackground) return;
    _pickingBackground = true;
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择背景图片',
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await backgroundProvider.installImage(path);
      if (mounted) setState(() {});
    } catch (e) {
      KazumiDialog.showToast(message: '背景图设置失败：$e');
    } finally {
      _pickingBackground = false;
    }
  }

  void manageBackgroundImage() {
    final name = p.basename(backgroundProvider.imagePath ?? '');
    KazumiDialog.show(builder: (context) {
      return AlertDialog(
        title: const Text('背景图片'),
        content: Text(name.isEmpty ? '已设置' : name),
        actions: [
          TextButton(
            onPressed: () {
              KazumiDialog.dismiss();
              pickBackgroundImage();
            },
            child: const Text('更换图片'),
          ),
          TextButton(
            onPressed: () {
              KazumiDialog.dismiss();
              clearBackgroundImage();
            },
            child: const Text('清除背景图'),
          ),
        ],
      );
    });
  }

  Future<void> clearBackgroundImage() async {
    await backgroundProvider.clearImage();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('外观设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text('外观'),
            tiles: [
              SettingsDropdownTile<String>(
                leading: Icons.dark_mode_rounded,
                title: const Text('深色模式'),
                value: defaultThemeMode,
                fallbackLabel: '跟随系统',
                options: const {'system': '跟随系统', 'light': '浅色', 'dark': '深色'},
                onChanged: updateTheme,
              ),
              SettingsTile(
                leading: Icons.palette_rounded,
                enabled: !useDynamicColor,
                onPressed: (_) async {
                  KazumiDialog.show(builder: (context) {
                    return AlertDialog(
                      title: Text('配色方案'),
                      content: StatefulBuilder(builder:
                          (BuildContext context, StateSetter setState) {
                        final List<Map<String, dynamic>> colorThemes =
                            colorThemeTypes;
                        return Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: isDesktop() ? 8 : 0,
                          children: [
                            ...colorThemes.map(
                              (e) {
                                final index = colorThemes.indexOf(e);
                                return GestureDetector(
                                  onTap: () {
                                    index == 0
                                        ? resetTheme()
                                        : setTheme(e['color']);
                                    KazumiDialog.dismiss();
                                  },
                                  child: Column(
                                    children: [
                                      PaletteCard(
                                        color: e['color'],
                                        selected: (e['color']
                                                    .value
                                                    .toRadixString(16) ==
                                                defaultThemeColor ||
                                            (defaultThemeColor == 'default' &&
                                                index == 0)),
                                      ),
                                      Text(e['label']),
                                    ],
                                  ),
                                );
                              },
                            )
                          ],
                        );
                      }),
                    );
                  });
                },
                title: Text('配色方案'),
              ),
              SettingsTile.switchTile(
                leading: Icons.colorize_rounded,
                enabled: !Platform.isIOS,
                onToggle: (value) async {
                  useDynamicColor = value ?? !useDynamicColor;
                  await GStorage.putSetting(
                      SettingsKeys.useDynamicColor, useDynamicColor);
                  themeProvider.setDynamic(useDynamicColor);
                  setState(() {});
                },
                title: Text('动态配色'),
                initialValue: useDynamicColor,
              ),
              SettingsTile.switchTile(
                leading: Icons.font_download_rounded,
                onToggle: (value) async {
                  useSystemFont = value ?? !useSystemFont;
                  await GStorage.putSetting(
                      SettingsKeys.useSystemFont, useSystemFont);
                  themeProvider.setFontFamily(useSystemFont);
                  dynamic color;
                  if (defaultThemeColor == 'default') {
                    color = Colors.green;
                  } else {
                    color = Color(int.parse(defaultThemeColor, radix: 16));
                  }
                  setTheme(color);
                  setState(() {});
                },
                title: Text('使用系统字体'),
                description: Text('关闭后使用 MI Sans 字体'),
                initialValue: useSystemFont,
              ),
            ],
            bottomInfo: Text('动态配色仅支持安卓12及以上和桌面平台'),
          ),
          SettingsSection(
            title: Text('自定义背景'),
            tiles: [
              if (backgroundProvider.hasImage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 120,
                      width: double.infinity,
                      // 预览与实际一致的叠加效果：背景图 + 半透明表面色。
                      // 表面色直接取环境主题的值：AppSurfaceLayer 已经把整棵树
                      // 换成玻璃态，这里再乘一次遮罩会比实际更透。
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const AppBackgroundLayer(),
                          ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SettingsTile(
                leading: Icons.wallpaper_rounded,
                title: Text('背景图片'),
                value: Text(backgroundProvider.hasImage ? '已设置' : '未设置'),
                onPressed: (_) => backgroundProvider.hasImage
                    ? manageBackgroundImage()
                    : pickBackgroundImage(),
              ),
              SettingsTile.switchTile(
                leading: Icons.blur_on_rounded,
                enabled: backgroundProvider.hasImage,
                onToggle: (value) async {
                  await backgroundProvider.setBlurEnabled(
                      value ?? !backgroundProvider.blurEnabled);
                  setState(() {});
                },
                title: Text('毛玻璃效果'),
                description: Text('对背景图应用高斯模糊'),
                initialValue: backgroundProvider.blurEnabled,
              ),
              if (backgroundProvider.hasImage &&
                  backgroundProvider.blurEnabled)
                SettingsSliderTile(
                  leading: Icons.tune_rounded,
                  title: Text('模糊强度'),
                  value: backgroundProvider.blurSigma,
                  valueLabel: backgroundProvider.blurSigma.round().toString(),
                  min: 4,
                  max: 50,
                  divisions: 23,
                  onChanged: (value) async {
                    await backgroundProvider.setBlurSigma(value);
                    setState(() {});
                  },
                ),
              if (backgroundProvider.hasImage)
                SettingsSliderTile(
                  leading: Icons.opacity_rounded,
                  title: Text('背景不透明度'),
                  description: Text('背景图透出的强度，过高可能影响可读性'),
                  value: backgroundProvider.opacity,
                  valueLabel:
                      '${(backgroundProvider.opacity * 100).round()}%',
                  min: 0.05,
                  max: 1.0,
                  divisions: 19,
                  onChanged: (value) async {
                    await backgroundProvider.setOpacity(value);
                    setState(() {});
                  },
                ),
            ],
            bottomInfo: Text('背景图显示于所有页面，播放器与图片预览不受影响'),
          ),
          SettingsSection(
            title: Text('显示'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.contrast_rounded,
                onToggle: (value) async {
                  oledEnhance = value ?? !oledEnhance;
                  await GStorage.putSetting(
                      SettingsKeys.oledEnhance, oledEnhance);
                  updateOledEnhance();
                  setState(() {});
                },
                title: Text('OLED优化'),
                description: Text('深色模式下使用纯黑背景'),
                initialValue: oledEnhance,
              ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: Text('窗口'),
              tiles: [
                SettingsTile.switchTile(
                  leading: Icons.web_asset_rounded,
                  onToggle: (value) async {
                    showWindowButton = value ?? !showWindowButton;
                    await GStorage.putSetting(
                        SettingsKeys.showWindowButton, showWindowButton);
                    setState(() {});
                  },
                  title: Text('使用系统标题栏'),
                  description: Text('重启应用生效'),
                  initialValue: showWindowButton,
                ),
              ],
            ),
          if (Platform.isAndroid)
            SettingsSection(
              title: Text('屏幕'),
              tiles: [
                SettingsTile(
                  leading: Icons.sixty_fps_rounded,
                  onPressed: (_) async {
                    context.pushNamed('/settings/theme/display');
                  },
                  title: Text('屏幕帧率'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
