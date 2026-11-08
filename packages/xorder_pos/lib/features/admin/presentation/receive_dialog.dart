import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/money/quantity.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/mono_amount.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import 'admin_messages.dart';
import '../../../domain/models/purchase_order.dart';

/// Booking in what actually arrived.
///
/// **Every box starts at what is still owed, not at zero.** The overwhelmingly
/// common case is that the delivery matches the order, and a form that made
/// somebody retype eight numbers to say "all of it came" is a form they will
/// stop using by Thursday. Changing one is how a short delivery gets recorded.
class ReceiveDialog extends StatefulWidget {
  const ReceiveDialog({super.key, required this.order});

  final PurchaseOrder order;

  /// Returns what arrived, by line id.
  static Future<Map<int, Quantity>?> show(
    BuildContext context, {
    required PurchaseOrder order,
  }) => showDialog<Map<int, Quantity>>(
    context: context,
    builder: (_) => ReceiveDialog(order: order),
  );

  @override
  State<ReceiveDialog> createState() => _ReceiveDialogState();
}

class _ReceiveDialogState extends State<ReceiveDialog> {
  late final Map<int, TextEditingController> _boxes = {
    for (final line in widget.order.lines)
      line.id: TextEditingController(text: line.outstanding.format()),
  };

  @override
  void dispose() {
    for (final c in _boxes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<int, Quantity> get _booked {
    final booked = <int, Quantity>{};
    for (final line in widget.order.lines) {
      final typed = Quantity.tryParse(
        _boxes[line.id]!.text,
        unit: line.ordered.unit,
      );
      if (typed != null && typed.milli > 0) booked[line.id] = typed;
    }
    return booked;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.pos;
    final booked = _booked;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PosSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.purchaseReceiveInto(widget.order.reference),
                    style: PosText.ui(
                      size: 18,
                      weight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: PosSpace.xs),
                  Text(
                    strings.purchaseReceiveHint,
                    style: PosText.ui(
                      size: 12.5,
                      color: palette.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
                children: [
                  Row(
                    children: [
                      Expanded(flex: 4, child: MicroLabel(strings.purchaseItem)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseOrdered)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseOutstanding)),
                      Expanded(flex: 2, child: MicroLabel(strings.purchaseArrived)),
                    ],
                  ),
                  const SizedBox(height: PosSpace.sm),
                  for (final line in widget.order.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              line.description,
                              style: PosText.ui(size: 13.5, color: palette.ink),
                            ),
                          ),
                          // The quantity is mono and left-to-right; the unit is
                          // ordinary text, because in Arabic it is a word
                          // ("كجم") and forcing it into an LTR mono run is how
                          // it comes out reversed beside the number.
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                MonoCode(line.ordered.format(), size: 12.5),
                                const SizedBox(width: 4),
                                Text(
                                  AdminText.unit(strings, line.ordered.unit),
                                  style: PosText.ui(
                                    size: 11.5,
                                    color: palette.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: MonoCode(
                              line.outstanding.format(),
                              size: 12.5,
                              color: line.isFullyReceived
                                  ? palette.ok
                                  : palette.warn,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              key: Key('receive-${line.id}'),
                              controller: _boxes[line.id],
                              onChanged: (_) => setState(() {}),
                              textDirection: TextDirection.ltr,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: PosText.mono(size: 14, color: palette.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                    flex: 2,
                    child: PosButton(
                      key: const Key('receive-confirm'),
                      label: strings.purchaseBookIn(booked.length),
                      background: booked.isEmpty
                          ? palette.ctaDisabled
                          : palette.accent,
                      foreground: Colors.white,
                      fontWeight: FontWeight.w700,
                      onPressed: booked.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(booked),
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
