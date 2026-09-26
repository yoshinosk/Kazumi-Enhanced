import 'package:flutter/material.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/settings/settings_list.dart';
import 'package:kazumi/services/storage/settings_keys.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/subtitle_style.dart';

class SubtitleSettingsPage extends StatefulWidget {
  const SubtitleSettingsPage({super.key});

  @override
  State<SubtitleSettingsPage> createState() => _SubtitleSettingsPageState();
}

class _SubtitleSettingsPageState extends State<SubtitleSettingsPage> {
  /// 字体颜色预设色板。
  static const Map<String, int> textColorChoices = {
    '粉红': 0xFFFF4081,
    '白色': 0xFFFFFFFF,
    '黄色': 0xFFFFEB3B,
    '青色': 0xFF00E5FF,
    '绿色': 0xFF69F0AE,
    '橙色': 0xFFFFAB40,
    '紫色': 0xFFB388FF,
    '红色': 0xFFFF5252,
  };

  /// 描边颜色预设色板。
  static const Map<String, int> borderColorChoices = {
    '白色': 0xFFFFFFFF,
    '黑色': 0xFF000000,
    '深灰': 0xFF424242,
    '灰色': 0xFF9E9E9E,
  };

  late double fontSize;
  late int textColor;
  late double borderWidth;
  late int borderColor;
  late double backgroundOpacity;
  late bool bold;

