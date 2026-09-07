import '../../core/money/money.dart';
import '../../domain/models/catalog.dart';
import '../../domain/models/discount.dart';
import '../../domain/models/ticket.dart';

/// Serializes a parked [Ticket] for `pos_parked_tickets`, and rebuilds it.
///
/// Lives in the data layer on purpose: the domain stays pure and never learns
/// what JSON is. Encoding snapshots everything a rebuild could need — ids for
/// the happy path, names and prices for the sad one — because the catalog can
/// change while a ticket sits parked: reseeded from the platform, an item
/// deleted, a price moved. Decoding therefore **prefers the live catalog**
/// (so a resumed line keeps behaving like its product: modifiers, availability)
/// and **falls back to the snapshots** when the id no longer resolves — the
/// bill the guests are eating from must not change because head office edited
/// the menu (client rule 11: never throw on data).
abstract final class ParkedTicketCodec {
  static Map<String, Object?> encode(Ticket ticket) => {
    'v': 1,
    'client_transaction_id': ticket.id,
    'order_type': ticket.orderType.wire,
    'table_id': ticket.tableId,
    'table_label': ticket.tableLabel,
    'guest_count': ticket.guestCount,
    'currency': ticket.currency,
    'exponent': ticket.exponent,
    'rounds_sent': ticket.roundsSent,
    'tax': {
      'service_bp': ticket.taxConfig.serviceBp,
      'vat_bp': ticket.taxConfig.vatBp,
      'service_dine_in_only': ticket.taxConfig.serviceDineInOnly,
      'source': ticket.taxConfig.source.name,
    },
    'lines': [
      for (final line in ticket.lines)
        {
          'product_id': line.product.id,
          'category_id': line.product.categoryId,
          'name_en': line.product.nameEn,
          'name_ar': line.product.nameAr,
          'price_minor': line.product.price.minor,
          'discounted_price_minor': line.product.discountedPrice?.minor,
          'quantity': line.quantity,
          'note': line.note,
          'stage': line.stage.name,
          'round_number': line.roundNumber,
          'modifiers': [
            for (final modifier in line.modifiers)
              {
                'id': modifier.id,
                'group_id': modifier.groupId,
                'name_en': modifier.nameEn,
                'name_ar': modifier.nameAr,
                'price_delta_minor': modifier.priceDelta.minor,
              },
          ],
        },
    ],
    'tenders': [
      for (final tender in ticket.tenders)
        {
          'type_id': tender.typeId,
          'label': tender.label,
          'amount_minor': tender.amount.minor,
          'reference': tender.reference,
        },
    ],
    // A parked ticket that lost its discount on a restart would hand the guests
    // a larger bill than the one they agreed to, with nothing on screen to say
    // why. Everything here is already a snapshot, so it round-trips as written
    // and never re-prices against a discount somebody has since edited.
    'discounts': [
      for (final discount in ticket.discounts)
        {
          'discount_id': discount.discountId,
          'line_key': discount.lineKey,
          'name_snapshot': discount.nameSnapshot,
          'kind': discount.kind.wire,
          'value_bp': discount.valueBp,
          'value_minor': discount.valueMinor?.minor,
          'amount_minor': discount.amount.minor,
          'reason_id': discount.reasonId,
          'note': discount.note,
          'approved_by_name': discount.approvedByName,
        },
    ],
  };

