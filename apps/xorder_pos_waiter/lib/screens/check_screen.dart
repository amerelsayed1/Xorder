import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'item_sheet.dart';
import 'widgets.dart';

/// One table's check: the menu to add from, the lines, and "send to kitchen".
///
/// Every tap is one request: the till applies it with its own ticket rules and
/// sends back the check it now holds, priced. A table changed on another
/// device meanwhile comes back as the current check and the waiter redoes the
/// change (XORD-044) — nothing is merged behind their back.
class CheckScreen extends ConsumerStatefulWidget {
  const CheckScreen({required this.table, super.key});

  final WaiterTable table;

  @override
  ConsumerState<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends ConsumerState<CheckScreen> {
  WaiterCheck? _check;
  String? _error;
  bool _busy = false;
  int? _category;

  WaiterLinkClient get _client => ref.read(waiterAppProvider.notifier).client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final check = await _client.check(widget.table.id);
      if (mounted) {
        setState(() {
          _check = check;
          _error = null;
        });
      }
    } on WaiterLinkFailure catch (e) {
      await _fail(e);
    }
  }

  Future<void> _fail(WaiterLinkFailure e) async {
    final app = ref.read(waiterAppProvider.notifier);
    if (await app.absorb(e)) {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    if (!mounted) return;
    final s = WaiterStrings.of(context);
    if (_check == null) {
      setState(() => _error = s.failure(e));
    } else {
      _say(s.failure(e), danger: true);
    }
  }

  void _say(String message, {bool danger = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: danger ? WaiterColors.danger : WaiterColors.ink,
      ));
  }

  /// Send [ops] against the check on screen.
  Future<bool> _apply(List<WaiterOp> ops) async {
    final check = _check;
    if (check == null || _busy) return false;
    setState(() => _busy = true);
    try {
      final next = await _client.apply(tableId: widget.table.id, version: check.version, ops: ops);
      if (mounted) setState(() => _check = next);
      return true;
    } on WaiterCheckChanged catch (e) {
      if (mounted) {
        setState(() => _check = e.current);
        _say(WaiterStrings.of(context).checkChangedElsewhere, danger: true);
      }
      return false;
    } on WaiterLinkFailure catch (e) {
      await _fail(e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(WaiterProduct product, WaiterMenu menu) async {
    final groups = menu.groupsOf(product);
    if (groups.isEmpty) {
      await _apply([WaiterAdd(productId: product.id)]);
      return;
    }
    final choice = await ItemSheet.show(context, product: product, groups: groups, currency: menu.currency);
    if (choice == null) return;
    await _apply([
      WaiterAdd(productId: product.id, modifierIds: choice.modifierIds, quantity: choice.quantity, note: choice.note),
    ]);
  }

  Future<void> _send() async {
    if (await _apply(const [WaiterSendRound()]) && mounted) _say(WaiterStrings.of(context).roundSent);
  }

  Future<void> _editLine(WaiterLine line) async {
    if (!line.isDraft) {
      _say(WaiterStrings.of(context).lineSent);
      return;
    }
    final ops = await LineSheet.show(context, line: line);
    if (ops != null && ops.isNotEmpty) await _apply(ops);
  }

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final menu = ref.watch(menuProvider);
    final check = _check;
    final title = '${widget.table.label}${check?.guests != null ? ' · ${s.guests(check!.guests!)}' : ''}';

    final Widget body;
    if (_error != null && check == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(WaiterSpace.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ErrorNote(_error!),
            const SizedBox(height: WaiterSpace.md),
            OutlinedButton(onPressed: _load, child: Text(s.retry)),
          ]),
        ),
      );
    } else if (check == null || !menu.hasValue) {
      body = menu.hasError
          ? Center(child: ErrorNote(menu.error is WaiterLinkFailure ? s.failure(menu.error! as WaiterLinkFailure) : s.tillProblem))
          : const Center(child: CircularProgressIndicator());
    } else {
      final menuPane = _MenuPane(
        menu: menu.requireValue,
        category: _category,
        onCategory: (c) => setState(() => _category = c),
        onProduct: (p) => _add(p, menu.requireValue),
        enabled: !_busy,
      );
      final checkPane = _CheckPane(check: check, busy: _busy, onSend: _send, onLine: _editLine);
      body = LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= WaiterSpace.tabletMin
            ? Row(children: [
                Expanded(child: menuPane),
                const VerticalDivider(width: 1),
                SizedBox(width: 360, child: checkPane),
              ])
            : DefaultTabController(
                length: 2,
                child: Column(children: [
                  Material(
                    color: WaiterColors.surface,
                    child: TabBar(
                      labelColor: WaiterColors.ink,
                      indicatorColor: WaiterColors.accent,
                      tabs: [
                        Tab(text: s.menu),
                        Tab(key: const Key('check-tab'), text: '${s.check} (${check.lines.where((l) => l.stage != WaiterLineStage.voided).length})'),
                      ],
                    ),
                  ),
                  Expanded(child: TabBarView(children: [menuPane, checkPane])),
                ]),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (check != null)
            IconButton(
              tooltip: s.guestsLabel,
              icon: const Icon(Icons.people_outline),
              onPressed: _busy ? null : () => _editGuests(check),
            ),
          IconButton(tooltip: s.refresh, icon: const Icon(Icons.refresh), onPressed: _busy ? null : _load),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Future<void> _editGuests(WaiterCheck check) async {
    final s = WaiterStrings.of(context);
    var n = check.guests ?? widget.table.seats ?? 2;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(s.guestsLabel),
          content: _Stepper(value: n, onChanged: (v) => set(() => n = v), min: 1),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, n), child: Text(s.save)),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != check.guests) await _apply([WaiterSetGuests(chosen)]);
  }
}

