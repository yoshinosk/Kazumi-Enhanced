import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';
import 'package:kazumi/pages/magnet/magnet_page.dart';

final magnetModule = createModule(
  path: '/magnet',
  register: (c) {
    c.route(
      '/',
      child: (context, state) {
        final args = state.arguments;
        // 兼容旧调用：直接传字符串作为搜索关键词；
        // 新调用通过 MagnetSearchRouteArgs 携带关键词与关联番剧。
        final query = args is String ? args : args is MagnetSearchRouteArgs ? args.query : null;
        final anime =
            args is MagnetSearchRouteArgs ? args.anime : null;
        return MagnetPage(
          controller: inject<MagnetController>(),
          initialQuery: query,
          initialAnime: anime,
        );
      },
    );
  },
);
