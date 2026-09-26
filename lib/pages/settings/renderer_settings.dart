import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/bean/settings/settings_list.dart';

class RendererSettings extends StatefulWidget {
  const RendererSettings({super.key});

  @override
  State<RendererSettings> createState() => _RendererSettingsState();
}

class _RendererSettingsState extends State<RendererSettings> {
  // 项目只面向 Android 与 Windows，其余平台沿用 Android 的选项以免取到空值。
  final bool _useAndroidRenderers = !Platform.isWindows;

  late final ValueNotifier<String> renderer = ValueNotifier<String>(
    GStorage.getSetting<String>(_settingKey),
  );

  SettingKey<String> get _settingKey => _useAndroidRenderers
      ? SettingsKeys.androidVideoRenderer
      : SettingsKeys.windowsVideoRenderer;

  Map<String, String> get _renderersList => _useAndroidRenderers
      ? androidVideoRenderersList
      : windowsVideoRenderersList;

  @override
  void dispose() {
    renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SysAppBar(
        title: Text('视频渲染器'),
      ),
      body: SettingsList(
        sections: [
          SettingsRadioSection<String>(
            title: Text(_useAndroidRenderers
                ? '选择合适的渲染器以获得最佳播放体验'
                : '启用超分辨率时建议使用 gpu-next，可获得更好的着色器性能'),
            groupValue: renderer.value,
            onChanged: (String? value) {
              if (value != null) {
                GStorage.putSetting<String>(_settingKey, value);
                setState(() {
                  renderer.value = value;
                });
              }
            },
            tiles: _renderersList.entries
                .map((e) => SettingsTile<String>.radioTile(
                      title: Text(e.key),
                      description: Text(e.value),
                      radioValue: e.key,
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
