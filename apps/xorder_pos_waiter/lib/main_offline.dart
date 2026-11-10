import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'mode.dart';

/// "XOrder Waiter – Offline": `flutter run --flavor offline -t lib/main_offline.dart`.
void main() => runApp(
  ProviderScope(
    overrides: [waiterModeProvider.overrideWithValue(WaiterMode.offline)],
    child: const WaiterApplication(),
  ),
);
