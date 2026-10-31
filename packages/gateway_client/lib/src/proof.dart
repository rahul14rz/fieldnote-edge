import 'dart:convert';

import 'package:crypto/crypto.dart';

const _label = 'fieldnote-pair-v1';

String _hmac(String code, String role, String fingerprint) => Hmac(
  sha256,
  utf8.encode(code),
).convert(utf8.encode('$_label|$role|$fingerprint')).toString();

/// The proof the phone sends instead of the pairing code (ADR 0010).
String clientProof(String code, String fingerprint) =>
    _hmac(code, 'client', fingerprint);

/// The proof the gateway answers with. The phone checks it before trusting the reply.
String serverProof(String code, String fingerprint) =>
    _hmac(code, 'server', fingerprint);

/// SHA-256 of a certificate's DER bytes, lowercase hex, the format the gateway logs.
String fingerprintOf(List<int> der) => sha256.convert(der).toString();