  /// Null only when the payload cannot name a transaction at all — anything
  /// less broken decodes to the best ticket the data supports.
  static Ticket? decode(Map<String, Object?> json, Catalog catalog) {
    final id = json['client_transaction_id'];
    if (id is! String || id.isEmpty) return null;

    final currency = json['currency'] is String
        ? json['currency'] as String
        : 'EGP';
    final exponent = json['exponent'] is int ? json['exponent'] as int : 2;

    Money minor(Object? value, {int orElse = 0}) => Money(
      value is int ? value : orElse,
      currency: currency,
      exponent: exponent,
    );

    final tax = json['tax'] is Map
        ? (json['tax'] as Map).cast<String, Object?>()
        : const <String, Object?>{};

    final lines = <TicketLine>[
      if (json['lines'] is List)
        for (final raw in json['lines'] as List)
          if (raw is Map)
            ?_line(raw.cast<String, Object?>(), catalog, currency, exponent),
    ];

    return Ticket(
      id: id,
      orderType:
          OrderType.fromWire(
            json['order_type'] is String ? json['order_type'] as String : '',
          ) ??
          OrderType.dineIn,
      tableId: json['table_id'] is int ? json['table_id'] as int : null,
      tableLabel: json['table_label'] is String
          ? json['table_label'] as String
          : null,
      guestCount: json['guest_count'] is int
          ? json['guest_count'] as int
          : null,
      currency: currency,
      exponent: exponent,
      roundsSent: json['rounds_sent'] is int ? json['rounds_sent'] as int : 0,
      taxConfig: TaxConfig(
        serviceBp: tax['service_bp'] is int ? tax['service_bp'] as int : 1200,
        vatBp: tax['vat_bp'] is int ? tax['vat_bp'] as int : 1400,
        serviceDineInOnly: tax['service_dine_in_only'] is bool
            ? tax['service_dine_in_only'] as bool
            : true,
        source: tax['source'] == TaxSource.server.name
            ? TaxSource.server
            : TaxSource.deviceConfig,
      ),
      lines: lines,
      tenders: [
        if (json['tenders'] is List)
          for (final raw in json['tenders'] as List)
            if (raw is Map && raw['amount_minor'] is int)
              Tender(
                typeId: raw['type_id'] is int ? raw['type_id'] as int : 0,
                label: raw['label'] is String ? raw['label'] as String : '—',
                amount: minor(raw['amount_minor']),
                reference: raw['reference'] is String
                    ? raw['reference'] as String
                    : null,
              ),
      ],
      discounts: [
        if (json['discounts'] is List)
          for (final raw in json['discounts'] as List)
            if (raw is Map && raw['amount_minor'] is int)
              AppliedDiscount(
                discountId: raw['discount_id'] is int
                    ? raw['discount_id'] as int
                    : null,
                lineKey: raw['line_key'] is String
                    ? raw['line_key'] as String
                    : null,
                nameSnapshot: raw['name_snapshot'] is String
                    ? raw['name_snapshot'] as String
                    : '—',
                // An unreadable kind decodes as `fixed`, because the amount
                // beside it is already the answer: a fixed discount needs no
                // rate to re-price from, so the bill stays exactly what it was
                // when the guests were told it.
                kind:
                    DiscountKind.fromWire(
                      raw['kind'] is String ? raw['kind'] as String : '',
                    ) ??
                    DiscountKind.fixed,
                valueBp: raw['value_bp'] is int ? raw['value_bp'] as int : null,
                valueMinor: raw['value_minor'] is int
                    ? minor(raw['value_minor'])
                    : null,
                amount: minor(raw['amount_minor']),
                reasonId: raw['reason_id'] is int
                    ? raw['reason_id'] as int
                    : null,
                note: raw['note'] is String ? raw['note'] as String : null,
                approvedByName: raw['approved_by_name'] is String
                    ? raw['approved_by_name'] as String
                    : null,
              ),
      ],
    );
  }

  static TicketLine? _line(
    Map<String, Object?> raw,
    Catalog catalog,
    String currency,
    int exponent,
  ) {
    final productId = raw['product_id'];
    if (productId is! int) return null;
    final quantity = raw['quantity'] is int ? raw['quantity'] as int : 1;
    if (quantity <= 0) return null;

    Money minor(Object? value, {int orElse = 0}) => Money(
      value is int ? value : orElse,
      currency: currency,
      exponent: exponent,
    );

    // The live catalog first: a resumed line keeps its product's behaviour.
    // The snapshot second: a deleted product still reads, prices and settles
    // exactly as it did when it was rung up.
    final live = catalog.products.where((p) => p.id == productId).firstOrNull;
    final product =
        live ??
        Product(
          id: productId,
          categoryId: raw['category_id'] is int ? raw['category_id'] as int : 0,
          nameEn: raw['name_en'] is String
              ? raw['name_en'] as String
              : 'Item $productId',
          nameAr: raw['name_ar'] is String ? raw['name_ar'] as String : null,
          price: minor(raw['price_minor']),
          discountedPrice: raw['discounted_price_minor'] is int
              ? minor(raw['discounted_price_minor'])
              : null,
        );

    final modifiers = <Modifier>[
      if (raw['modifiers'] is List)
        for (final m in raw['modifiers'] as List)
          if (m is Map && m['id'] is int)
            catalog.modifierGroups
                    .expand((g) => g.modifiers)
                    .where((mod) => mod.id == m['id'])
                    .firstOrNull ??
                Modifier(
                  id: m['id'] as int,
                  groupId: m['group_id'] is int ? m['group_id'] as int : 0,
                  nameEn: m['name_en'] is String
                      ? m['name_en'] as String
                      : 'Option',
                  nameAr: m['name_ar'] is String
                      ? m['name_ar'] as String
                      : null,
                  priceDelta: minor(m['price_delta_minor']),
                ),
    ];

    return TicketLine(
      product: product,
      quantity: quantity,
      modifiers: modifiers,
      note: raw['note'] is String ? raw['note'] as String : null,
      stage: raw['stage'] == LineStage.sent.name
          ? LineStage.sent
          : LineStage.draft,
      roundNumber: raw['round_number'] is int
          ? raw['round_number'] as int
          : null,
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
