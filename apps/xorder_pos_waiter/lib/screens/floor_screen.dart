import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'check_screen.dart';
import 'widgets.dart';

/// Every table of the branch, as the till holds them (W5: all waiters see all
/// tables), grouped by dining area under a summary strip (design §5.3). Read
/// again every few seconds while on screen, the same cadence the tills use
/// with each other (XORD-044); a failed read keeps the last floor on screen,
/// because a stale floor beats an empty one.
class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({super.key, this.refreshEvery = const Duration(seconds: 5)});

  final Duration refreshEvery;

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  WaiterFloor? _floor;
  String? _error;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(widget.refreshEvery, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final app = ref.read(waiterAppProvider.notifier);
    try {
      final floor = await app.client.floor();
      if (mounted) {
        setState(() {
          _floor = floor;
          _error = null;
        });
      }
    } on WaiterLinkFailure catch (e) {
      if (await app.absorb(e)) return;
      if (mounted) setState(() => _error = WaiterStrings.of(context).failure(e));
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(WaiterTable table) async {
    _timer?.cancel();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CheckScreen(table: table)));
    if (!mounted) return;
    unawaited(_load());
    _timer = Timer.periodic(widget.refreshEvery, (_) => unawaited(_load()));
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final staff = ref.watch(waiterAppProvider.select((a) => a.staff));
    final floor = _floor;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.floorTitle),
        actions: [
          if (staff != null)
            Center(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: WaiterSpace.sm),
                child: Text(staff.name, style: WaiterText.ui(color: WaiterColors.body, weight: FontWeight.w500)),
              ),
            ),
          IconButton(
            tooltip: s.signOutAction,
            onPressed: ref.read(waiterAppProvider.notifier).signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: WaiterColors.ink,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(padding: const EdgeInsets.fromLTRB(WaiterSpace.md, WaiterSpace.md, WaiterSpace.md, 0), child: ErrorNote(_error!)),
              ),
            if (floor == null && _error == null)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (floor != null && floor.tables.isEmpty)
              SliverFillRemaining(child: EmptyState(s.noTables))
            else if (floor != null) ...[
              SliverToBoxAdapter(child: _SummaryStrip(floor: floor)),
              ..._areaSlivers(floor, s),
              const SliverToBoxAdapter(child: SizedBox(height: WaiterSpace.lg)),
            ],
          ],
        ),
      ),
    );
  }

  /// One grid per dining area, in the till's order, each under its header.
  /// A floor with a single group — every table in one area, or none in any —
  /// has no headers to read past.
  List<Widget> _areaSlivers(WaiterFloor floor, WaiterStrings s) {
    final groups = <String?, List<WaiterTable>>{};
    for (final t in floor.tables) {
      (groups[t.area] ??= []).add(t);
    }
    final grouped = groups.length > 1;
    return [
      for (final entry in groups.entries) ...[
        if (grouped)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(WaiterSpace.lg, WaiterSpace.sm, WaiterSpace.lg, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(entry.key ?? s.noArea, count: entry.value.length),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(WaiterSpace.md, WaiterSpace.sm, WaiterSpace.md, WaiterSpace.sm),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: WaiterSpace.tableTileMaxExtent,
              mainAxisExtent: WaiterSpace.tableTile,
              crossAxisSpacing: WaiterSpace.tableGutter,
              mainAxisSpacing: WaiterSpace.tableGutter,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _TableTile(
                table: entry.value[i],
                currency: floor.currency,
                showArea: !grouped,
                onTap: _open,
              ),
              childCount: entry.value.length,
            ),
          ),
        ),
      ],
    ];
  }
}

/// "3 open · 1 paying · 6 free": the glance before the grid.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.floor});
  final WaiterFloor floor;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    var open = 0, paying = 0, free = 0;
    for (final t in floor.tables) {
      switch (t.state) {
        case WaiterTableState.free:
          free++;
        case WaiterTableState.open:
          open++;
        case WaiterTableState.billAsked:
          paying++;
      }
    }
    return Container(
      key: const Key('floor-summary'),
      padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.lg, vertical: WaiterSpace.s10),
      decoration: const BoxDecoration(
        color: WaiterColors.surface,
        border: Border(bottom: BorderSide(color: WaiterColors.line)),
      ),
      child: Row(
        children: [
          if (paying > 0) ...[
            Container(width: 8, height: 8, color: WaiterColors.danger),
            const SizedBox(width: WaiterSpace.sm),
          ],
          Expanded(
            child: Text(
              s.floorSummary(open: open, paying: paying, free: free),
              style: WaiterText.meta(color: paying > 0 ? WaiterColors.ink : WaiterColors.body),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.currency, required this.showArea, required this.onTap});

  final WaiterTable table;
  final WaiterCurrency currency;
  final bool showArea;
  final ValueChanged<WaiterTable> onTap;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final (fill, edge) = switch (table.state) {
      WaiterTableState.free => (WaiterColors.surface, const BorderSide(color: WaiterColors.lineStrong)),
      WaiterTableState.open => (WaiterColors.accentSoft, const BorderSide(color: WaiterColors.accent, width: 2)),
      WaiterTableState.billAsked => (WaiterColors.dangerSoft, const BorderSide(color: WaiterColors.danger, width: 2)),
    };
    final open = table.state != WaiterTableState.free;
    return Material(
      color: fill,
      shape: Border.fromBorderSide(edge),
      child: InkWell(
        key: Key('table-${table.id}'),
        onTap: () => onTap(table),
        child: Padding(
          padding: const EdgeInsets.all(WaiterSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(table.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: WaiterText.tableLabel()),
                  ),
                  StateBadge(table.state),
                ],
              ),
              if (showArea && table.area != null)
                Text(table.area!, maxLines: 1, overflow: TextOverflow.ellipsis, style: WaiterText.meta()),
              const Spacer(),
              if (open) ...[
                Text(
                  dotJoin([s.items(table.items), if (table.guests != null) s.guests(table.guests!)]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WaiterText.meta(color: WaiterColors.body),
                ),
                MoneyText(currency, table.totalMinor, style: WaiterText.price()),
              ]
              else if (table.seats != null)
                Text(s.guests(table.seats!), style: WaiterText.meta()),
            ],
          ),
        ),
      ),
    );
  }
}
