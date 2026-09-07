import 'package:flutter/material.dart';

import '../../../domain/services/authorization.dart';
import '../tokens.dart';

/// How a control the current person may not use should appear.
///
/// Three behaviours rather than the usual two, because *"no"* and *"not without
/// a manager"* lead a cashier to do completely different things. Getting this
/// wrong costs service time on every order: a cashier who cannot tell whether a
/// manager can fix something either fetches one for nothing, or gives up on
/// something a manager would have approved in four seconds.
enum GateBehaviour {
  /// No access, and no override exists. The control is **absent** — not greyed,
  /// no tooltip, not in the focus tree, no trace. The person never learns it is
  /// there.
  ///
  /// For capabilities the patterns handoff classifies `CRITICAL`: database
  /// restore, licence, server configuration. Showing a cashier a greyed-out
  /// *Restore database* teaches them that the till has a restore button, which
  /// is knowledge with no use and one misuse.
  hidden,

  /// The control exists and this person cannot use it, and **nobody at the till
  /// can lend it to them**. Visible, muted, dashed, and it says why.
  ///
  /// Used sparingly. Its job is to stop somebody hunting for a feature that is
  /// switched off at this branch rather than missing.
  disabled,

  /// The control is **fully enabled and looks it**. Activating it opens the
  /// manager-approval dialog rather than performing the act.
  ///
  /// This is the case that must not be styled as a refusal. A cashier at a
  /// queue needs to press *Discount* and have a manager arrive at the prompt —
  /// not read a disabled tooltip and go looking for one first.
  approval,
}

/// Renders a permission-bearing control in the one correct way for the person
/// holding the till.
///
/// **This is the only correct way to render a gated control.** A screen that
/// greys a button out on its own has made a private decision about which of the
/// three behaviours applies, and two screens making that decision differently
/// for the same capability is how a permission model stops meaning anything.
///
/// The gate is a *presentation* of a decision, never the decision itself.
/// [Authorization.check] answers whether the act is permitted, and the
/// repository re-checks before it writes — so a gate that is wrong can only
/// ever be wrong in the harmless direction, showing less than is allowed.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.behaviour,
    required this.child,
    this.disabledReason,
    this.onApprovalNeeded,
  });

  /// Build a gate from an [Authorization] decision.
  ///
  /// [deniedBehaviour] decides what a flat `Denied` looks like, and the caller
  /// has to supply it because the information that would settle it — the
  /// capability's risk level — does not exist in the schema yet. It arrives in
  /// Wave C as `pos_permissions.risk_level`, at which point this factory can
  /// read it and the parameter becomes a default rather than a requirement.
  ///
  /// Until then the rule to apply by hand is the handoff's: `CRITICAL` is
  /// [GateBehaviour.hidden], everything else a person could reasonably discover
  /// is [GateBehaviour.disabled].
  factory PermissionGate.forDecision(
    PermissionDecision decision, {
    Key? key,
    required Widget child,
    required GateBehaviour deniedBehaviour,
    String? disabledReason,
    VoidCallback? onApprovalNeeded,
  }) => PermissionGate(
    key: key,
    behaviour: switch (decision) {
      Allowed() => GateBehaviour.approval,
      NeedsOverride() => GateBehaviour.approval,
      Denied() => deniedBehaviour,
    },
    disabledReason: disabledReason,
    // An `Allowed` decision must not route through the approval dialog — there
    // is nothing to approve. The caller's own handler is already on the child,
    // so passing null here leaves the child to do its own job.
    onApprovalNeeded: decision is NeedsOverride ? onApprovalNeeded : null,
    child: child,
  );

  final GateBehaviour behaviour;

  /// The control as it looks when the person may use it.
  final Widget child;

  /// Why this is unavailable, in the words a cashier would use — *"Price
  /// override is off for cashiers at this branch."* Announced to screen readers
  /// and shown on hover and long-press.
  ///
  /// Only read in [GateBehaviour.disabled]. A reason on a hidden control would
  /// be a reason nobody can reach, and a reason on an enabled one is noise.
  final String? disabledReason;

  /// Opens the manager-approval flow. Called **instead of** the child's own
  /// action, never after it.
  final VoidCallback? onApprovalNeeded;

  @override
  Widget build(BuildContext context) => switch (behaviour) {
    // Not `Visibility(visible: false)`, not `Opacity(0)`: both keep the widget
    // in the tree, and a control that is merely transparent is still reachable
    // by Tab and still announced by a screen reader.
    GateBehaviour.hidden => const SizedBox.shrink(),
    GateBehaviour.disabled => _Disabled(
      reason: disabledReason,
      child: child,
    ),
    GateBehaviour.approval => _Approval(
      onApprovalNeeded: onApprovalNeeded,
      child: child,
    ),
  };
}

