import 'dart:io';

import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:path/path.dart' as p;

/// 视频抽帧器：运行时查找 ffmpeg/ffprobe，从本地视频抽取一帧 JPEG 用于以图搜番。
///
/// 搜刮兜底链路：视频文件 → 抽帧 → trace.moe 图片识别 → 标题 → Bangumi 元数据。
class VideoFrameExtractor {
  VideoFrameExtractor._();

  static final VideoFrameExtractor instance = VideoFrameExtractor._();

  String? _ffmpeg;
  String? _ffprobe;
  bool _resolved = false;

  /// 是否可用（已找到 ffmpeg）。
  bool get isAvailable => ffmpeg != null;

  /// ffmpeg 可执行文件路径，找不到时返回 null。
  ///
  /// 首次调用时检测一次（同步，使用 Process.runSync），结果被缓存。
  String? get ffmpeg {
    if (!_resolved) {
      _resolved = true;
      if (_ffmpeg == null) {
        String custom = '';
        try {
          custom =
              GStorage.getSetting(SettingsKeys.localMediaFfmpegPath).trim();
        } catch (_) {
          // 存储盒未初始化（例如单元测试环境）时走自动查找。
        }
        if (custom.isNotEmpty && _exists(custom)) {
          _ffmpeg = custom;
        } else {
          _locateSync();
        }
        if (_ffmpeg != null) {
          _ffprobe = _findProbeNearSync(_ffmpeg!);
          KazumiLogger().d('VideoFrameExtractor: using ffmpeg at $_ffmpeg');
        } else {
          KazumiLogger().d(
              'VideoFrameExtractor: ffmpeg not found, image trace fallback disabled');
        }
      }
    }
    return _ffmpeg;
  }

  String? get ffprobe =>
      (_ffprobe != null && _exists(_ffprobe!)) ? _ffprobe : null;

  void _locateSync() {
    String? path;
    if (Platform.isWindows) {
      path = _resolveRun('where', ['ffmpeg']);
    } else {
      path = _resolveRun('which', ['ffmpeg']);
    }
    if (path == null) {
      for (final candidate in _commonLocations('ffmpeg')) {
        if (_exists(candidate)) {
          path = candidate;
          break;
        }
      }
    }
    _ffmpeg = path;
  }

  static String? _resolveRun(String cmd, List<String> args) {
    try {
      final r = Process.runSync(cmd, args);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return null;
      final first = out.split(RegExp(r'[\r\n]+')).first.trim();
      return _exists(first) ? first : null;
    } catch (_) {
      return null;
    }
  }

  static String? _findProbeNearSync(String ffmpegPath) {
    final dir = p.dirname(ffmpegPath);
    final probe = p.join(dir, Platform.isWindows ? 'ffprobe.exe' : 'ffprobe');
    return _exists(probe) ? probe : null;
  }

  static bool _exists(String path) {
    try {
      return File(path).existsSync() || Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static List<String> _commonLocations(String exe) {
    final dirs = <String>[
      if (Platform.isWindows) ...[
        r'C:\ffmpeg\bin',
        r'C:\Program Files\ffmpeg\bin',
        r'C:\Program Files (x86)\ffmpeg\bin',
        r'D:\ffmpeg\bin',
      ] else ...[
        '/usr/bin',
        '/usr/local/bin',
        '/opt/homebrew/bin',
      ],
    ];
    return [
      for (final d in dirs)
        if (Platform.isWindows) '$d\\$exe.exe' else '$d/$exe',
    ];
  }

  /// 抽取视频的一帧 JPEG，返回临时文件；失败时返回 null。
  Future<File?> extractFrame(String videoPath) async {
    final bin = ffmpeg;
    if (bin == null) return null;
    if (!File(videoPath).existsSync()) return null;

    final tmpDir = Directory.systemTemp;
    final out = File(p.join(
      tmpDir.path,
      'kazumi_trace_${DateTime.now().millisecondsSinceEpoch}.jpg',
    ));

    final ts = await _sampleTimestamp(videoPath);

    try {
      final r = await Process.run(bin, [
        '-y',
        '-v', 'error',
        '-ss', ts.toString(),
        '-i', videoPath,
        '-frames:v', '1',
        '-vf', 'scale=480:-2',
        '-q:v', '4',
        out.path,
      ]);
      if (r.exitCode != 0) {
        KazumiLogger().w(
            'VideoFrameExtractor: ffmpeg exit=${r.exitCode} stderr=${r.stderr}');
        if (await out.exists()) {
          await out.delete();
        }
        return null;
      }
      if (!await out.exists() || await out.length() == 0) {
        if (await out.exists()) {
          await out.delete();
        }
        return null;
      }
      return out;
    } catch (e) {
      KazumiLogger().w('VideoFrameExtractor: extract failed', error: e);
      return null;
    }
  }

  /// 用 ffprobe 读取时长，取中段时间点抽帧（避开片头片尾）。
  Future<int> _sampleTimestamp(String videoPath) async {
    final probe = ffprobe;
    if (probe == null) return 300; // 无 ffprobe 时退化为固定时间点
    try {
      final r = await Process.run(probe, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'csv=p=0',
        videoPath,
      ]);
      final duration = double.tryParse((r.stdout as String).trim());
      if (duration == null || duration <= 0) return 10;
      // 在 30%~70% 之间抽样
      final target = duration * (0.3 + (DateTime.now().millisecond % 40) / 100);
      return target.clamp(1, duration).floor();
    } catch (e) {
      return 10;
    }
  }
}