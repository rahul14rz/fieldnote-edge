@Tags(['integration', 'mdns'])
library;

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:test/test.dart';

import 'gateway_process.dart';

void main() {
  test('finds a gateway advertised over mDNS, with its port and fingerprint prefix', () async {
    final gateway = await GatewayProcess.start(
      env: {'HOST': '0.0.0.0', 'MDNS': 'on'},
    );
    addTearDown(gateway.stop);

    final found = await discoverGateways(timeout: const Duration(seconds: 4));

    final match = found.where((g) => g.address.port == gateway.port).toList();
    expect(
      match,
      isNotEmpty,
      reason: 'found: ${found.map((g) => '${g.name} ${g.address}').toList()}',
    );
    expect(match.first.fingerprintPrefix, matches(RegExp(r'^[0-9a-f]{16}$')));
  });
}
