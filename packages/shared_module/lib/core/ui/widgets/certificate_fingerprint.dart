import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/lan_tls.dart';
import '../../l10n/app_strings.dart';
import '../theme.dart';
import '../tokens.dart';
import 'pos_widgets.dart';

/// A certificate's SHA-256 the way a technician compares it: mono, left to
/// right in either language, selectable, and one button from the clipboard.
///
/// One widget for both ends of the comparison — the main device's Management
/// pane and the child's wizard — so the two screens a person holds side by
/// side cannot format the same 32 bytes differently. A fingerprint that
/// *looks* different because one screen grouped it in fours is a pairing
/// somebody abandons, or worse, confirms without reading.
class CertificateFingerprint extends StatelessWidget {
  const CertificateFingerprint({super.key, required this.sha256, this.notAfter});

  /// Lower-case hex, as [LanTls] keeps it.
  final String sha256;

  /// Shown when known: the installer's certificate lives 825 days, and its
  /// end is something to see coming rather than meet.
  final DateTime? notAfter;

  static String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final utc = value.toUtc();
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pos = context.pos;
    final shown = LanTls.formatFingerprint(sha256);

    return Container(
      padding: const EdgeInsets.all(PosSpace.md),
      decoration: BoxDecoration(
        color: pos.surface,
        border: Border.fromBorderSide(pos.resting),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Latin hex in an Arabic sentence would be reordered pair by pair;
          // the comparison is only possible if both screens read left to right.
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              shown,
              key: const Key('certificate-fingerprint'),
              style: PosText.mono(
                size: 13,
                weight: FontWeight.w600,
                color: pos.ink,
              ),
            ),
          ),
          if (notAfter case final until?) ...[
            const SizedBox(height: PosSpace.sm),
            Row(
              children: [
                Text(
                  strings.certificateValidUntil,
                  style: PosText.ui(size: 12, color: pos.muted),
                ),
                const SizedBox(width: PosSpace.sm),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    _date(until),
                    style: PosText.mono(size: 12, color: pos.ink),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: PosSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PosButton(
              key: const Key('certificate-fingerprint-copy'),
              label: strings.copyFingerprint,
              border: Border.fromBorderSide(BorderSide(color: pos.inkWarm)),
              padding: const EdgeInsets.symmetric(horizontal: PosSpace.lg),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shown));
                if (context.mounted) posToast(context, strings.fingerprintCopied);
              },
            ),
          ),
        ],
      ),
    );
  }
}
