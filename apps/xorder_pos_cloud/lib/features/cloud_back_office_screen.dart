import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:shared_module/app/providers.dart';
import 'package:shared_module/core/config/deployment.dart';
import 'package:shared_module/core/l10n/app_strings.dart';
import 'package:shared_module/core/ui/theme.dart';
import 'package:shared_module/core/ui/tokens.dart';
import 'package:shared_module/core/ui/widgets/pos_widgets.dart';

/// What a CLOUD till shows where an offline till shows its back office.
///
/// **CB-07, owner decision 27 Sep 2026: the whole back office, not part of
/// it.** `BACKOFFICE_TO_CLOUD.md` §2 already said there is one author per row
/// and no merge path — on a cloud terminal the platform authors and
/// `BootstrapSeeder` overwrites. The Management panes were built for the
/// offline product, where the desktop is the only back office there is. On
/// cloud they were a second set of controls over rows the till does not own:
/// an edit made here survived until the next bundle landed on top of it,
/// which is worse than no edit at all, because it looked like it had worked.
///
/// So this screen is deliberately a signpost and not a smaller back office.
/// It carries no panes, offers no edits, and does not try to open a browser —
/// a till is a fixed machine at a counter and the manager's dashboard is
/// wherever they already sign in. It names the address and lets them copy it.
class CloudBackOfficeScreen extends ConsumerWidget {
  const CloudBackOfficeScreen({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.strings;
    final config = ref.watch(deploymentProvider);
    final address = dashboardAddress(config);

    return Scaffold(
      backgroundColor: context.pos.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: PosSize.topBar,
            padding: const EdgeInsets.symmetric(horizontal: PosSpace.s14),
            decoration: BoxDecoration(
              color: context.pos.shell,
              border: Border(bottom: context.pos.accentBorder),
            ),
            child: Row(
              children: [
                PosButton(
                  label: s.backArrow,
                  height: 38,
                  foreground: context.pos.shellText,
                  border: Border.fromBorderSide(context.pos.shellBorder),
                  onPressed: onClose,
                ),
                const SizedBox(width: PosSpace.lg),
                Text(
                  s.management,
                  style: PosText.ui(
                    size: 15,
                    weight: FontWeight.w700,
                    color: context.pos.shellText,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: const EdgeInsets.all(PosSpace.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MicroLabel(s.backOfficeIsOnTheCloud),
                      const SizedBox(height: PosSpace.md),
                      Text(
                        s.backOfficeIsOnTheCloudHelp,
                        style: PosText.ui(
                          size: 13.5,
                          color: context.pos.body,
                          height: 1.6,
                        ),
                      ),
                      if (address != null) ...[
                        const SizedBox(height: PosSpace.xl),
                        MicroLabel(s.dashboardAddress),
                        const SizedBox(height: PosSpace.sm),
                        SelectableText(
                          address,
                          style: PosText.mono(
                            size: 14,
                            color: context.pos.ink,
                          ),
                        ),
                        const SizedBox(height: PosSpace.lg),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: PosButton(
                            label: s.copyAddress,
                            background: context.pos.ink,
                            foreground: context.pos.onInk,
                            padding: const EdgeInsets.symmetric(
                              horizontal: PosSpace.xl,
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: address),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(s.addressCopied)),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Where this business's dashboard lives, or null when the till cannot say.
///
/// Built from what the till already knows rather than from a new field on the
/// bundle: the platform address it talks to, and its own tenant slug. A cloud
/// dashboard is served on the business's own subdomain (`apps/web`'s router
/// puts it at `/admin`, because on a business subdomain the bare root is the
/// public menu).
///
/// **Null rather than a guess.** A till with no platform address or no slug
/// cannot name the dashboard, and an address that is wrong is worse than none:
/// a manager typing it in gets a certificate warning or somebody else's
/// business. The screen simply omits the line.
String? dashboardAddress(DeploymentConfig config) {
  final base = config.baseUrl?.trim();
  final slug = config.tenantSlug?.trim();
  if (base == null || base.isEmpty || slug == null || slug.isEmpty) return null;

  final uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty) return null;

  // A host that already names the tenant is left alone — the operator typed
  // the business's own address into setup and it is the one that works.
  final host = uri.host.startsWith('$slug.') ? uri.host : '$slug.${uri.host}';
  return Uri(
    scheme: uri.scheme.isEmpty ? 'https' : uri.scheme,
    host: host,
    port: uri.hasPort ? uri.port : null,
    path: '/admin',
  ).toString();
}
