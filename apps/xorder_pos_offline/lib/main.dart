import 'package:xorder_pos/core/config/deployment.dart';
import 'package:xorder_pos/pos_main.dart';

/// "XOrder POS - Offline": one mode, fixed here and nowhere else
/// (pos-split-apps, BR-1). Everything else is the shared till.
Future<void> main() => runPos(mode: DeploymentMode.offline);
