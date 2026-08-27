import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';

/// A POS terminal is a fixed installation, not a phone. The window is given a
/// minimum size that the three-pane shell actually fits in, so a cashier cannot
/// drag the till into a layout the design never covered.
const _minimumWindow = Size(1024, 700);
const _initialWindow = Size(1440, 900);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: _initialWindow,
        minimumSize: _minimumWindow,
        title: 'XOrder POS',
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(const ProviderScope(child: XorderPosApp()));
}

bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
