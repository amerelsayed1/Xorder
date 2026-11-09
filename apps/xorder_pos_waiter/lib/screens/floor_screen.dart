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
/// tables). Read again every few seconds while on screen, the same cadence
/// the tills use with each other (XORD-044).
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
            Center(child: Padding(
              padding: const EdgeInsetsDirectional.only(end: WaiterSpace.sm),
              child: Text(staff.name, style: const TextStyle(color: WaiterColors.body)),
            )),
          const LanguageButton(),
          IconButton(
            tooltip: s.signOutAction,
            onPressed: ref.read(waiterAppProvider.notifier).signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_error != null)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(WaiterSpace.md), child: ErrorNote(_error!))),
            if (floor == null && _error == null)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (floor != null && floor.tables.isEmpty)
              SliverFillRemaining(child: Center(child: Text(s.noTables, style: const TextStyle(color: WaiterColors.muted))))
            else if (floor != null)
              SliverPadding(
                padding: const EdgeInsets.all(WaiterSpace.md),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 112,
                    crossAxisSpacing: WaiterSpace.sm,
                    mainAxisSpacing: WaiterSpace.sm,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _TableTile(table: floor.tables[i], currency: floor.currency, onTap: _open),
                    childCount: floor.tables.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableTile extends StatelessWidget {
  const _TableTile({required this.table, required this.currency, required this.onTap});

  final WaiterTable table;
  final WaiterCurrency currency;
  final ValueChanged<WaiterTable> onTap;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final (fill, edge, label) = switch (table.state) {
      WaiterTableState.free => (WaiterColors.surface, const BorderSide(color: WaiterColors.lineStrong), s.tableFree),
      WaiterTableState.open => (WaiterColors.accentSoft, const BorderSide(color: WaiterColors.accent, width: 2), s.tableOpen),
      WaiterTableState.billAsked => (WaiterColors.dangerSoft, const BorderSide(color: WaiterColors.danger, width: 2), s.tableBillAsked),
    };
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
                children: [
                  Expanded(
                    child: Text(table.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: WaiterColors.ink)),
                  ),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WaiterColors.body)),
                ],
              ),
              if (table.area != null)
                Text(table.area!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: WaiterColors.muted)),
              const Spacer(),
              if (table.state != WaiterTableState.free) ...[
                Text(s.items(table.items), style: const TextStyle(fontSize: 12, color: WaiterColors.body)),
                Text(moneyText(currency, table.totalMinor, arabic: s.arabic), style: waiterMono(size: 15)),
              ] else if (table.seats != null)
                Text(s.guests(table.seats!), style: const TextStyle(fontSize: 12, color: WaiterColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
