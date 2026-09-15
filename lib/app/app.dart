import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:menu_bar/menu_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../domain/models/permissions.dart';
import '../core/ui/theme.dart';
import '../core/ui/tokens.dart';
import '../features/settings/about_dialog.dart';
import '../features/settings/printer_settings_dialog.dart';
import '../features/setup/presentation/force_reset_dialog.dart';
import '../features/admin/application/admin_session.dart';
import '../features/admin/presentation/admin_shortcut.dart';
import 'providers.dart';
import '../features/admin/presentation/management_screen.dart';
import 'router.dart';

class XorderPosApp extends ConsumerWidget {
  const XorderPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod providers are lazy, and the cloud sync loop must not be: a
    // till parked on the start screen still owes the platform its heartbeat
    // and still has to notice a config change — a PIN set in the dashboard,
    // a repriced menu. Watching it here is what makes it exist at all;
    // without this, the background sync only started once somebody visited
    // the sale screen, which is exactly backwards.
    ref.watch(cloudSyncProvider);
    final adminShortcut = ref.watch(adminModeSettingsProvider).shortcut;

    return MaterialApp.router(
      title: 'XOrder POS',
      // Text direction follows from this. Flutter reads the locale and
      // wraps the tree in the right `Directionality`, so there is no
      // separate RTL switch to forget to set.
      locale: ref.watch(localeProvider),
      debugShowCheckedModeBanner: false,
      // Two full themes rather than one palette. `themeMode` is what decides
      // between them, and a null brightness means the operator has not chosen
      // — so the till follows the machine, and changes with it at dusk.
      theme: buildPosTheme(PosPalette.light),
      darkTheme: buildPosTheme(PosPalette.dark),
      themeMode: switch (ref.watch(brightnessProvider)) {
        Brightness.light => ThemeMode.light,
        Brightness.dark => ThemeMode.dark,
        null => ThemeMode.system,
      },
      routerConfig: ref.watch(routerProvider),
      // Two hidden chords, registered at the ROOT, above the router, so they
      // work on every screen and survive the redirect that sends an
      // unconfigured terminal back to the wizard.
      //
      // **Admin Mode** — Ctrl+Shift+S unless this till was set otherwise
      // (System › Terminal). A hidden way in and nothing more: what it opens
      // is a username and PIN, and no pane renders before them. F8 used to
      // open the back office from anywhere, ungated, on the strength of the
      // screen "gating itself" — which it did only until a manager had used it
      // once, after which a locked till opened the staff pane for anybody.
      //
      // **The forced reset** — Ctrl+Shift+R. It owned Ctrl+Shift+S until Admin
      // Mode took it (owner decision, 12 Sep 2026), and stays a chord rather
      // than a button for the reason it always was one: it can discard an open
      // shift, so it is for somebody who knows it exists. On a till that is set
      // up it asks for a username and PIN holding `terminal.manage` first.
      builder: (context, child) => _menuBar(
        AppStrings.of(ref.watch(localeProvider)),
        CallbackShortcuts(
          bindings: {
            for (final activator in adminShortcutActivators(adminShortcut))
              activator: () => _openAdmin(ref),
            // Both chords, matching the welcome screen's existing convention:
            // Ctrl for the Windows tills this ships to, Cmd for macOS.
            const SingleActivator(
              LogicalKeyboardKey.keyR,
              control: true,
              shift: true,
            ): () =>
                _forceReset(ref),
            const SingleActivator(
              LogicalKeyboardKey.keyR,
              meta: true,
              shift: true,
            ): () =>
                _forceReset(ref),
          },
          // Root focus so the binding receives keys wherever focus currently
          // sits — key events bubble up to here from any focused field.
          child: Focus(
            autofocus: true,
            child: _settingsBar(child ?? const SizedBox()),
          ),
        ),
      ),
      localizationsDelegates: const [
        AppLocalizations(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }

  /// The native menu bar.
  ///
  /// `PlatformMenuBar` rather than an in-app menu widget or a package: on
  /// macOS this fills the REAL system menu bar, which costs a till zero screen
  /// space. A fullscreen point of sale cannot spare a row of chrome above the
  /// ticket, and a cashier has no use for a menu — this is for whoever is
  /// installing or supporting the machine.
  ///
  /// On every other platform it renders [child] and nothing else, by design.
  /// So the WINDOWS tills this ships to get no menu from this: the actions
  /// below stay reachable there through their keyboard chords, which is how
  /// they were reachable before. An in-app `MenuBar` is the Windows answer if
  /// one is wanted, and it is also built in — neither needs a package.
  ///
  /// **Built on macOS only.** The provided items below — About, Hide, Quit —
  /// exist only there, and Android throws the moment one is instantiated: the
  /// first frame on a tablet was a red error screen, not a till.
  ///
  /// The app and window menus are re-declared because `PlatformMenuBar` owns
  /// the whole bar once it exists: omitting them would take away Quit, Hide,
  /// Services and Minimise.
  Widget _menuBar(AppStrings strings, Widget child) =>
      defaultTargetPlatform != TargetPlatform.macOS
      ? child
      : PlatformMenuBar(
    menus: [
      // The product's own name, and so never translated.
      const PlatformMenu(
        label: 'XOrder POS',
        menus: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ],
      ),
      PlatformMenu(
        label: strings.windowMenu,
        menus: const [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.toggleFullScreen,
          ),
        ],
      ),
    ],
    child: child,
  );

