import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/collect_crud_repository.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/media/local_availability_service.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';

/// Root-owned application data and cross-feature coordinators.
///
/// This module intentionally has no path, so its registrations live for the
/// whole application. Page and feature-local state belongs in route `provide`
/// callbacks or path-bearing modules instead.
final coreModule = createModule(
  register: (c) {
    c
      // Repository layer.
      ..addSingleton<ICollectRepository>(CollectRepository.new)
      ..addSingleton<ISearchHistoryRepository>(SearchHistoryRepository.new)
      ..addSingleton<ICollectCrudRepository>(CollectCrudRepository.new)
      ..addSingleton<IHistoryRepository>(HistoryRepository.new)
      ..addSingleton<IDownloadRepository>(DownloadRepository.new)
      // Service layer.
      ..addSingleton<IDownloadManager>(DownloadManager.new)
      ..addSingleton<AudioController>(AudioController.new)
      ..addSingleton<HistoryPlaybackService>(HistoryPlaybackService.new)
      ..addSingleton<LocalAvailabilityService>(LocalAvailabilityService.new)
      ..addSingleton<ShaderAssetService>(ShaderAssetService.new)
      // Cross-feature state and coordinators.
      ..addSingleton<PluginsController>(PluginsController.new)
      ..addSingleton<CollectController>(CollectController.new)
      ..addSingleton<HistoryController>(HistoryController.new)
      ..addSingleton<MyController>(MyController.new)
      ..addSingleton<DownloadController>(DownloadController.new)
      ..addSingleton<MagnetController>(MagnetController.new)
      ..addSingleton<MediaController>(MediaController.new);
  },
);
