import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../domain/models/order_type_config.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import '../../../domain/models/ticket.dart';
import '../../../domain/services/order_type_entitlement.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';
import 'order_type_dialog.dart';

/// What each kind of order requires (§31).
///
/// **The pane that deleted a comparison.** `type == OrderType.dineIn` used to
/// appear in the router, the cart panel and the ticket engine, and in all three
/// what it meant was *"does this kind of order have a table"*. Migration 25 made
/// that a row; this is where a business finally sets it.
///
/// Four rows and no "new" button. The codes are an enum and every place that
/// renders an order type reads its name off that enum, so a fifth would have
/// nowhere to appear — see `OrderTypeConfig`. What a business wants here is its
/// own words for the four, and to turn off the ones it does not sell.
class ManagementOrderTypesPane extends ConsumerStatefulWidget {
  const ManagementOrderTypesPane({required this.admin, super.key});

  final PosStaff admin;

  @override
  ConsumerState<ManagementOrderTypesPane> createState() =>
      _ManagementOrderTypesPaneState();
}

class _ManagementOrderTypesPaneState
    extends ConsumerState<ManagementOrderTypesPane> {
  bool _busy = false;
  String? _note;

  /// What the licence covers, or null when it says nothing about order types.
  Set<OrderType>? get _entitled {
    final features = ref.read(licenceClaimsProvider).valueOrNull?.features;
    return features == null
        ? null
        : OrderTypeEntitlement.fromFeatures(features);
  }

  Future<void> _edit(OrderTypeConfig config) async {
    final edited = await OrderTypeDialog.show(
      context,
      config: config,
      languages: ref.read(contentLanguagesNowProvider),
    );
    if (edited == null || !mounted) return;

    await _save(edited);
  }

  /// Turn one on or off without opening it.
  ///
  /// It was always possible — the editor has the switch — and that is one tap
  /// too deep for the thing a business changes most: Ramadan starts and
  /// delivery goes on, the dining room closes for a refit and seating goes off.
  /// A pane you have to open a row inside to answer "what do we sell today"
  /// reads as a pane that cannot answer it.
  Future<void> _setActive(OrderTypeConfig config, bool active) =>
      _save(OrderTypeConfig(
        type: config.type,
        nameEn: config.nameEn,
        nameAr: config.nameAr,
        requiresTable: config.requiresTable,
        requiresCustomer: config.requiresCustomer,
        requiresAddress: config.requiresAddress,
        isActive: active,
        sortOrder: config.sortOrder,
      ));

  Future<void> _save(OrderTypeConfig edited) async {
    final repository = ref.read(catalogAdminRepositoryProvider);
    if (repository == null) return;

    setState(() {
      _busy = true;
      _note = null;
    });
    final result = await repository.saveOrderType(
      edited,
      by: widget.admin,
      entitled: _entitled,
    );
    if (!mounted) return;

    setState(() {
      _busy = false;
      _note = result.succeeded
          ? null
          : AdminText.refusal(context.strings, result.refusal!);
    });

    // The router reads `orderTypeRulesProvider` to decide whether to offer a
    // floor plan at all, and the cart reads it per ticket. Without the
    // invalidation a manager who turns seating on gets it after a restart.
    if (result.succeeded) {
      ref
        ..invalidate(orderTypeConfigProvider)
        ..invalidate(orderTypesAllProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    // Two things must hold: this till authors its own catalogue (not a cloud
    // till, whose types come from the platform), and the person may choose
    // order types at all (XORD-002).
    final platformOwned = ref.watch(catalogAdminRepositoryProvider) == null;
    final mayChoose = widget.admin.can(PosCapability.orderTypesManage);
    final authors = !platformOwned && mayChoose;
    final entitled = OrderTypeEntitlement.fromFeatures(
      ref.watch(licenceClaimsProvider).valueOrNull?.features ?? const {},
    );

    return ListView(
      padding: const EdgeInsets.all(PosSpace.xl),
      children: [
        if (platformOwned) ...[
          PlatformOwnedNotice(text: strings.orderTypesComeFromPlatform),
          const SizedBox(height: PosSpace.xl),
        ] else if (!mayChoose) ...[
          PlatformOwnedNotice(text: strings.orderTypesNeedPermission),
          const SizedBox(height: PosSpace.xl),
        ],
        PaneSection(title: strings.orderTypes, hint: strings.orderTypesHint),
        ...ref
            .watch(orderTypesAllProvider)
            .when(
              loading: () => const [SizedBox(height: 40)],
              error: (error, _) => [
                Text(
                  '$error',
                  style: PosText.ui(size: 13, color: context.pos.danger),
                ),
              ],
              data: (types) => [
                for (final config in types)
                  // A type the licence does not include and that is off is not
                  // listed at all: there is nothing to do with it, and a row
                  // that can never be switched on is a row that invites asking
                  // why (XORD-002 — hide what is unavailable).
                  if (entitled == null ||
                      entitled.contains(config.type) ||
                      config.isActive)
                    _OrderTypeRow(
                      config: config,
                      onEdit: authors && !_busy ? () => _edit(config) : null,
                      onActive: authors && !_busy
                          ? (active) => _setActive(config, active)
                          : null,
                    ),
              ],
            ),
        if (_note != null) ...[
          const SizedBox(height: PosSpace.md),
          Text(
            _note!,
            style: PosText.ui(size: 12.5, color: context.pos.danger),
          ),
        ],
      ],
    );
  }
}

/// One order type, with the requirements that have consequences.
class _OrderTypeRow extends StatelessWidget {
  const _OrderTypeRow({
    required this.config,
    required this.onEdit,
    required this.onActive,
  });

  final OrderTypeConfig config;
  final VoidCallback? onEdit;

  /// Null while the pane is saving, or on a terminal whose catalogue belongs to
  /// the platform — the same rule that greys the row's editor.
  final ValueChanged<bool>? onActive;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    /// Only the requirements that are on. A row listing all three with two
    /// crossed out is a row nobody can read at a glance.
    final requires = [
      if (config.requiresTable) strings.orderTypeChipTable,
      if (config.requiresCustomer) strings.orderTypeChipCustomer,
      if (config.requiresAddress) strings.orderTypeChipAddress,
    ];

    return InkWell(
      onTap: onEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PosSpace.md),
        decoration: BoxDecoration(
          border: BorderDirectional(bottom: palette.hairline),
        ),
        child: Opacity(
          // A type that is off stays listed, greyed. It has to: turning it back
          // on is the only reason somebody opens this pane twice.
          opacity: config.isActive ? 1 : 0.5,
          child: Row(
            children: [
              SizedBox(
                width: 160,
                child: Text(
                  config.displayName(strings.languageCode),
                  style: PosText.ui(size: 13.5, color: palette.ink),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: PosSpace.xs,
                  runSpacing: 2,
                  children: [
                    for (final label in requires)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: PosSpace.sm,
                          vertical: 2,
                        ),
                        color: palette.chipBg,
                        child: Text(
                          label,
                          style: PosText.ui(
                            size: 10.5,
                            weight: FontWeight.w700,
                            color: palette.chipText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (!config.isActive)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: PosSpace.sm),
                  child: Text(
                    strings.orderTypeNotOffered,
                    style: PosText.ui(size: 11.5, color: palette.muted),
                  ),
                ),
              // Outside the Opacity above would be tidier; inside is correct.
              // A switch at full strength on a row that is greyed out reads as
              // the one thing still working on a broken row, when it is the
              // control that says WHY the row is grey.
              Switch(
                key: Key('order-type-active-${config.type.wire}'),
                value: config.isActive,
                onChanged: onActive,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
