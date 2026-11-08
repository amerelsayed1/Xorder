import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../core/ui/widgets/pos_widgets.dart';
import '../../../domain/models/business_logo.dart';
import '../../../domain/models/permissions.dart';
import '../../../domain/models/shift.dart';
import 'admin_messages.dart';
import 'admin_pane_bits.dart';

/// Where the card gets a picture from. Null means the person cancelled; bytes
/// that are not a logo are the repository's to refuse, not the picker's.
typedef LogoFileSource = Future<Uint8List?> Function();

/// The business logo, in Settings › General (XORD-021).
///
/// An offline install authors it here, under `business.branding.manage`; a
/// cloud till's comes from the platform and is shown read-only, as its order
/// types and menu languages are. The picture is held in the branch database, so
/// what is previewed here is exactly what the start screen draws.
class BusinessLogoCard extends ConsumerStatefulWidget {
  const BusinessLogoCard({required this.admin, this.source, super.key});

  final PosStaff admin;

  /// Replaces the file dialog. Tests hand bytes in; production leaves it null.
  final LogoFileSource? source;

  @override
  ConsumerState<BusinessLogoCard> createState() => _BusinessLogoCardState();
}

class _BusinessLogoCardState extends ConsumerState<BusinessLogoCard> {
  bool _busy = false;
  String? _problem;
  String? _note;

  /// At most [BusinessLogoRules.maxBytes] + 1 bytes are read, so a file that is
  /// too big is refused as too big without being loaded whole.
  static Future<Uint8List?> _pick() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final path = picked?.path;
    if (path == null) return null;
    final chunks = <int>[];
    await for (final chunk in File(
      path,
    ).openRead(0, BusinessLogoRules.maxBytes + 1)) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  Future<void> _choose() async {
    final repository = ref.read(businessLogoRepositoryProvider);
    if (repository == null || _busy) return;
    final strings = context.strings;

    setState(() {
      _busy = true;
      _problem = null;
      _note = null;
    });

    final Uint8List? bytes;
    try {
      bytes = await (widget.source ?? _pick)();
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = strings.businessLogoReadFailed;
      });
      return;
    }
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      return;
    }

    final result = await repository.save(bytes, by: widget.admin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.succeeded) {
        _note = strings.businessLogoSavedNote;
      } else {
        _problem = AdminText.refusal(strings, result.refusal!);
      }
    });
    if (result.succeeded) ref.invalidate(businessLogoProvider);
  }

  Future<void> _remove() async {
    final repository = ref.read(businessLogoRepositoryProvider);
    if (repository == null || _busy) return;
    final strings = context.strings;

    setState(() {
      _busy = true;
      _problem = null;
      _note = null;
    });
    final result = await repository.remove(by: widget.admin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.succeeded) {
        _note = strings.businessLogoRemovedNote;
      } else {
        _problem = AdminText.refusal(strings, result.refusal!);
      }
    });
    if (result.succeeded) ref.invalidate(businessLogoProvider);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final logo = ref.watch(businessLogoProvider).valueOrNull;
    final platformOwned = ref.watch(businessLogoRepositoryProvider) == null;
    final mayChange = widget.admin.can(PosCapability.brandingManage);
    final editable = !platformOwned && mayChange;

    return SettingsCard(
      key: const Key('business-logo'),
      title: strings.businessLogoTitle,
      hint: strings.businessLogoHint,
      children: [
        if (platformOwned)
          PlatformOwnedNotice(text: strings.businessLogoFromPlatform)
        else if (!mayChange)
          PlatformOwnedNotice(text: strings.businessLogoNeedPermission),
        if (platformOwned || !mayChange) const SizedBox(height: PosSpace.sm),
        _Preview(logo: logo, empty: strings.businessLogoNone),
        if (editable) ...[
          const SizedBox(height: PosSpace.md),
          // A Wrap, not a Row: the card is 420 wide, and "Replace picture" and
          // "Remove logo" do not fit side by side in every language.
          Wrap(
            spacing: PosSpace.sm,
            runSpacing: PosSpace.sm,
            children: [
              PosButton(
                key: const Key('business-logo-choose'),
                label: logo == null
                    ? strings.businessLogoChoose
                    : strings.businessLogoReplace,
                border: Border.fromBorderSide(context.pos.resting),
                onPressed: _busy ? null : _choose,
              ),
              if (logo != null)
                PosButton(
                  key: const Key('business-logo-remove'),
                  label: strings.businessLogoRemove,
                  foreground: context.pos.danger,
                  border: Border.fromBorderSide(context.pos.resting),
                  onPressed: _busy ? null : _remove,
                ),
            ],
          ),
        ],
        if (_problem != null) ...[
          const SizedBox(height: PosSpace.sm),
          Text(
            _problem!,
            key: const Key('business-logo-problem'),
            style: PosText.ui(size: 12.5, color: context.pos.danger),
          ),
        ],
        if (_note != null) ...[
          const SizedBox(height: PosSpace.sm),
          Text(
            _note!,
            key: const Key('business-logo-note'),
            style: PosText.ui(size: 12.5, color: context.pos.muted),
          ),
        ],
      ],
    );
  }
}

/// The logo on the same white plate the start screen puts it on, or the
/// sentence saying there is none. A picture that will not decode is shown as
/// "none": the card must never be the thing that breaks.
class _Preview extends StatelessWidget {
  const _Preview({required this.logo, required this.empty});

  final BusinessLogo? logo;
  final String empty;

  @override
  Widget build(BuildContext context) {
    Widget none() => Text(
      empty,
      key: const Key('business-logo-none'),
      style: PosText.ui(size: 12.5, color: context.pos.muted),
    );
    final held = logo;
    if (held == null) return none();

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        key: const Key('business-logo-preview'),
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 110),
        padding: const EdgeInsets.all(PosSpace.sm),
        decoration: BoxDecoration(
          color: context.pos.logoPlate,
          border: Border.fromBorderSide(context.pos.resting),
        ),
        child: Image.memory(
          held.bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: 440,
          errorBuilder: (context, error, stack) => none(),
        ),
      ),
    );
  }
}
