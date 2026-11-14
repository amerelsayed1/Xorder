import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'mode.dart';

/// "XOrder Waiter – Cloud": `flutter run --flavor cloud -t lib/main_cloud.dart`.
void main() => runApp(
  ProviderScope(
    overrides: [waiterModeProvider.overrideWithValue(WaiterMode.cloud)],
    child: const WaiterApplication(),
  ),
);
