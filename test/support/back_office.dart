import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xorder_pos/features/admin/presentation/management_screen.dart';

/// A [ManagementScreen] a test moves the way the window's bar moves it.
///
/// **The bar is the only way between pages** since the owner took the strip
/// and sub-nav away (15 Sep 2026). It sits above the router and follows a line
/// with `go('/management', extra: destination)`, which rebuilds the one screen
/// with that destination (`router.dart`) — the screen hears it in
/// `didUpdateWidget`. This is that rebuild, for a suite that mounts the screen
/// bare. Mounting the whole app in every pane suite was the alternative, and
/// would have made each of them a test of the router, the bar's overlay and the
/// macOS menu as well; `settings_bar_test.dart` already holds the drawn bar to
/// `managementBarFor`, line for line, and follows its lines through the app.
///
/// Construct inside a test: it registers its own teardown.
class BarRoute {
  BarRoute([ManagementPane? pane])
    : _at = ValueNotifier(ManagementDestination(pane: pane)) {
    addTearDown(_at.dispose);
  }

  final ValueNotifier<ManagementDestination> _at;

  /// The screen, standing wherever [go] last sent it.
  Widget screen({VoidCallback? onClose, VoidCallback? onReconfigure}) =>
      ValueListenableBuilder<ManagementDestination>(
        valueListenable: _at,
        builder: (context, to, child) => ManagementScreen(
          onClose: onClose ?? () {},
          onReconfigure: onReconfigure ?? () {},
          initialPane: to.pane,
          purchasingTab: to.purchasingTab,
          create: to.create,
          request: to.request,
        ),
      );

  /// A bar line's destination, followed.
  Future<void> go(WidgetTester tester, ManagementDestination to) async {
    _at.value = to;
    await tester.pumpAndSettle();
  }

  /// The bar line that opens [pane], followed — a fresh request, as every tap
  /// on the bar is, so asking for the page already showing still counts.
  Future<void> open(WidgetTester tester, ManagementPane pane) =>
      go(tester, ManagementDestination(pane: pane, request: Object()));
}
