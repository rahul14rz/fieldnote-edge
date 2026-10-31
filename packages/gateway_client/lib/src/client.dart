import 'package:fieldnote_contracts/fieldnote_contracts.dart';

import 'errors.dart';
import 'pinned_http.dart';
import 'proof.dart';

/// What the phone keeps after pairing. [deviceSecret] belongs in secure storage.
class PairedGateway {
  const PairedGateway({
    required this.address,
    required this.fingerprint,
    required this.deviceId,
    required this.deviceSecret,
  });

  factory PairedGateway.fromJson(Map<String, Object?> json) => PairedGateway(
    address: GatewayAddress(json['host']! as String, json['port']! as int),
    fingerprint: json['fingerprint']! as String,
    deviceId: json['deviceId']! as String,
    deviceSecret: json['deviceSecret']! as String,
  );

  final GatewayAddress address;

  /// Pinned at pairing. Every later connection must present this certificate.
  final String fingerprint;
  final String deviceId;
  final String deviceSecret;

  Map<String, Object?> toJson() => {
    'host': address.host,
    'port': address.port,
    'fingerprint': fingerprint,
    'deviceId': deviceId,
    'deviceSecret': deviceSecret,
  };

  PairedGateway at(GatewayAddress newAddress) => PairedGateway(
    address: newAddress,
    fingerprint: fingerprint,
    deviceId: deviceId,
    deviceSecret: deviceSecret,
  );
}

String _message(Object? body) => body is Map && body['message'] is String
    ? body['message'] as String
    : 'no message';

JsonResponse _expect(JsonResponse response, Set<int> ok) {
  if (!ok.contains(response.statusCode)) {
    throw GatewayRejected(response.statusCode, _message(response.body));
  }
  return response;
}

/// Pairs with the gateway at [address] using the code shown on the Mac.
///
/// The phone reads the certificate fingerprint first, sends a proof bound to
/// it instead of the code, checks the gateway's proof, and only then trusts
/// and pins the certificate (ADR 0010).
Future<PairedGateway> pair(
  GatewayAddress address, {
  required String code,
  required String deviceName,
}) async {
  final normalized = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  final fingerprint = await probeFingerprint(address);
  final http = PinnedHttp(address, fingerprint);
  try {
    final response = _expect(
      await http.send(
        'POST',
        '/v1/pairing',
        body: PairingRequest(
          proof: clientProof(normalized, fingerprint),
          deviceName: deviceName,
        ).toJson(),
      ),
      {201},
    );
    final paired = PairingResponse.fromJson(
      response.body! as Map<String, dynamic>,
    );
    if (paired.serverProof != serverProof(normalized, fingerprint)) {
      throw const ServerProofMismatch();
    }
    return PairedGateway(
      address: address,
      fingerprint: fingerprint,
      deviceId: paired.deviceId,
      deviceSecret: paired.deviceSecret,
    );
  } finally {
    http.close();
  }
}

/// Talks to a paired gateway over pinned TLS. Gets a session token when it
/// needs one, reuses it until a minute before it expires, and gets a new one
/// once if the gateway answers 401.
class GatewayClient {
  GatewayClient(this.gateway, {DateTime Function()? now})
    : _http = PinnedHttp(gateway.address, gateway.fingerprint),
      _now = now ?? DateTime.now;

  final PairedGateway gateway;
  final PinnedHttp _http;
  final DateTime Function() _now;
  String? _token;
  DateTime? _expiresAt;

  Future<HealthResponse> health() async => HealthResponse.fromJson(
    _expect(await _http.send('GET', '/health'), {200}).body!
        as Map<String, dynamic>,
  );

  Future<JobStatus> submit(JobSubmission submission) async =>
      JobStatus.fromJson(
        (await _authorized(
              'POST',
              '/v1/jobs',
              body: submission.toJson(),
              ok: {200, 202},
            )).body!
            as Map<String, dynamic>,
      );

  Future<JobStatus> status(String jobId) async => JobStatus.fromJson(
    (await _authorized(
          'GET',
          '/v1/jobs/${Uri.encodeComponent(jobId)}',
          ok: {200},
        )).body!
        as Map<String, dynamic>,
  );

  Future<MeetingSummary> summary(String jobId) async => MeetingSummary.fromJson(
    (await _authorized(
          'GET',
          '/v1/jobs/${Uri.encodeComponent(jobId)}/summary',
          ok: {200},
        )).body!
        as Map<String, dynamic>,
  );

  void close() => _http.close();

  Future<JsonResponse> _authorized(
    String method,
    String path, {
    Object? body,
    required Set<int> ok,
  }) async {
    var response = await _http.send(
      method,
      path,
      body: body,
      bearer: await _session(),
    );
    if (response.statusCode == 401) {
      _token = null;
      response = await _http.send(
        method,
        path,
        body: body,
        bearer: await _session(),
      );
    }
    return _expect(response, ok);
  }

  Future<String> _session() async {
    final token = _token;
    final expiresAt = _expiresAt;
    if (token != null &&
        expiresAt != null &&
        _now().isBefore(expiresAt.subtract(const Duration(minutes: 1)))) {
      return token;
    }
    final response = _expect(
      await _http.send(
        'POST',
        '/v1/sessions',
        body: SessionRequest(
          deviceId: gateway.deviceId,
          deviceSecret: gateway.deviceSecret,
        ).toJson(),
      ),
      {201},
    );
    final session = SessionResponse.fromJson(
      response.body! as Map<String, dynamic>,
    );
    _token = session.sessionToken;
    _expiresAt = DateTime.parse(session.expiresAt);
    return session.sessionToken;
  }
}
