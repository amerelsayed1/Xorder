import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/pos_main.dart';

import 'wiring.dart';

/// "XOrder POS - Cloud": one mode, fixed here and nowhere else
/// (pos-split-apps, BR-1), plus this app's own bindings. Everything else is
/// the shared till.
Future<void> main() =>
    runPos(mode: DeploymentMode.cloud, overrides: cloudOverrides());