  final MenuController textColorMenuController = MenuController();
  final MenuController borderColorMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    _loadSettingsFromStorage();
  }

  void _loadSettingsFromStorage() {
    fontSize = GStorage.getSetting<double>(SettingsKeys.subtitleFontSize);
    textColor = GStorage.getSetting<int>(SettingsKeys.subtitleTextColor);
    borderWidth = GStorage.getSetting<double>(SettingsKeys.subtitleBorderWidth);
    borderColor = GStorage.getSetting<int>(SettingsKeys.subtitleBorderColor);
    backgroundOpacity = GStorage.getSetting<double>(
      SettingsKeys.subtitleBackgroundOpacity,
    );
    bold = GStorage.getSetting<bool>(SettingsKeys.subtitleBold);
  }

  String _colorLabel(int value, Map<String, int> choices) {
    for (final entry in choices.entries) {
      if (entry.value == value) {
        return entry.key;
      }
    }
    return '自定义';
  }

  void updateFontSize(double value) {
    final newValue = double.parse(value.toStringAsFixed(1));
    if (newValue == fontSize) return;
    GStorage.putSetting<double>(SettingsKeys.subtitleFontSize, newValue);
    setState(() {
      fontSize = newValue;
    });
  }

  void updateTextColor(int value) {
    if (value == textColor) return;
    GStorage.putSetting<int>(SettingsKeys.subtitleTextColor, value);
    setState(() {
      textColor = value;
    });
  }

  void updateBorderWidth(double value) {
    final newValue = double.parse(value.toStringAsFixed(1));
    if (newValue == borderWidth) return;
    GStorage.putSetting<double>(SettingsKeys.subtitleBorderWidth, newValue);
    setState(() {
      borderWidth = newValue;
    });
  }

  void updateBorderColor(int value) {
    if (value == borderColor) return;
    GStorage.putSetting<int>(SettingsKeys.subtitleBorderColor, value);
    setState(() {
      borderColor = value;
    });
  }

  void updateBackgroundOpacity(double value) {
    final newValue = double.parse(value.toStringAsFixed(1));
    if (newValue == backgroundOpacity) return;
    GStorage.putSetting<double>(
      SettingsKeys.subtitleBackgroundOpacity,
      newValue,
    );
    setState(() {
      backgroundOpacity = newValue;
    });
  }

  void updateBold(bool value) {
    GStorage.putSetting<bool>(SettingsKeys.subtitleBold, value);
    setState(() {
      bold = value;
    });
  }

  TextStyle get previewStyle {
    return SubtitleStyle.build(
      fontSize: fontSize,
      textColor: Color(textColor),
      borderWidth: borderWidth,
      borderColor: Color(borderColor),
      backgroundOpacity: backgroundOpacity,
      bold: bold,
    );
  }

  Widget buildColorMenu({
    required MenuController controller,
    required Map<String, int> choices,
    required int currentValue,
    required ValueChanged<int> onSelected,
  }) {
    return MenuAnchor(
      consumeOutsideTap: true,
      controller: controller,
      builder: (_, __, ___) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color(currentValue),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(_colorLabel(currentValue, choices)),
          ],
        );
      },
      menuChildren: [
        for (final entry in choices.entries)
          MenuItemButton(
            requestFocusOnHover: false,
            onPressed: () => onSelected(entry.value),
            child: Container(
              height: 48,
              constraints: const BoxConstraints(minWidth: 112),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Color(entry.value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                        width: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    entry.key,
                    style: TextStyle(
                      color: entry.value == currentValue
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('字幕样式'),
      body: Column(
        children: [
          // 实时预览区：模拟视频画面上的字幕效果。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Container(
              width: double.infinity,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.bottomCenter,
              padding: const EdgeInsets.all(16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '字幕样式预览 Kazumi',
                  style: previewStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Expanded(
            child: SettingsList(
              sections: [
                SettingsSection(
                  title: Text('字体'),
                  tiles: [
                    SettingsSliderTile(
                      leading: Icons.format_size_rounded,
                      title: Text('字号'),
                      value: fontSize,
                      min: 20,
                      max: 72,
                      divisions: 26,
                      valueLabel: fontSize.round().toString(),
                      onChanged: updateFontSize,
                    ),
                    SettingsTile.switchTile(
                      leading: Icons.format_bold_rounded,
                      onToggle: (value) {
                        updateBold(value ?? !bold);
                      },
                      title: Text('加粗'),
                      initialValue: bold,
                    ),
                    SettingsTile(
                      leading: Icons.palette_rounded,
                      onPressed: (_) {
                        if (textColorMenuController.isOpen) {
                          textColorMenuController.close();
                        } else {
                          textColorMenuController.open();
                        }
                      },
                      title: Text('字体颜色'),
                      value: buildColorMenu(
                        controller: textColorMenuController,
                        choices: textColorChoices,
                        currentValue: textColor,
                        onSelected: updateTextColor,
                      ),
                    ),
                  ],
                ),
                SettingsSection(
                  title: Text('描边与背景'),
                  tiles: [
                    SettingsSliderTile(
                      leading: Icons.border_color_rounded,
                      title: Text('描边宽度'),
                      value: borderWidth,
                      min: 0,
                      max: 5,
                      divisions: 10,
                      valueLabel: borderWidth <= 0
                          ? '关闭'
                          : borderWidth.toStringAsFixed(1),
                      onChanged: updateBorderWidth,
                    ),
                    SettingsTile(
                      leading: Icons.format_color_fill_rounded,
                      onPressed: (_) {
                        if (borderColorMenuController.isOpen) {
                          borderColorMenuController.close();
                        } else {
                          borderColorMenuController.open();
                        }
                      },
                      title: Text('描边颜色'),
                      value: buildColorMenu(
                        controller: borderColorMenuController,
                        choices: borderColorChoices,
                        currentValue: borderColor,
                        onSelected: updateBorderColor,
                      ),
                    ),
                    SettingsSliderTile(
                      leading: Icons.texture_rounded,
                      title: Text('背景不透明度'),
                      description: Text('在字幕文字后显示半透明黑色背景'),
                      value: backgroundOpacity,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      valueLabel: backgroundOpacity <= 0
                          ? '关闭'
                          : '${(backgroundOpacity * 100).round()}%',
                      onChanged: updateBackgroundOpacity,
                    ),
                  ],
                ),
                SettingsSection(
                  tiles: [
                    SettingsTile(
                      leading: Icons.settings_backup_restore_rounded,
                      onPressed: (_) async {
                        await GStorage.resetSettings(const [
                          SettingsKeys.subtitleFontSize,
                          SettingsKeys.subtitleTextColor,
                          SettingsKeys.subtitleBorderWidth,
                          SettingsKeys.subtitleBorderColor,
                          SettingsKeys.subtitleBackgroundOpacity,
                          SettingsKeys.subtitleBold,
                        ]);
                        // resetSettings 含磁盘 IO，await 期间页面可能已
                        // 被弹出，setState 前必须确认仍然 mounted。
                        if (!mounted) return;
                        setState(_loadSettingsFromStorage);
                      },
                      title: Text('恢复默认字幕样式'),
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
