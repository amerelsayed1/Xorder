import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xorder_waiter_link/xorder_waiter_link.dart';

import '../state.dart';
import '../strings.dart';
import '../theme.dart';
import 'item_sheet.dart';
import 'widgets.dart';

/// One table's check: the menu to add from, the lines, and "send to kitchen"
/// (design §5.4–5.5).
///
/// Every tap is one request: the till applies it with its own ticket rules and
/// sends back the check it now holds, priced. A table changed on another
/// device meanwhile comes back as the current check and the waiter redoes the
/// change (XORD-044) — nothing is merged behind their back.
///
/// On a phone the menu and the check are two tabs with a sticky bar under the
/// menu; on a tablet they sit side by side. The bar never sends: sending is a
/// decision taken while looking at the lines.
class CheckScreen extends ConsumerStatefulWidget {
  const CheckScreen({required this.table, super.key});

  final WaiterTable table;

  @override
  ConsumerState<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends ConsumerState<CheckScreen> with SingleTickerProviderStateMixin {
  WaiterCheck? _check;
  String? _error;
  bool _busy = false;
  int? _category;
  String _query = '';
  late final TabController _tabs = TabController(length: 2, vsync: this);

  WaiterClient get _client => ref.read(waiterAppProvider.notifier).client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
    final liveLines = check?.lines.where((l) => l.stage != WaiterLineStage.voided).length ?? 0;
    final subtitle = dotJoin([widget.table.area, if (check?.guests != null) s.guests(check!.guests!)]);

    final Widget body;
    if (_error != null && check == null) {
      body = EmptyState(_error!, actionLabel: s.retry, onAction: _load);
    } else if (check == null || !menu.hasValue) {
      body = menu.hasError
          ? EmptyState(
              menu.error is WaiterLinkFailure ? s.failure(menu.error! as WaiterLinkFailure) : s.tillProblem,
              actionLabel: s.retry,
              onAction: () => ref.invalidate(menuProvider),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final menuPane = _MenuPane(
        menu: menu.requireValue,
        category: _category,
        query: _query,
        onCategory: (c) => setState(() => _category = c),
        onQuery: (q) => setState(() => _query = q),
        onProduct: (p) => _add(p, menu.requireValue),
        onCheck: _onCheck(check),
        enabled: !_busy,
      );
      body = LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= WaiterSpace.tabletMin) {
            return Row(children: [
              Expanded(child: menuPane),
              const VerticalDivider(width: 1),
              SizedBox(
                width: WaiterSpace.checkPane,
                child: _CheckPane(check: check, busy: _busy, onSend: _send, onLine: _editLine),
              ),
            ]);
          }
          void toCheck() => _tabs.animateTo(1);
          return Column(children: [
            Material(
              color: WaiterColors.surface,
              child: TabBar(
                controller: _tabs,
                tabs: [
                  Tab(height: WaiterSpace.touch, text: s.menu),
                  Tab(key: const Key('check-tab'), height: WaiterSpace.touch, text: s.checkTab(liveLines)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  Column(children: [
                    Expanded(child: menuPane),
                    if (!check.isEmpty) _CheckBar(check: check, onOpen: toCheck),
                  ]),
                  _CheckPane(check: check, busy: _busy, onSend: _send, onLine: _editLine, onOpenMenu: () => _tabs.animateTo(0)),
                ],
              ),
            ),
          ]);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.table.label, style: WaiterText.mono(size: 18, weight: FontWeight.w700)),
            if (subtitle.isNotEmpty) Text(subtitle, style: WaiterText.meta()),
          ],
        ),
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

  /// How many of each product are on the check (voided lines aside), so the
  /// menu shows what the waiter has already picked for this table.
  static Map<int, int> _onCheck(WaiterCheck check) {
    final counts = <int, int>{};
    for (final l in check.lines) {
      final id = l.productId;
      if (id == null || l.stage == WaiterLineStage.voided) continue;
      counts[id] = (counts[id] ?? 0) + l.quantity;
    }
    return counts;
  }

