/// The gateway's certificate is not the one pinned at pairing.
class PinMismatch implements Exception {
  const PinMismatch(this.expected, this.actual);
  final String expected;
  final String actual;

  @override
  String toString() => 'PinMismatch: expected $expected, got $actual';
}

/// The gateway could not be reached: no route, refused, timed out, TLS failed.
class GatewayUnreachable implements Exception {
  const GatewayUnreachable(this.cause);
  final Object cause;

  @override
  String toString() => 'GatewayUnreachable: $cause';
}

/// The gateway answered with an error status.
class GatewayRejected implements Exception {
  const GatewayRejected(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GatewayRejected($statusCode): $message';
}

/// The gateway answered the pairing request, but its server proof is wrong, so
/// the other end does not know the code. Treat it as an impostor.
class ServerProofMismatch implements Exception {
  const ServerProofMismatch();

  @override
  String toString() =>
      'ServerProofMismatch: the gateway could not prove it knows the pairing code';
}
