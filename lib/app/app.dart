import 'package:flutter/material.dart';
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
      // Cmd+Shift+S — delete this machine's terminal setup and run the
      // wizard again. Registered at the ROOT, above the router, for two
      // reasons: it has to work on every screen (a till that needs
      // re-pairing is usually parked somewhere with no reset link), and it
      // has to survive the redirect that sends an unconfigured terminal
      // back to the wizard.
      //
      // A shortcut rather than a button, deliberately. This can discard an
      // open shift, so it should be reachable by someone who knows it
      // exists and not by someone hunting around the screen. The dialog
      // states what it will cost before anything is deleted.
      builder: (context, child) => _menuBar(
        AppStrings.of(ref.watch(localeProvider)),
        CallbackShortcuts(
          bindings: {
            // Both chords, matching the welcome screen's existing convention:
            // Ctrl for the Windows tills this ships to, Cmd for macOS.
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              control: true,
              shift: true,
            ): () =>
                _forceReset(ref),
            const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ): () =>
                _forceReset(ref),
            // The back office, from anywhere — the till, the start screen, a
            // floor plan, a pane already open. An F-key rather than a chord
            // because that is the vocabulary of the rest of this product's
            // keyboard (F2 search, F7 open orders, F10 drawer) and of the
            // keyboards it ships on, and because back-office work is something
            // a manager does twenty times an evening between orders.
            //
            // Safe to bind globally and ungated: the pane it opens gates
            // itself, with a PIN pad for somebody who has not signed in and a
            // refusal by name for somebody who may not be there.
            const SingleActivator(LogicalKeyboardKey.f8): () =>
                ref.read(routerProvider).go(PosRoutes.management),
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
  /// The app and window menus are re-declared because `PlatformMenuBar` owns
  /// the whole bar once it exists: omitting them would take away Quit, Hide,
  /// Services and Minimise.
  Widget _menuBar(AppStrings strings, Widget child) => PlatformMenuBar(
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

              return MenuBarWidget(
                barButtons: [
                  // **The back office, in the window's own bar.**
                  //
                  // The only door, with F8. The till's bar and the start
                  // screen each had a Management button too — the same door
                  // twice, three times on the start screen counting this bar —
                  // and both are gone. A menu bar is the one surface that is
                  // always there, so the panes hang off it, grouped by area as
                  // the back office's own tabs are, because "where do I change
                  // the VAT rate" is answered by *Money* long before it is
                  // answered by reading thirteen pane names.
                  //
                  // Absent entirely for somebody who cannot open the back
                  // office: a greyed-out menu is a permanent advertisement for
                  // a door they will never be given.
                  // **One button per area of the back office.**
                  //
                  // Thirteen panes under a single word called Management is a
                  // list somebody reads rather than a menu somebody uses: the
                  // question is never "what is in the back office", it is "where
                  // do I enter this invoice" — and the answer to that is
                  // Purchasing, which is now a word in the bar rather than the
                  // fifth line of a scrolling list.
                  for (final (label, entries) in _managementMenus(ref, strings))
                    BarButton(
                      text: Text(label),
                      submenu: SubMenu(
                        menuItems: [
                          // The pane — or, where a pane is really several
                          // things, each of them and the "new" that starts
                          // one. Under المشتريات that is orders, invoices,
                          // payments and suppliers, not one word that opens a
                          // screen and makes you find them again. On a cloud
                          // till it is one line saying where they went —
                          // `managementBarFor` decides which.
                          for (final entry in entries) ...[
                            if (entry.divider) const MenuDivider(),
                            MenuButton(
                              text: Text(entry.label),
                              // Printed, not bound: the global binding is
                              // what fires, and it lands on Staff — so the
                              // key is named on the item it opens.
                              shortcutText:
                                  entry.pane == ManagementPane.staff &&
                                      entry.first
                                  ? 'F8'
                                  : null,
                              onTap: () => ref
                                  .read(routerProvider)
                                  .go(
                                    PosRoutes.management,
                                    extra: entry.open(),
                                  ),
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
                        // Not the back office: the bar's own Management menu
                        // opens it, and "Staff & accounts" and "Management"
                        // here were the same door twice more.
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
                        const MenuDivider(),
                        MenuButton(
                          text: Text(strings.settingsAbout),
                          icon: const Icon(Icons.info_outline, size: 16),
                          onTap: () {
                            final context = rootNavigatorKey.currentContext;
                            if (context != null) PosAboutDialog.show(context);
                          },
                        ),
                        MenuButton(
                          text: Text(strings.forceResetConfirm),
                          icon: const Icon(Icons.restart_alt, size: 16),
                          // Printed, not bound: the chord above is what fires. Showing
                          // it here is how an installer discovers a shortcut nobody
                          // would guess, without making a destructive action something
                          // a cashier finds by wandering the menus.
                          shortcutText: '⇧⌘S',
                          onTap: () => _forceReset(ref),
                        ),
                      ],
                    ),
                  ),
                ],
                child: child,
              );
            },
          ),
        ),
      ],
    );
  }

  /// The bar's back-office buttons: one per area, each with its own lines.
  ///
  /// Asks `managementBarFor` rather than listing panes, for the reason
  /// `managementAreasFor` exists beneath it: a menu offering Purchasing to
  /// somebody the rail hides it from would take them to a screen that refuses
  /// everything.
  List<(String, List<ManagementBarEntry>)> _managementMenus(
    WidgetRef ref,
    AppStrings strings,
  ) {
    final admin = ref.watch(signedInStaffProvider);

    // Nobody signed in is not nobody permitted. Before a shift — and after any
    // restart — there is no signed-in staff at all, and the management screen's
    // own PIN pad is what signs somebody in. Which areas an unknown person has
    // is not a question this bar can answer, so it offers the one door under
    // the one word: Management, opening on Staff, which opens locked and asks.
    if (admin == null) {
      return [
        (
          strings.management,
          [
            for (final (i, (label, open, _)) in managementMenuEntries(
              strings,
              ManagementPane.staff,
            ).indexed)
              (
                pane: ManagementPane.staff,
                first: i == 0,
                label: label,
                open: open,
                divider: false,
              ),
          ],
        ),
      ];
    }
    if (!admin.can(PosCapability.staffManage)) {
      return const [];
    }

    return [
      for (final (area, entries) in managementBarFor(
        strings,
        admin: admin,
        authorsItsOwnCatalogue:
            ref.watch(catalogAdminRepositoryProvider) != null,
      ))
        (managementAreaName(strings, area), entries),
    ];
  }

  /// Guarded so a second Cmd+Shift+S while the dialog is open cannot stack a
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
