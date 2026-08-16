import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/media/media_controller.dart';
import 'package:kazumi/pages/media/media_library_page.dart';

final mediaModule = createModule(
  path: '/media',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => MediaLibraryPage(
        controller: inject<MediaController>(),
      ),
    );
  },
);
