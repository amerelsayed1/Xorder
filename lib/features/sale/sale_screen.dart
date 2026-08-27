import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/ticket.dart';
import '../../domain/repositories/repositories.dart';
import '../payment/payment_screen.dart';
import '../shift/presentation/shift_dialogs.dart';
import 'widgets/cart_panel.dart';
import 'widgets/category_rail.dart';
import 'widgets/modifier_sheet.dart';
import 'widgets/pos_top_bar.dart';
import 'widgets/product_grid.dart';

/// The primary selling screen.
///
/// Three shells, one feature set, chosen by width (design sheet §2):
/// ≥1100 rail + grid + persistent cart · 700–1099 tabs + grid + cart ·
/// <700 pushed routes. Desktop is the design driver; the narrow shell exists
/// for Android POS handhelds.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({
    super.key,
    required this.onLock,
    required this.onTables,
    required this.onCloseShift,
  });

  final VoidCallback onLock;
  final VoidCallback onTables;
  final VoidCallback onCloseShift;

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _addProduct(Product product, Catalog catalog) async {
    if (!product.isAvailable) {
      posToast(context, "${product.nameEn} is out of stock — 86'd in the catalog.");
      return;
    }

    final groups = catalog.groupsFor(product);
    final controller = ref.read(ticketProvider.notifier);

    // A product with no modifier groups goes straight onto the ticket — an
    // extra confirmation on every drink would cost the cashier real seconds.
    if (groups.isEmpty) {
      controller.addProduct(product);
      return;
    }

    final selection = await ModifierSheet.show(
      context,
      product: product,
      groups: groups,
    );
    if (selection == null || !mounted) return;

    controller.addProduct(
      product,
      modifiers: selection.modifiers,
      groups: groups,
      quantity: selection.quantity,
    );
  }

  void _charge(Ticket ticket) {
    if (ticket.isEmpty) {
      posToast(context, 'Nothing to charge.');
      return;
    }
    PaymentScreen.show(context);
  }

  void _void(Ticket ticket) {
    ref.read(ticketProvider.notifier).reset();
    posToast(context, 'Ticket voided.');
  }

  /// Cash up and hand the till back.
  ///
  /// Two things had to change here. It used to navigate to the start screen and
  /// nothing else — no shift was closed, because none was ever opened, and an
  /// in-progress ticket was discarded without a word. A cashier who taps this
  /// with a customer's order on screen should not lose it.
  Future<void> _closeShift(Ticket ticket) async {
    if (!ticket.isEmpty) {
      posToast(
        context,
        'There is still a ticket on this till. Take payment or void it before '
        'closing the shift.',
      );
      return;
    }

    final shift = ref.read(shiftProvider).valueOrNull;
    if (shift == null) {
      // Nothing to count. Handing the till back is still the right outcome.
      widget.onCloseShift();
      return;
    }

    final closed = await CloseShiftDialog.show(context, shift: shift);
    if (closed && mounted) widget.onCloseShift();
  }

  void _sendRound() {
    ref.read(ticketProvider.notifier).sendRound();
    posToast(context, 'Round sent to the kitchen.');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final catalog = ref.watch(catalogProvider);
    final ticket = ref.watch(ticketProvider);
    final ui = ref.watch(posUiProvider);

    if (session.isLoading || catalog.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: PosColors.accent)),
      );
    }

    final sessionData = session.requireValue;
    final catalogData = catalog.requireValue;

    return _shortcuts(
      ticket: ticket,
      child: Scaffold(
        backgroundColor: PosColors.page,
        body: Column(
          // Stretch, not the default centre: without it the 56px shell top bar
          // shrink-wraps to its content and floats in the middle of the window.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PosTopBar(
              session: sessionData,
              onLock: widget.onLock,
              onCloseShift: () => _closeShift(ticket),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _shell(
                  constraints.maxWidth,
                  sessionData,
                  catalogData,
                  ticket,
                  ui,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shell-level shortcuts. Registered once here, never per-widget, so a key
  /// means the same thing on every screen the shell hosts.
  Widget _shortcuts({required Ticket ticket, required Widget child}) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f2): _searchFocus.requestFocus,
          const SingleActivator(LogicalKeyboardKey.f4): () {
            if (ticket.hasDraft) _sendRound();
          },
          const SingleActivator(LogicalKeyboardKey.f9): () => _charge(ticket),
          const SingleActivator(LogicalKeyboardKey.f10): () =>
              posToast(context, 'Cash drawer opened · F10'),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_searchController.text.isNotEmpty) {
              _searchController.clear();
              ref.read(posUiProvider.notifier).setQuery('');
            }
          },
        },
        child: Focus(autofocus: true, child: child),
      );

  Widget _shell(
    double width,
    PosSession session,
    Catalog catalog,
    Ticket ticket,
    PosUiState ui,
  ) {
    final products = _visibleProducts(catalog, ui);
    final productArea = _productArea(catalog, products, ticket, ui);

    if (width >= PosSize.wideShellMin) {
      return Row(
        children: [
          CategoryRail(
            catalog: catalog,
            selectedId: ui.selectedCategoryId,
            onSelect: ref.read(posUiProvider.notifier).selectCategory,
            onOpenTickets: () => posToast(context, 'Open tickets — not built yet.'),
            onTables: widget.onTables,
          ),
          Expanded(child: productArea),
          _cart(session, ticket, ui),
        ],
      );
    }

    if (width >= PosSize.mediumShellMin) {
      return Row(
        children: [Expanded(child: productArea), _cart(session, ticket, ui)],
      );
    }

    // Narrow: the cart is a route, not a pane.
    return productArea;
  }

  Widget _cart(PosSession session, Ticket ticket, PosUiState ui) => CartPanel(
        ticket: ticket,
        cashierName: session.userName,
        online: ui.online,
        onQuantityChanged: (key, delta) =>
            ref.read(ticketProvider.notifier).changeQuantity(key, delta),
        onSendRound: _sendRound,
        onVoid: () => _void(ticket),
        onCharge: () => _charge(ticket),
        onChangeTable: widget.onTables,
      );

  List<Product> _visibleProducts(Catalog catalog, PosUiState ui) {
    if (ui.query.trim().isNotEmpty) return catalog.search(ui.query);
    return catalog.inCategory(ui.selectedCategoryId);
  }

  Widget _productArea(
    Catalog catalog,
    List<Product> products,
    Ticket ticket,
    PosUiState ui,
  ) {
    final slugs = {for (final c in catalog.categories) c.id: c.slug};
    final inCart = ticket.lines.map((l) => l.product.id).toSet();

    return Column(
      children: [
        _searchRow(),
        Expanded(
          child: ProductGrid(
            products: products,
            categorySlugs: slugs,
            inCartProductIds: inCart,
            onTap: (product) => _addProduct(product, catalog),
          ),
        ),
        _footerStrip(catalog, products, ui),
      ],
    );
  }

  Widget _searchRow() => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: PosSpace.s14,
          vertical: PosSpace.md,
        ),
        decoration: const BoxDecoration(
          color: PosColors.surface,
          border: Border(bottom: PosBorders.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: PosSize.searchRow,
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.md),
                decoration: const BoxDecoration(
                  color: PosColors.page,
                  border: Border.fromBorderSide(PosBorders.emphasis),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 17, color: PosColors.inkWarm),
                    const SizedBox(width: PosSpace.sm),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        onChanged: ref.read(posUiProvider.notifier).setQuery,
                        style: PosText.ui(size: 14.5),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Scan barcode or search item / PLU',
                          hintStyle: PosText.ui(size: 14.5, color: PosColors.muted),
                        ),
                      ),
                    ),
                    const KeyChip('F2'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: PosSpace.md),
            PosButton(
              label: 'Custom amount',
              height: PosSize.searchRow,
              border: const Border.fromBorderSide(BorderSide(color: PosColors.inkWarm)),
              onPressed: () => posToast(context, 'Custom amount — not built yet.'),
            ),
          ],
        ),
      );

  Widget _footerStrip(Catalog catalog, List<Product> visible, PosUiState ui) {
    final searching = ui.query.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PosSpace.s14,
        vertical: PosSpace.s10,
      ),
      decoration: const BoxDecoration(
        color: PosColors.surface,
        border: Border(top: PosBorders.hairline),
      ),
      child: Row(
        children: [
          Text(
            'F2 SEARCH   F4 PARK   F9 PAY   ESC CLOSE',
            style: PosText.mono(size: 11, color: PosColors.muted),
          ),
          const Spacer(),
          Text(
            searching
                ? '${visible.length} matches'
                : 'CATALOG CACHED · ${catalog.products.length} ITEMS',
            style: PosText.mono(size: 11, color: PosColors.ink),
          ),
        ],
      ),
    );
  }
}
