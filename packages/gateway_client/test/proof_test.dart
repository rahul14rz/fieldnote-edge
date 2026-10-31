import 'dart:convert';
import 'dart:io';

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'computes the same pairing proofs as the gateway, from the shared vector',
    () {
      final vector = jsonDecode(
        File('../contracts/fixtures/pairing-proof-vector.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final code = vector['code']! as String;
      final fingerprint = vector['fingerprint']! as String;

      expect(clientProof(code, fingerprint), vector['clientProof']);
      expect(serverProof(code, fingerprint), vector['serverProof']);
    },
  );

  test(
    'a proof over another fingerprint differs, so a relayed proof is useless',
    () {
      expect(
        clientProof('44PY2HRX7D', 'ab' * 32),
        isNot(clientProof('44PY2HRX7D', 'cd' * 32)),
      );
    },
  );
}
