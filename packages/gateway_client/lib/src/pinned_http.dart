import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'proof.dart';

class GatewayAddress {
  const GatewayAddress(this.host, this.port);
  final String host;
  final int port;

  Uri uri(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  @override
  String toString() => '$host:$port';
}

class JsonResponse {
  const JsonResponse(this.statusCode, this.body);
  final int statusCode;
  final Object? body;
}

/// Opens one TLS connection and returns the fingerprint of the certificate the
/// server presented, without sending any request. Used once, at pairing.
Future<String> probeFingerprint(
  GatewayAddress address, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  String? seen;
  try {
    final socket = await SecureSocket.connect(
      address.host,
      address.port,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (cert) {
        seen = fingerprintOf(cert.der);
        return true;
      },
      timeout: timeout,
    );
    seen ??= socket.peerCertificate == null
        ? null
        : fingerprintOf(socket.peerCertificate!.der);
    await socket.close();
  } on SocketException catch (e) {
    throw GatewayUnreachable(e);
  } on HandshakeException catch (e) {
    throw GatewayUnreachable(e);
  } on TimeoutException catch (e) {
    throw GatewayUnreachable(e);
  }
  final fingerprint = seen;
  if (fingerprint == null) {
    throw const GatewayUnreachable('the server presented no certificate');
  }
  return fingerprint;
}

/// HTTPS to one gateway, accepting only the certificate whose SHA-256
/// fingerprint equals [fingerprint]. No certificate authority is trusted.
/// The check runs during the TLS handshake, before any request is sent.
class PinnedHttp {
  PinnedHttp(
    this.address,
    this.fingerprint, {
    this.timeout = const Duration(seconds: 30),
  }) : _client = HttpClient(context: SecurityContext(withTrustedRoots: false)) {
    _client.connectionTimeout = timeout;
    _client.badCertificateCallback = (cert, host, port) {
      final actual = fingerprintOf(cert.der);
      if (actual == fingerprint) return true;
      _lastMismatch = actual;
      return false;
    };
  }

  final GatewayAddress address;
  final String fingerprint;
  final Duration timeout;
  final HttpClient _client;
  String? _lastMismatch;

  Future<JsonResponse> send(
    String method,
    String path, {
    Object? body,
    String? bearer,
  }) async {
    _lastMismatch = null;
    try {
      final request = await _client
          .openUrl(method, address.uri(path))
          .timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await utf8.decodeStream(response).timeout(timeout);
      return JsonResponse(
        response.statusCode,
        text.isEmpty ? null : jsonDecode(text),
      );
    } on HandshakeException catch (e) {
      final mismatch = _lastMismatch;
      if (mismatch != null) throw PinMismatch(fingerprint, mismatch);
      throw GatewayUnreachable(e);
    } on SocketException catch (e) {
      throw GatewayUnreachable(e);
    } on TimeoutException catch (e) {
      throw GatewayUnreachable(e);
    } on HttpException catch (e) {
      throw GatewayUnreachable(e);
    }
  }

  void close() => _client.close(force: true);
}
