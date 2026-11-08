/// What the setup wizard decided about *this* terminal.
///
/// Kept separate from `sessionProvider`, which describes the signed-in person
/// and comes from the server. Branch and till name are properties of the
/// machine, chosen once at setup, and must survive a different cashier signing
/// in — so they are not read off the session.
///
/// Lives here rather than beside its controller because it is written to disk:
/// a profile that only existed in memory made the wizard a first-run screen
/// that ran on every run, and regenerated [terminalId] — and therefore the
/// licence fingerprint — each time.
class TerminalProfile {
  const TerminalProfile({
    this.branchId,
    this.branchName,
    this.terminalName,
    this.terminalId,
    this.installationId,
    this.provisioned = false,
    this.businessId,
    this.branchCode,
  });

  /// Stamped on every row this till writes. Comes from provisioning, never from
  /// anything the cashier can type.
  final int? businessId;

  /// Invoice prefix (POS-BE-005).
  final String? branchCode;

  final int? branchId;
  final String? branchName;
  final String? terminalName;

  /// Generated once on this device and never reissued.
  ///
  /// `TerminalIdFingerprint` hashes it for the licence, so a terminal that
  /// invented a new one each launch would be a different machine to the licence
  /// server every morning — and its activation would never stick.
  final String? terminalId;

  /// Stable identity of this physical installation, independent of the server
  /// terminal row assigned later by pairing/provisioning.
  final String? installationId;

  /// True when this terminal was created in the dashboard and claimed with a
  /// pairing code, rather than registering itself. Worth keeping: a provisioned
  /// terminal's id came from the server, so it is the same row Super Admin is
  /// already tracking (POS-BE-023).
  final bool provisioned;

  /// True only when this terminal can identify every row it writes.
  ///
  /// A name alone is display copy, not a usable terminal registration. Older
  /// builds accepted it as "set", which let a failed manual registration save
  /// setup and route to a start screen backed by unconfigured repositories.
  bool get isSet =>
      (terminalName?.isNotEmpty ?? false) &&
      businessId != null &&
      branchId != null &&
      (branchCode?.isNotEmpty ?? false) &&
      (terminalId?.isNotEmpty ?? false);

  Map<String, Object?> toJson() => {
    'business_id': businessId,
    'branch_code': branchCode,
    'branch_id': branchId,
    'branch_name': branchName,
    'terminal_name': terminalName,
    'terminal_id': terminalId,
    'installation_id': installationId,
    'provisioned': provisioned,
  };

  /// Tolerant by design: a till must boot holding a profile written by a build
  /// that knew one field more or less than this one does.
  static TerminalProfile fromJson(Map<String, Object?> json) => TerminalProfile(
    // `restaurant_id` is what a profile saved before the rename to "business"
    // (2026-11-07) holds; read so an installed till stays provisioned.
    businessId: ((json['business_id'] ?? json['restaurant_id']) as num?)?.toInt(),
    branchCode: json['branch_code'] as String?,
    branchId: (json['branch_id'] as num?)?.toInt(),
    branchName: json['branch_name'] as String?,
    terminalName: json['terminal_name'] as String?,
    terminalId: json['terminal_id'] as String?,
    // Older installations used the server terminal id as their device
    // fingerprint. Preserve that identity across an upgrade.
    installationId:
        json['installation_id'] as String? ?? json['terminal_id'] as String?,
    provisioned: json['provisioned'] as bool? ?? false,
  );
}