class _MenuPane extends StatelessWidget {
  const _MenuPane({
    required this.menu,
    required this.category,
    required this.onCategory,
    required this.onProduct,
    required this.enabled,
  });

  final WaiterMenu menu;
  final int? category;
  final ValueChanged<int?> onCategory;
  final ValueChanged<WaiterProduct> onProduct;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final products = category == null ? menu.products : menu.inCategory(category!);
    Widget chip(String label, int? id) => Padding(
      padding: const EdgeInsetsDirectional.only(end: WaiterSpace.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: category == id,
        onSelected: (_) => onCategory(id),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        selectedColor: WaiterColors.accentSoft,
        side: BorderSide(color: category == id ? WaiterColors.accent : WaiterColors.lineStrong),
        showCheckmark: false,
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.md, vertical: WaiterSpace.sm),
            children: [
              chip(s.allItems, null),
              for (final c in menu.categories) chip(c.name.pick(arabic: s.arabic), c.id),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(WaiterSpace.md),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 92,
              crossAxisSpacing: WaiterSpace.sm,
              mainAxisSpacing: WaiterSpace.sm,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) {
              final p = products[i];
              return Material(
                color: p.available ? WaiterColors.surface : WaiterColors.page,
                shape: const Border.fromBorderSide(BorderSide(color: WaiterColors.lineStrong)),
                child: InkWell(
                  key: Key('product-${p.id}'),
                  onTap: enabled && p.available ? () => onProduct(p) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(WaiterSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            p.name.pick(arabic: s.arabic),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: p.available ? WaiterColors.ink : WaiterColors.muted,
                            ),
                          ),
                        ),
                        Text(
                          p.available ? moneyText(menu.currency, p.priceMinor, arabic: s.arabic) : s.unavailable,
                          style: waiterMono(size: 13, color: p.available ? WaiterColors.body : WaiterColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CheckPane extends StatelessWidget {
  const _CheckPane({required this.check, required this.busy, required this.onSend, required this.onLine});

  final WaiterCheck check;
  final bool busy;
  final VoidCallback onSend;
  final ValueChanged<WaiterLine> onLine;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    String m(int minor) => moneyText(check.currency, minor, arabic: s.arabic);
    return ColoredBox(
      color: WaiterColors.surface,
      child: Column(
        children: [
          Expanded(
            child: check.lines.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(WaiterSpace.xl),
                      child: Text(s.emptyCheck, textAlign: TextAlign.center, style: const TextStyle(color: WaiterColors.muted)),
                    ),
                  )
                : ListView.separated(
                    itemCount: check.lines.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) => _LineTile(line: check.lines[i], money: m, onTap: () => onLine(check.lines[i])),
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(WaiterSpace.md),
            child: Column(
              children: [
                _TotalRow(s.subtotal, m(check.subtotalMinor)),
                if (check.discountMinor != 0) _TotalRow(s.discount, m(-check.discountMinor)),
                if (check.serviceMinor != 0) _TotalRow(s.service, m(check.serviceMinor)),
                if (check.taxMinor != 0) _TotalRow(s.tax, m(check.taxMinor)),
                _TotalRow(s.total, m(check.totalMinor), strong: true),
                const SizedBox(height: WaiterSpace.md),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    key: const Key('send'),
                    onPressed: check.hasDraft && !busy ? onSend : null,
                    child: busy ? const SmallSpinner() : Text(s.sendRound),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.money, required this.onTap});

  final WaiterLine line;
  final String Function(int) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final voided = line.stage == WaiterLineStage.voided;
    final status = switch (line.stage) {
      WaiterLineStage.draft => s.notSentYet,
      WaiterLineStage.sent => s.sent(line.round ?? 1),
      WaiterLineStage.voided => s.voided,
    };
    final strike = voided ? TextDecoration.lineThrough : null;
    return InkWell(
      onTap: voided ? null : onTap,
      child: Container(
        // Unsent lines are marked: they are the ones the waiter can still change.
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(color: line.isDraft ? WaiterColors.accent : Colors.transparent, width: 4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.md, vertical: WaiterSpace.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${line.quantity}×', style: waiterMono(size: 15)),
            const SizedBox(width: WaiterSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name.pick(arabic: s.arabic),
                      style: TextStyle(fontWeight: FontWeight.w600, color: WaiterColors.ink, decoration: strike)),
                  if (line.modifiers.isNotEmpty)
                    Text(line.modifiers.map((m) => m.pick(arabic: s.arabic)).join('، '),
                        style: const TextStyle(fontSize: 12.5, color: WaiterColors.body)),
                  if (line.note != null)
                    Text('“${line.note}”', style: const TextStyle(fontSize: 12.5, color: WaiterColors.warn)),
                  Text(status, style: TextStyle(fontSize: 11.5, color: line.isDraft ? WaiterColors.warn : WaiterColors.muted)),
                ],
              ),
            ),
            Text(money(line.totalMinor), style: waiterMono(size: 14).copyWith(decoration: strike)),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(color: strong ? WaiterColors.ink : WaiterColors.body, fontWeight: strong ? FontWeight.w800 : FontWeight.w400, fontSize: strong ? 17 : 14))),
      Text(value, style: waiterMono(size: strong ? 18 : 14, weight: strong ? FontWeight.w800 : FontWeight.w600)),
    ]),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged, this.min = 1});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  static const max = 99;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      OutlinedButton(onPressed: value > min ? () => onChanged(value - 1) : null, child: const Icon(Icons.remove)),
      SizedBox(width: 56, child: Text('$value', textAlign: TextAlign.center, style: waiterMono(size: 22))),
      OutlinedButton(onPressed: value < max ? () => onChanged(value + 1) : null, child: const Icon(Icons.add)),
    ],
  );
}
