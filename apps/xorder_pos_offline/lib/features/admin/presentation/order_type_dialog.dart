import 'package:flutter/material.dart';

import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/mono_amount.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';
import 'package:shared_module/domain/models/content_languages.dart';
import 'content_language_ui.dart';
import 'package:shared_module/domain/models/order_type_config.dart';

/// What a kind of order requires (§31).
///
/// **No "new" and no "delete".** The four codes are an `OrderType` enum and
/// every place that renders one reads its name off that enum, so a fifth would
/// have nowhere to appear. What a business actually wants here is to rename
/// them into its own words — "Delivery" is *دليفري* on half the tills in Cairo —
/// and to say which of the four it sells.
///
/// **`requires a table` is the switch with teeth.** The router asks it before it
/// offers a floor plan, the cart asks it before prompting "no table yet", and the
/// engine asks it when somebody switches an order's type mid-ticket. A catering
/// business that seats people turns it on for takeaway; a drive-thru with
/// numbered bays turns it on for drive-thru. That was compiled in before this
/// existed.
class OrderTypeDialog extends StatefulWidget {
  const OrderTypeDialog({
    required this.config,
    super.key,
    this.languages = ContentLanguages.both,
  });

  final OrderTypeConfig config;

  /// Which name fields the business writes its content in (XORD-005).
  final ContentLanguages languages;

  static Future<OrderTypeConfig?> show(
    BuildContext context, {
    required OrderTypeConfig config,
    ContentLanguages languages = ContentLanguages.both,
  }) => showDialog<OrderTypeConfig>(
    context: context,
    builder: (_) => OrderTypeDialog(config: config, languages: languages),
  );

  @override
  State<OrderTypeDialog> createState() => _OrderTypeDialogState();
}

class _OrderTypeDialogState extends State<OrderTypeDialog> {
  late final _nameEn = TextEditingController(text: widget.config.nameEn);
  late final _nameAr = TextEditingController(
    text: initialArabicName(
      languages: widget.languages,
      nameAr: widget.config.nameAr,
      nameEn: widget.config.nameEn,
    ),
  );

  late bool _table = widget.config.requiresTable;
  late bool _customer = widget.config.requiresCustomer;
  late bool _address = widget.config.requiresAddress;
  late bool _active = widget.config.isActive;
  String? _problem;

  @override
  void dispose() {
    _nameEn.dispose();
    _nameAr.dispose();
    super.dispose();
  }

  void _save() {
    if (!hasRequiredName(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
    )) {
      setState(() => _problem = context.strings.orderTypeNeedsAName);
      return;
    }

    final names = resolveNames(
      languages: widget.languages,
      typedEn: _nameEn.text,
      typedAr: _nameAr.text,
      previousEn: widget.config.nameEn,
      previousAr: widget.config.nameAr,
    );

    Navigator.of(context).pop(
      OrderTypeConfig(
        type: widget.config.type,
        nameEn: names.nameEn,
        nameAr: names.nameAr.isEmpty ? null : names.nameAr,
        requiresTable: _table,
        requiresCustomer: _customer,
        requiresAddress: _address,
        isActive: _active,
        sortOrder: widget.config.sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.config.nameEn,
                      style: PosText.ui(
                        size: 18,
                        weight: FontWeight.w800,
                        color: palette.ink,
                      ),
                    ),
                  ),
                  // The code, shown and not editable. It is what the enum, the
                  // ticket rows and every report already say.
                  MonoCode(widget.config.type.wire, size: 12),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  if (widget.languages.showsEnglish) ...[
                    NameDirection(
                      languages: widget.languages,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MicroLabel(
                            widget.languages.nameStrings(strings).orderTypeName,
                          ),
                          const SizedBox(height: PosSpace.xs),
                          TextField(
                            key: const Key('order-type-name'),
                            controller: _nameEn,
                            onChanged: (_) => setState(() => _problem = null),
                            style: PosText.ui(size: 15, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: PosSpace.md),
                  ],
                  if (widget.languages.showsArabic) ...[
                    NameDirection(
                      languages: widget.languages,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MicroLabel(
                            widget.languages == ContentLanguages.arabic
                                ? widget.languages
                                      .nameStrings(strings)
                                      .orderTypeName
                                : strings.optionalField(strings.tenderNameAr),
                          ),
                          const SizedBox(height: PosSpace.xs),
                          TextField(
                            key: const Key('order-type-name-ar'),
                            controller: _nameAr,
                            onChanged: (_) => setState(() => _problem = null),
                            style: PosText.ui(size: 15, color: palette.ink),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),

                  _Switch(
                    boxKey: const Key('order-type-table'),
                    value: _table,
                    title: strings.orderTypeRequiresTable,
                    hint: strings.orderTypeRequiresTableHint,
                    onChanged: (v) => setState(() => _table = v),
                  ),
                  _Switch(
                    boxKey: const Key('order-type-customer'),
                    value: _customer,
                    title: strings.orderTypeRequiresCustomer,
                    hint: strings.orderTypeRequiresCustomerHint,
                    onChanged: (v) => setState(() => _customer = v),
                  ),
                  _Switch(
                    boxKey: const Key('order-type-address'),
                    value: _address,
                    title: strings.orderTypeRequiresAddress,
                    hint: strings.orderTypeRequiresAddressHint,
                    onChanged: (v) => setState(() => _address = v),
                  ),
                  const SizedBox(height: PosSpace.sm),
                  _Switch(
                    boxKey: const Key('order-type-active'),
                    value: _active,
                    title: strings.orderTypeOffered,
                    hint: strings.orderTypeOfferedHint,
                    onChanged: (v) => setState(() => _active = v),
                  ),

                  if (_problem != null) ...[
                    const SizedBox(height: PosSpace.md),
                    Text(
                      _problem!,
                      style: PosText.ui(size: 12.5, color: palette.danger),
                    ),
                  ],
                  const SizedBox(height: PosSpace.lg),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PosSpace.lg),
              decoration: BoxDecoration(
                border: BorderDirectional(top: palette.resting),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: PosButton(
                      label: strings.cancel,
                      border: Border.fromBorderSide(palette.resting),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: PosSpace.sm),
                  Expanded(
                    child: PosButton(
                      key: const Key('order-type-save'),
                      label: strings.save,
                      background: palette.ink,
                      foreground: palette.onInk,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.boxKey,
    required this.value,
    required this.title,
    required this.hint,
    required this.onChanged,
  });

  final Key boxKey;
  final bool value;
  final String title;
  final String hint;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: boxKey,
    value: value,
    onChanged: onChanged,
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: PosText.ui(size: 13.5, color: context.pos.body),
    ),
    subtitle: Text(
      hint,
      style: PosText.ui(size: 11.5, color: context.pos.muted, height: 1.4),
    ),
  );
}