/// Visible, unusable, and explicit about why.
///
/// Stays in the focus order deliberately. A control removed from the Tab order
/// is one a keyboard user cannot discover at all, which turns "disabled" into
/// "hidden" for exactly the people least able to work around it.
class _Disabled extends StatelessWidget {
  const _Disabled({required this.child, this.reason});

  final Widget child;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final palette = context.pos;

    final body = Semantics(
      enabled: false,
      hint: reason,
      child: MouseRegion(
        cursor: SystemMouseCursors.forbidden,
        child: CustomPaint(
          painter: _DashedBorderPainter(color: palette.lineStrong),
          child: ColoredBox(
            color: palette.page,
            child: Opacity(
              // Muted rather than removed. The label has to stay readable —
              // the point of showing this at all is that the person can see
              // what the control would do.
              opacity: 0.55,
              // Swallows every pointer event before it reaches the child, so a
              // child that manages its own `onTap` cannot fire through the gate.
              child: IgnorePointer(child: child),
            ),
          ),
        ),
      ),
    );

    // Focusable, so Tab reaches it and the hint is announced, but it cannot be
    // activated: there is no action bound to it.
    final focusable = Focus(canRequestFocus: true, child: body);

    return reason == null
        ? focusable
        : Tooltip(message: reason!, child: focusable);
  }
}

/// Enabled, and it looks it. Activation opens the approval prompt.
class _Approval extends StatelessWidget {
  const _Approval({required this.child, this.onApprovalNeeded});

  final Widget child;
  final VoidCallback? onApprovalNeeded;

  @override
  Widget build(BuildContext context) {
    // Nothing to intercept — the person holds the capability outright, so the
    // child keeps its own behaviour untouched.
    if (onApprovalNeeded == null) return child;

    return Stack(
      children: [
        // The child renders exactly as it would if the person were permitted.
        // That is the requirement: a control needing approval must be
        // indistinguishable from one that does not, or the cashier hesitates.
        IgnorePointer(child: child),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onApprovalNeeded,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

/// A 1px dashed rectangle.
///
/// Dashed is the one border *style* in this product, and it is used for exactly
/// one thing: a control that exists and is not available to you. It carries
/// meaning that neither of the two solid weights can — `1px` solid is a resting
/// surface and `2px` solid is a selected one, and neither says *unavailable*.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  /// 4 on, 3 off. Short enough that the dashes read as a texture rather than a
  /// row of marks at the 44px control height this is nearly always drawn at.
  static const dash = 4.0;
  static const gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    void line(Offset from, Offset to) {
      final total = (to - from).distance;
      if (total == 0) return;
      final step = (to - from) / total;
      var travelled = 0.0;
      while (travelled < total) {
        final end = (travelled + dash).clamp(0.0, total);
        canvas.drawLine(from + step * travelled, from + step * end, paint);
        travelled = end + gap;
      }
    }

    final topRight = Offset(size.width, 0);
    final bottomRight = Offset(size.width, size.height);
    final bottomLeft = Offset(0, size.height);

    line(Offset.zero, topRight);
    line(topRight, bottomRight);
    line(bottomRight, bottomLeft);
    line(bottomLeft, Offset.zero);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}
