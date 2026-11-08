import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:xorder_pos_offline/wiring.dart';
import 'package:xorder_pos_test_support/fakes.dart';

export 'package:xorder_pos_test_support/fakes.dart';

/// The shared test harness, as THIS app runs: the fakes, plus the offline
/// app's own bindings (`offlineOverrides`) — the back office behind
/// `PosRoutes.management` and the window bar's menus. A test that pumps the
/// whole app needs both, exactly as `main.dart` supplies both; without the
/// second the shell has no back office to open (pos-split-apps, stage 3).
List<Override> offlineTestOverrides({
  bool english = true,
  Future<List<int>> Function()? schemaUpgrader,
  DeploymentMode? appMode,
}) => [
  ...fakeRepositoryOverrides(
    english: english,
    schemaUpgrader: schemaUpgrader,
    appMode: appMode,
  ),
  ...offlineOverrides(),
];
