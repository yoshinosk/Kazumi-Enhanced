import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/season_mark/season_mark_controller.dart';
import 'package:kazumi/pages/season_mark/season_mark_page.dart';

final seasonMarkModule = createModule(
  path: '/mark',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s..add<SeasonMarkController>(SeasonMarkController.new),
      child: (context, state) {
        int? initialYear;
        int? initialQuarterMonth;
        final args = state.arguments;
        if (args is Map) {
          initialYear = args['year'] as int?;
          initialQuarterMonth = args['month'] as int?;
        }
        return SeasonMarkPage(
          controller: context.read<SeasonMarkController>(),
          initialYear: initialYear,
          initialQuarterMonth: initialQuarterMonth,
        );
      },
    );
  },
);
