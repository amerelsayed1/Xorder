import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/pos_main.dart';

import 'data/local/cloud_datastore.dart';
import 'wiring.dart';

/// "XOrder POS - Cloud": one mode, fixed here and nowhere else
/// (pos-split-apps, BR-1), plus this app's own bindings. Everything else is
/// the shared till.
Future<void> main() => runPos(
  mode: DeploymentMode.cloud,
  overrides: cloudOverrides(),
  // The data file's key is this till's database credential: it has no
  // database password (pos-cloud-single-till-sqlite).
  embeddedDataKey: cloudDataKeyName,
);