  /// The in-app Settings bar.
  ///
  /// `menu_bar` draws this itself rather than handing it to the OS, which is
  /// the entire reason it is here: [PlatformMenuBar] above fills the real
  /// macOS menu bar and renders NOTHING anywhere else, so on the Windows tills
  /// this actually ships to those actions had no home but a keyboard chord.
  ///
  /// The split is by concern, not by duplication. The native bar keeps what
  /// belongs to the operating system — About, Hide, Quit, window management —
  /// and this keeps what belongs to the till. Nothing appears in both.
  Widget _settingsBar(Widget child) {
    // An Overlay of its own, because this sits ABOVE the router: `MenuBarWidget`
    // uses Material's `MenuBar`, which needs an Overlay ancestor to float its
    // submenus into, and the app's own Overlay lives BELOW here inside the
    // Navigator. Without this the bar throws "No Overlay widget found" on the
    // first frame and takes the whole app down with it.
    return Overlay(
      initialEntries: [
        OverlayEntry(
          // Everything this menu says is read INSIDE the entry, through a
          // Consumer of its own, and that is load-bearing rather than a matter
          // of taste. `initialEntries` is used ONCE — when the Overlay first
          // builds — and every entry constructed on a later build is discarded,
          // so a menu assembled outside it is frozen at the first frame for the
          // life of the process. The body still followed the theme and the
          // language, because those travel by inherited widget, which left this
          // menu as the only thing on screen describing a till that no longer
          // existed: "Switch to light", offered on a till already showing
          // light. The language item and Sync now were frozen the same way.
          //
          // [child] stays the first frame's, and that is fine: it is the
          // router's Navigator, which updates itself from below.
          builder: (_) => Consumer(
            builder: (context, ref, _) {
              final strings = AppStrings.of(ref.watch(localeProvider));
              final arabic = ref.watch(localeProvider).languageCode == 'ar';

              // What is on screen right now, which is not the same as what was
              // chosen: while following the machine the override is null and
              // says nothing about which way the toggle should go.
              final showing =
                  ref.watch(brightnessProvider) ??
                  MediaQuery.platformBrightnessOf(context);
              final dark = showing == Brightness.dark;

              final staff = ref.watch(signedInStaffProvider);
              final managesTerminal =
                  staff?.can(PosCapability.terminalManage) ?? false;

              // **No bar until somebody signs in.**
              //
              // A till parked on the start or lock screen is in front of
              // whoever walks up to it, so the whole bar — Settings and the
              // back-office menus alike — waits for a sign-in, and the back
              // office is not on this bar at all until somebody is in Admin
              // Mode. The way in is a hidden chord and a username and PIN.
              //
              // **Somebody in Admin Mode is somebody signed in.** Admin Mode
              // is not the till, so it can be entered with nobody signed in
              // there — and since 15 Sep 2026 its menus are the only way
              // between the back office's pages: the owner took away the
              // on-screen strip that also was. Hiding the bar here would leave
              // whoever is in Admin Mode on one page with nothing but Exit.
              //
              // Except while the till is not set up yet: the wizard has no
              // language step up front and relies on Settings' language
              // switch, and nobody can sign in to a till that has no staff.
              //
              // Hidden through `enabled` rather than by returning [child]
              // bare: that keeps the tree's shape, so signing in or out never
              // reparents the router's Navigator underneath it.
              final visible =
                  staff != null ||
                  ref.watch(adminSessionProvider) != null ||
                  !ref.watch(setupCompleteProvider);

              // **And not in front of the till.** The start and lock screens are
              // where somebody signs in to sell, so they stay clean even with a
              // name still signed in behind them; the bar arrives with the
              // till. Listened to through the router because this sits above
              // it and no route rebuilds it.
              final router = ref.watch(routerProvider);

              final menus = _managementMenus(ref, strings);
              final settingsLines = [
                for (final menu in menus)
                  if (menu.tab == BackOfficeTab.settings) ...menu.lines,
              ];
              // **One line per place.** Printer and About are the till's own
              // lines AND the back office's Settings items; offered both, the
              // menu would say each twice, a dialog and a page. So while the
              // back office offers the page, the till's line steps aside, and
              // it is back the moment Admin Mode ends — the till's dialog is
              // the only way to either outside it. Read off the lines, not
              // off a capability: the page follows whoever is in Admin Mode,
              // the till's line whoever is signed in at the till, and those
              // can be two people.
              final inBackOffice = {for (final line in settingsLines) line.pane};
              final tillPrinter =
                  managesTerminal &&
                  !inBackOffice.contains(ManagementPane.printer);
              final tillAbout = !inBackOffice.contains(ManagementPane.about);
              return _AfterEachRoute(
                listenable: router.routerDelegate,
                builder: (context) => MenuBarWidget(
                  enabled: visible &&
                      !_beforeTheTill(
                        router.routerDelegate.currentConfiguration.uri.path,
                      ),
                  barButtons: [
                    // **The back office, in the window's own bar: the owner's
                    // map (14 Sep 2026), one menu per tab.**
                    //
                    // Inside Admin Mode only. The till's bar and the start
                    // screen each had a Management button too — the same door
                    // twice, three times on the start screen counting this bar —
                    // and both are gone.
                    //
                    // The map's ten words, in its order, each listing that
                    // tab's items. BO-1 had folded these into one Back office
                    // menu, a line per tab; the owner reversed that, then on
                    // 15 Sep 2026 took away the on-screen strip and sub-nav
                    // that said the same — so these menus are the back
                    // office's only navigation, and every page anybody holds
                    // is a line here, bar the four behind Settings' side nav.
                    // Home comes first, a button straight to the landing
                    // rather than a menu: its lines were Home again and Exit,
                    // which the header's button already is, and the owner
                    // called both duplication (15 Sep 2026). Under المشتريات, "new
                    // order", "enter an invoice" and "new supplier" still start
                    // one straight away; on a cloud till Inventory and
                    // Purchasing each hold one line saying where they went.
                    // `managementBarFor` decides all of it, and Settings' items
                    // join the till's own Settings menu below rather than
                    // making a second menu of the same name.
                    //
                    // Absent entirely for somebody who cannot open the back
                    // office: a greyed-out menu is a permanent advertisement for
                    // a door they will never be given.
                    for (final menu in menus)
                      if (menu.tab != BackOfficeTab.settings)
                        if (menu.direct)
                          _DirectBarButton(
                            () => _openFromBar(ref, menu.lines.single),
                            text: Text(menu.label),
                          )
                        else
                          BarButton(
                            text: Text(menu.label),
                            submenu: SubMenu(
                              menuItems: [
                                for (final entry in menu.lines) ...[
                                  if (entry.divider) const MenuDivider(),
                                  MenuButton(
                                    text: Text(entry.label),
                                    onTap: () => _openFromBar(ref, entry),
                                  ),
                                ],
                              ],
                            ),
                          ),
                    BarButton(
                      text: Text(strings.settings),
                      submenu: SubMenu(
                        menuItems: [
                          // Only where there is a platform to sync with. On an
                          // offline terminal `cloudSyncProvider` is null and this
                          // item did nothing at all when tapped — an entry that
                          // silently no-ops teaches an operator that the menu is
                          // unreliable, which is worse than not offering it.
                          if (ref.watch(cloudSyncProvider) case final cloud?)
                            MenuButton(
                              text: Text(strings.syncNow),
                              icon: const Icon(Icons.sync, size: 16),
                              onTap: cloud.kick,
                            ),
                          // No door to the back office here: the hidden chord
                          // is the way in, and "Staff & accounts" and
                          // "Management" here were once the same door twice
                          // more. Inside Admin Mode, the back office's Settings
                          // items are listed at the foot of this menu instead.
                          //
                          // Every sale and its receipt, from wherever the till is
                          // — and back there on close, not to the sale screen.
                          MenuButton(
                            text: Text(strings.settingsOrders),
                            icon: const Icon(Icons.receipt_long_outlined, size: 16),
                            onTap: () {
                              final router = ref.read(routerProvider);
                              final here = router
                                  .routerDelegate
                                  .currentConfiguration
                                  .uri
                                  .path;
                              router.go(PosRoutes.orders, extra: here);
                            },
                          ),
                          // Configuring the machine is not a cashier's job, and
                          // both of these reconfigure it.
                          if (tillPrinter)
                            MenuButton(
                              text: Text(strings.settingsPrinter),
                              icon: const Icon(Icons.print_outlined, size: 16),
                              onTap: () {
                                // The bar sits above the router; its dialogs are
                                // shown from inside the navigator, as reset's is.
                                final context = rootNavigatorKey.currentContext;
                                if (context != null) {
                                  PrinterSettingsDialog.show(context);
                                }
                              },
                            ),
                          const MenuDivider(),
                          // Switching language rebuilds the whole tree, including this
                          // bar — the label flips with it, which is why it reads as the
                          // language you would GET rather than the one you are in.
                          MenuButton(
                            text: Text(
                              arabic
                                  ? const EnStrings().languageName
                                  : const ArStrings().languageName,
                            ),
                            icon: const Icon(Icons.translate, size: 16),
                            onTap: () => ref
                                .read(localeProvider.notifier)
                                .apply(arabic ? 'en' : 'ar'),
                          ),
                          // Reads as the theme you would GET, for the same reason the
                          // language item does.
                          MenuButton(
                            text: Text(
                              dark ? strings.switchToLight : strings.switchToDark,
                            ),
                            icon: Icon(
                              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                              size: 16,
                            ),
                            onTap: () =>
                                ref.read(brightnessProvider.notifier).toggle(showing),
                          ),
                          const MenuDivider(),
                          // Handing the till over. The lock screen signs in
                          // whoever's PIN it is, so locking already switches the
                          // operator — but nobody hands a till to a colleague by
                          // reaching for a control called Lock. Same door, named
                          // for what people are actually doing when they use it.
                          MenuButton(
                            text: Text(strings.switchUser),
                            icon: const Icon(Icons.switch_account, size: 16),
                            onTap: () =>
                                ref.read(routerProvider).go(PosRoutes.lock),
                          ),
                          // Not above nothing: with About the back office's
                          // and no reset to offer, the foot's own divider is
                          // the next thing drawn.
                          if (tillAbout || managesTerminal) const MenuDivider(),
                          if (tillAbout)
                            MenuButton(
                              text: Text(strings.settingsAbout),
                              icon: const Icon(Icons.info_outline, size: 16),
                              onTap: () {
                                final context = rootNavigatorKey.currentContext;
                                if (context != null) {
                                  PosAboutDialog.show(context);
                                }
                              },
                            ),
                          if (managesTerminal)
                            MenuButton(
                              text: Text(strings.forceResetConfirm),
                              icon: const Icon(Icons.restart_alt, size: 16),
                              // Printed, not bound: the chord above is what fires.
                              // Showing it here is how an installer discovers a
                              // shortcut nobody would guess.
                              shortcutText: '⇧⌘R',
                              onTap: () => _forceReset(ref),
                            ),
                          // The back office's Settings items, in Admin Mode and
                          // only those this person has, in the map's order —
                          // all six, printer and about among them, which is
                          // why the till's two lines above step aside. Beneath
                          // the till's own rather than woven into them: the
                          // rest of the till's lines are acts (sync, switch
                          // language, lock for somebody else) or `/orders`,
                          // not places in the back office. Switch user is not
                          // the map's User: it hands the till over; User is
                          // who is in Admin Mode and the way out of it.
                          if (settingsLines.isNotEmpty) const MenuDivider(),
                          for (final entry in settingsLines) ...[
                            if (entry.divider) const MenuDivider(),
                            MenuButton(
                              text: Text(entry.label),
                              onTap: () => _openFromBar(ref, entry),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  child: child,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The screens in front of the till: nobody has signed in to sell there yet,
  /// whatever the back office remembers.
  static bool _beforeTheTill(String path) =>
      path == PosRoutes.start || path == PosRoutes.lock;

  /// The bar's back-office menus.
  ///
  /// Asks `managementBarFor` rather than listing panes, for the reason
  /// `backOfficeTabsFor` exists beneath it: the screen checks every request
  /// against that rule, so a menu offering Purchasing to somebody it hides
  /// Purchasing from would open on Home instead, and read as a broken menu.
  List<ManagementBarMenu> _managementMenus(
    WidgetRef ref,
    AppStrings strings,
  ) {
    // Only inside Admin Mode, and for whoever is in it. Outside, the bar offers
    // no back office at all — not a door, not a greyed word: the way in is the
    // hidden shortcut, and a menu item leading to it would be a second, visible
    // one. That includes a till being set up, which once offered Management
    // here: there is nobody to sign in and nothing yet to administer. Inside,
    // the tabs are the admin's, not the till operator's.
    final admin = ref.watch(adminSessionProvider)?.staff;
    if (admin == null) return const [];

    return managementBarFor(
      strings,
      admin: admin,
      authorsItsOwnCatalogue: ref.watch(catalogAdminRepositoryProvider) != null,
    );
  }

  /// A bar line, followed. Through the route, so somebody no longer in Admin
  /// Mode meets its door first, and lands on the pane the line named.
  ///
  /// **Carrying the way back.** A line names its pane and nothing else, and
  /// the route's `extra` is the whole of what the back office remembers — so
  /// going there with the line's destination alone forgot where the chord
  /// was pressed, and Exit landed on the start screen. Remembering it in the admin session instead was the
  /// alternative, and would have been a second copy of the route's answer
  /// that the start screen's door and the router's own builder never read.
  void _openFromBar(WidgetRef ref, ManagementBarEntry entry) => ref
      .read(routerProvider)
      .go(
        PosRoutes.management,
        extra: entry.open().returningTo(_cameFrom(ref)),
      );

  /// Where the back office goes back to: the route it was entered from, as
  /// the destination that opened it recorded — or, from anywhere else, here.
  String? _cameFrom(WidgetRef ref) {
    final here = ref.read(routerProvider).routerDelegate.currentConfiguration;
    if (here.uri.path != PosRoutes.management) return here.uri.path;
    return switch (here.extra) {
      final ManagementDestination d => d.returnTo,
      _ => null,
    };
  }

  /// Into Admin Mode, from wherever the till is — and back there on the way
  /// out.
  ///
  /// Not on a till that is not set up: there is nobody to sign in and nothing
  /// to administer, and the welcome screen owns Ctrl+Shift+S there (it opens
  /// the wizard). Not twice: the chord inside Admin Mode is not a second door.
  ///
  /// No pane named: the door lands on the first tab that holds one, which is
  /// Home once BO-4 builds it.
  void _openAdmin(WidgetRef ref) {
    if (!ref.read(setupCompleteProvider)) return;
    final router = ref.read(routerProvider);
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here == PosRoutes.management) return;
    router.go(
      PosRoutes.management,
      extra: ManagementDestination(returnTo: here),
    );
  }

  /// Guarded so a second Cmd+Shift+R while the dialog is open cannot stack a
  /// second one on top of it.
  static bool _resetting = false;

  Future<void> _forceReset(WidgetRef ref) async {
    if (_resetting) return;
    // The binding sits above the router, so its own context has no Navigator.
    // The dialog has to be shown from inside one.
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    _resetting = true;
    try {
      final wiped = await showForceResetDialog(context, ref);
      if (!wiped) return;
      // The router's own redirect takes an unconfigured terminal to the
      // wizard, so the reset alone is the navigation — routing by hand here
      // would race it.
      ref.read(routerProvider).go(PosRoutes.start);
    } finally {
      _resetting = false;
    }
  }
}

/// A word in the bar that is a button, not a menu: Home's (see
/// `managementBarFor`).
///
/// **A subclass, because the package will not say it.** `MenuBarWidget` takes
/// only [BarButton]s, and [BarButton] demands a [SubMenu] — yet it draws any
/// entry whose `submenu` is null as a `MenuItemButton`, which Flutter's
/// `MenuBar` holds at the top level as readily as a menu. So the getters say
/// what the constructor would not. The alternatives were a menu of one line
/// repeating its own title — the duplication the owner asked to be rid of —
/// or dropping `menu_bar` for a hand-built `MenuBar`, which would re-home
/// every line of the till's Settings menu to change one word. If an upgrade
/// of the package stops honouring the getters, `settings_bar_test.dart` finds
/// Home a menu again and fails.
class _DirectBarButton extends BarButton {
  _DirectBarButton(this._onTap, {required super.text})
    : super(submenu: const SubMenu(menuItems: []));

  final VoidCallback _onTap;

  @override
  SubMenu? get submenu => null;

  @override
  VoidCallback? get onTap => _onTap;
}

/// Rebuilds [builder] whenever the router moves — a frame late when the move is
/// heard mid-build.
///
/// A plain `ListenableBuilder` is not enough: this sits ABOVE the router, and
/// the router announces its very first route while it is itself being built,
/// below this. Marking an ancestor dirty mid-build is an assertion, and it took
/// every frame down with it, so a change heard then waits for the next frame.
class _AfterEachRoute extends StatefulWidget {
  const _AfterEachRoute({required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<_AfterEachRoute> createState() => _AfterEachRouteState();
}

class _AfterEachRouteState extends State<_AfterEachRoute> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(_AfterEachRoute old) {
    super.didUpdateWidget(old);
    if (old.listenable != widget.listenable) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
