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
        final initialQuery = args is String ? args : null;
        return MagnetPage(
          controller: inject<MagnetController>(),
          initialQuery: initialQuery,
        );
      },
    );
  },
);
