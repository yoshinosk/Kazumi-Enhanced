import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/stats/stats_controller.dart';
import 'package:kazumi/pages/stats/stats_page.dart';

final statsModule = createModule(
  path: '/stats',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s..add<StatsController>(StatsController.new),
      child: (context, state) =>
          StatsPage(controller: context.read<StatsController>()),
    );
  },
);
