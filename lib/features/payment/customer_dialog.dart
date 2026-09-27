import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../core/ui/widgets/pos_widgets.dart';
import '../../domain/models/customer.dart';

/// Finding a regular, or adding one, at the moment the money is taken.
///
/// **One box, not two screens.** A cashier is mid-transaction with somebody
/// talking to them: they type what they have — a name, or the last four digits
/// of a number read over the counter — and either the person is in the list or
/// they are not. When they are not, the same text becomes the start of a new
/// customer rather than being thrown away and retyped into a second form.
///
/// **Local, always** (POS-BE-014, owner decision 27 Sep 2026). The directory
/// arrives in the bootstrap bundle and is searched in the branch database, so
/// this works during the outage when the counter is busiest. A customer
/// created here is written locally and uploaded by the outbox like a sale.
class CustomerDialog extends ConsumerStatefulWidget {
  const CustomerDialog({super.key, this.attached});

  /// Who is already on the ticket, if anybody — so the dialog can offer to
  /// take them off again.
  final PosCustomer? attached;

  /// Returns the customer to attach, or null when nothing changed.
  ///
  /// [CustomerChoice.none] is a real answer and means "take the current one
  /// off", which a bare null cannot say.
  static Future<CustomerChoice?> show(
    BuildContext context, {
    PosCustomer? attached,
  }) => showDialog<CustomerChoice>(
    context: context,
    builder: (_) => CustomerDialog(attached: attached),
  );

  @override
  ConsumerState<CustomerDialog> createState() => _CustomerDialogState();
}

/// What the dialog came back with.
class CustomerChoice {
  const CustomerChoice(this.customer);
  const CustomerChoice.none() : customer = null;

  final PosCustomer? customer;
}

class _CustomerDialogState extends ConsumerState<CustomerDialog> {
  final _query = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  List<PosCustomer> _results = const [];
  bool _adding = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final found = await ref.read(customersRepositoryProvider).search(query);
    if (!mounted) return;
    setState(() => _results = found);
  }

  /// What the cashier typed, read as a number if it looks like one.
  ///
  /// Somebody searching "01016943505" and finding nobody is about to create
  /// that customer, and the number is already typed — carrying it across is
  /// the difference between two fields and three.
  void _startAdding() {
    final typed = _query.text.trim();
    final digits = PosCustomer.normalisePhone(typed);
    setState(() {
      _adding = true;
      _error = null;
      if (digits.length >= 6 && digits.length == typed.replaceAll(' ', '').length) {
        _phone.text = typed;
        _query.clear();
      }
    });
  }

  Future<void> _save() async {
    final name = _query.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || PosCustomer.normalisePhone(phone).isEmpty) {
      setState(() => _error = context.strings.customerNeedsNameAndPhone);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref
          .read(customersRepositoryProvider)
          .upsert(name: name, phone: phone, address: _address.text);
      if (!mounted) return;
      Navigator.of(context).pop(CustomerChoice(saved));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final palette = context.pos;

    return Dialog(
      backgroundColor: palette.surface,
      shape: const RoundedRectangleBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Padding(
            padding: const EdgeInsets.all(PosSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _adding ? s.addCustomer : s.whoIsThisFor,
                  style: PosText.ui(
                    size: 18,
                    weight: FontWeight.w800,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: PosSpace.md),
                _field(
                  controller: _query,
                  hint: _adding ? s.customerName : s.searchNameOrPhone,
                  autofocus: true,
                  onChanged: _adding ? null : _search,
                ),
                if (_adding) ...[
                  const SizedBox(height: PosSpace.sm),
                  _field(controller: _phone, hint: s.customerPhone),
                  const SizedBox(height: PosSpace.sm),
                  _field(controller: _address, hint: s.customerAddress),
                ],
                if (_error case final error?) ...[
                  const SizedBox(height: PosSpace.sm),
                  Text(
                    error,
                    style: PosText.ui(size: 12.5, color: palette.danger),
                  ),
                ],
                if (!_adding) ...[
                  const SizedBox(height: PosSpace.sm),
                  Flexible(
                    child: _results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: PosSpace.lg,
                            ),
                            child: Text(
                              s.noCustomerFound,
                              style: PosText.ui(
                                size: 13,
                                color: palette.muted,
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final customer = _results[i];
                              return InkWell(
                                onTap: () => Navigator.of(context)
                                    .pop(CustomerChoice(customer)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: PosSpace.sm,
                                    horizontal: PosSpace.xs,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        customer.name,
                                        style: PosText.ui(
                                          size: 14,
                                          weight: FontWeight.w700,
                                          color: palette.ink,
                                        ),
                                      ),
                                      Text(
                                        customer.address == null
                                            ? customer.phone
                                            : '${customer.phone} · '
                                                  '${customer.address}',
                                        style: PosText.ui(
                                          size: 12,
                                          color: palette.muted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: PosSpace.md),
                Row(
                  children: [
                    if (widget.attached != null && !_adding) ...[
                      Expanded(
                        child: PosButton(
                          label: s.removeCustomer,
                          border: Border.fromBorderSide(palette.resting),
                          onPressed: () => Navigator.of(context)
                              .pop(const CustomerChoice.none()),
                        ),
                      ),
                      const SizedBox(width: PosSpace.sm),
                    ],
                    Expanded(
                      child: PosButton(
                        label: s.cancel,
                        border: Border.fromBorderSide(palette.resting),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: PosSpace.sm),
                    Expanded(
                      flex: 2,
                      child: PosButton(
                        label: _adding ? s.save : s.addCustomer,
                        background: palette.accent,
                        foreground: Colors.white,
                        fontWeight: FontWeight.w700,
                        onPressed: _busy
                            ? null
                            : (_adding ? _save : _startAdding),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool autofocus = false,
    void Function(String)? onChanged,
  }) {
    final palette = context.pos;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      style: PosText.ui(size: 14, color: palette.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: PosText.ui(size: 14, color: palette.muted),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: palette.resting,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: palette.resting,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: palette.accentBorder,
        ),
      ),
    );
  }
}