  Future<void> _editGuests(WaiterCheck check) async {
    final s = WaiterStrings.of(context);
    var n = check.guests ?? widget.table.seats ?? 2;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(s.guestsLabel),
          content: QuantityStepper(value: n, onChanged: (v) => set(() => n = v)),
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
    required this.query,
    required this.onCategory,
    required this.onQuery,
    required this.onProduct,
    required this.onCheck,
    required this.enabled,
  });

  final WaiterMenu menu;
  final int? category;
  final String query;
  final ValueChanged<int?> onCategory;
  final ValueChanged<String> onQuery;
  final ValueChanged<WaiterProduct> onProduct;

  /// Product id → quantity already on the check.
  final Map<int, int> onCheck;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final q = query.trim().toLowerCase();
    // A search looks across every category: a waiter typing "tea" wants tea,
    // whichever chip was left selected.
    final products = [
      for (final p in q.isEmpty && category != null ? menu.inCategory(category!) : menu.products)
        if (q.isEmpty || p.name.en.toLowerCase().contains(q) || (p.name.ar?.contains(q) ?? false)) p,
    ];
    Widget chip(String label, int? id) {
      final selected = q.isEmpty && category == id;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: WaiterSpace.sm),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onCategory(id),
          side: BorderSide(color: selected ? WaiterColors.accent : WaiterColors.lineStrong, width: selected ? 2 : 1),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(WaiterSpace.md, WaiterSpace.sm, WaiterSpace.md, 0),
          child: SizedBox(
            height: WaiterSpace.touch,
            child: TextField(
              key: const Key('menu-search'),
              onChanged: onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: s.searchMenu,
                prefixIcon: const Icon(Icons.search, color: WaiterColors.muted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: WaiterSpace.md, vertical: WaiterSpace.md),
              ),
            ),
          ),
        ),
        SizedBox(
          height: WaiterSpace.touch + WaiterSpace.sm,
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
          child: products.isEmpty
              ? EmptyState(s.noMatches)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(WaiterSpace.md, 0, WaiterSpace.md, WaiterSpace.md),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: WaiterSpace.productTileMaxExtent,
                    mainAxisExtent: WaiterSpace.productTile,
                    crossAxisSpacing: WaiterSpace.productGutter,
                    mainAxisSpacing: WaiterSpace.productGutter,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) => _ProductTile(
                    product: products[i],
                    currency: menu.currency,
                    onCheck: onCheck[products[i].id] ?? 0,
                    enabled: enabled,
                    onTap: onProduct,
                  ),
                ),
        ),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.currency,
    required this.onCheck,
    required this.enabled,
    required this.onTap,
  });

  final WaiterProduct product;
  final WaiterCurrency currency;

  /// How many of this product are on the check; above zero the tile reads as
  /// selected — accent fill, emphasised border and the count.
  final int onCheck;
  final bool enabled;
  final ValueChanged<WaiterProduct> onTap;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final p = product;
    final selected = onCheck > 0;
    return Semantics(
      selected: selected,
      child: Material(
        color: selected ? WaiterColors.accentSoft : (p.available ? WaiterColors.surface : WaiterColors.page),
        shape: Border.fromBorderSide(
          BorderSide(color: selected ? WaiterColors.accent : WaiterColors.lineStrong, width: selected ? 2 : 1),
        ),
        child: InkWell(
          key: Key('product-${p.id}'),
          onTap: enabled && p.available ? () => onTap(p) : null,
          child: Padding(
            padding: EdgeInsets.all(selected ? WaiterSpace.md - 1 : WaiterSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          p.name.pick(arabic: s.arabic),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WaiterText.itemTitle(color: p.available ? WaiterColors.ink : WaiterColors.muted),
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: WaiterSpace.sm),
                        Container(
                          key: Key('product-${p.id}-count'),
                          color: WaiterColors.accent,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text('$onCheck×', style: WaiterText.mono(size: 13, weight: FontWeight.w700, color: WaiterColors.ink)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (p.available)
                  MoneyText(currency, p.priceMinor, style: WaiterText.price(color: WaiterColors.body))
                else
                  Text(s.unavailable, style: WaiterText.meta()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Under the menu on a phone: the total, how much is not sent, and the way to
/// the check. It never sends.
class _CheckBar extends StatelessWidget {
  const _CheckBar({required this.check, required this.onOpen});

  final WaiterCheck check;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final drafts = check.lines.where((l) => l.isDraft).length;
    final live = check.lines.where((l) => l.stage != WaiterLineStage.voided).length;
    return BottomBar(
      padding: const EdgeInsets.symmetric(horizontal: WaiterSpace.lg, vertical: WaiterSpace.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: WaiterSpace.checkBar - 2 * WaiterSpace.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyText(check.currency, check.totalMinor, style: WaiterText.barTotal()),
                  if (drafts > 0) Text(s.notSentCount(drafts), style: WaiterText.meta(color: WaiterColors.warn)),
                ],
              ),
            ),
            OutlinedButton(
              key: const Key('check-bar-open'),
              onPressed: onOpen,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: drafts > 0 ? WaiterColors.accent : WaiterColors.lineStrong, width: drafts > 0 ? 2 : 1),
              ),
              child: Text(s.checkTab(live)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines, grouped: what is not sent yet first, then each round newest
/// first; then the totals and the one action.
class _CheckPane extends StatelessWidget {
  const _CheckPane({required this.check, required this.busy, required this.onSend, required this.onLine, this.onOpenMenu});

  final WaiterCheck check;
  final bool busy;
  final VoidCallback onSend;
  final ValueChanged<WaiterLine> onLine;
  final VoidCallback? onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final drafts = check.lines.where((l) => l.isDraft).toList();
    final rounds = <int?, List<WaiterLine>>{};
    for (final l in check.lines) {
      if (!l.isDraft) (rounds[l.round] ??= []).add(l);
    }
    final roundKeys = rounds.keys.toList()
      ..sort((a, b) => (b ?? 0).compareTo(a ?? 0));

    return ColoredBox(
      color: WaiterColors.surface,
      child: Column(
        children: [
          Expanded(
            child: check.lines.isEmpty
                ? EmptyState(s.emptyCheck, actionLabel: onOpenMenu == null ? null : s.openMenu, onAction: onOpenMenu)
                : ListView(
                    padding: const EdgeInsets.only(bottom: WaiterSpace.md),
                    children: [
                      if (drafts.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(WaiterSpace.lg, WaiterSpace.sm, WaiterSpace.lg, 0),
                          child: SectionHeader(s.notSentHeader, count: drafts.length, color: WaiterColors.warn),
                        ),
                        for (final l in drafts) _LineTile(line: l, currency: check.currency, onTap: () => onLine(l)),
                      ],
                      for (final r in roundKeys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(WaiterSpace.lg, WaiterSpace.sm, WaiterSpace.lg, 0),
                          child: SectionHeader(r == null ? s.voided : s.sent(r), count: rounds[r]!.length),
                        ),
                        for (final l in rounds[r]!) _LineTile(line: l, currency: check.currency, onTap: () => onLine(l)),
                      ],
                    ],
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(WaiterSpace.lg, WaiterSpace.md, WaiterSpace.lg, WaiterSpace.sm),
            child: Column(
              children: [
                _TotalRow(s.subtotal, check.currency, check.subtotalMinor),
                if (check.discountMinor != 0) _TotalRow(s.discount, check.currency, -check.discountMinor),
                if (check.serviceMinor != 0) _TotalRow(s.service, check.currency, check.serviceMinor),
                if (check.taxMinor != 0) _TotalRow(s.tax, check.currency, check.taxMinor),
                _TotalRow(s.total, check.currency, check.totalMinor, strong: true),
              ],
            ),
          ),
          BottomBar(
            child: PrimaryCta(
              key: const Key('send'),
              label: s.sendRoundCount(drafts.length),
              busy: busy,
              onPressed: drafts.isNotEmpty ? onSend : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.currency, required this.onTap});

  final WaiterLine line;
  final WaiterCurrency currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = WaiterStrings.of(context);
    final voided = line.stage == WaiterLineStage.voided;
    final sent = line.stage == WaiterLineStage.sent;
    final strike = voided ? TextDecoration.lineThrough : null;
    final ink = voided ? WaiterColors.muted : (sent ? WaiterColors.body : WaiterColors.ink);
    return InkWell(
      onTap: voided ? null : onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: WaiterSpace.touch),
        // Unsent lines are marked: they are the ones the waiter can still change.
        decoration: BoxDecoration(
          border: Border(
            bottom: const BorderSide(color: WaiterColors.line),
            left: BorderSide(color: line.isDraft ? WaiterColors.accent : Colors.transparent, width: 4),
          ),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(WaiterSpace.md, WaiterSpace.s10, WaiterSpace.lg, WaiterSpace.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 36, child: Text('${line.quantity}×', style: WaiterText.mono(size: 15, color: ink))),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name.pick(arabic: s.arabic), style: WaiterText.itemTitle(color: ink, decoration: strike)),
                  if (line.modifiers.isNotEmpty)
                    Text(line.modifiers.map((m) => m.pick(arabic: s.arabic)).join(s.listSeparator), style: WaiterText.meta(color: WaiterColors.body)),
                  if (line.note != null) Text('“${line.note}”', style: WaiterText.meta(color: WaiterColors.warn)),
                  if (line.isDraft) Text(s.notSentYet, style: WaiterText.meta(color: WaiterColors.warn)),
                  if (voided) Text(s.voided, style: WaiterText.meta()),
                ],
              ),
            ),
            const SizedBox(width: WaiterSpace.sm),
            MoneyText(currency, line.totalMinor, style: WaiterText.price(color: ink, decoration: strike)),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.currency, this.minor, {this.strong = false});
  final String label;
  final WaiterCurrency currency;
  final int minor;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            label,
            style: strong ? WaiterText.ui(size: 16, weight: FontWeight.w700) : WaiterText.body(),
          ),
        ),
        MoneyText(currency, minor, style: strong ? WaiterText.total() : WaiterText.price(color: WaiterColors.body)),
      ],
    ),
  );
}
