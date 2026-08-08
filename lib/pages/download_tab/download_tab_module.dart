import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/download_tab/download_tab_page.dart';
import 'package:kazumi/pages/magnet/magnet_controller.dart';

final downloadTabModule = createModule(
  path: '/download',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => DownloadTabPage(
        magnetController: inject<MagnetController>(),
        downloadController: inject<DownloadController>(),
      ),
    );
  },
);
