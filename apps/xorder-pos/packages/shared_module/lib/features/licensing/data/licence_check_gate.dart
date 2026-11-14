import '../../../data/cloud/cloud_api.dart';

/// One licence check at a time, and not another one for a minute.
///
/// The audit (S3-4) counted three identical `POST /api/pos/license/check` in
/// the first second after launch. Nobody asked three times: the entitlement
/// provider asks once, but it watches the licence service, and the licence
/// service is rebuilt whenever anything it is assembled from settles — the
/// device token coming out of the vault, the deployment config, the cloud
/// API — and each rebuild was a new service with no memory of the one before.
///
/// So the memory lives here, in an object that outlives the services: a
/// provider with no dependencies holds one of these for the process, and
/// every service built during that process asks through it.
///
/// Two rules, both small:
///
/// * **One in flight.** A second ask while the first has not answered waits
///   for the same answer rather than sending its own request.
/// * **One a minute.** An answer — including "no answer", so an offline till
///   does not retry on every rebuild either — stands for [window] from when
///   it was asked for. Short on purpose: the start screen re-reads before
///   each shift opens so a renewal lands without a restart, and a minute is
///   nothing against a shift. [force] skips the window for a caller that was
///   told to ask now.
///
/// Not a cache of the verdict: the service still interprets every reply and
/// keeps its own on-disk record of the last definite one. This only stops
/// the same question leaving the till twice.
class LicenceCheckGate {
  LicenceCheckGate({this.window = const Duration(seconds: 60)});

  final Duration window;

  Future<CloudReply?>? _inFlight;
  CloudReply? _last;
  DateTime? _askedAt;

  /// How many requests actually left. For tests, and for nothing else.
  int sent = 0;

  /// [request] is sent unless one is in flight or one was answered within
  /// [window] of [now]; either way the caller gets the one answer.
  Future<CloudReply?> ask(
    Future<CloudReply?> Function() request, {
    required DateTime now,
    bool force = false,
  }) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final askedAt = _askedAt;
    if (!force &&
        askedAt != null &&
        !now.isBefore(askedAt) &&
        now.difference(askedAt) < window) {
      return Future.value(_last);
    }

    sent++;
    late final Future<CloudReply?> answer;
    answer = request()
        // A request that threw is "no answer", which is what the service
        // already makes of a transport failure; it is turned into one here
        // too so every waiter sees the same thing.
        .then<CloudReply?>((reply) => reply, onError: (Object _) => null)
        .then((reply) {
          _last = reply;
          _askedAt = now;
          return reply;
        })
        .whenComplete(() {
          if (identical(_inFlight, answer)) _inFlight = null;
        });
    _inFlight = answer;
    return answer;
  }
}
