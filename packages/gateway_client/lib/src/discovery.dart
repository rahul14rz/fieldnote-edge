import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'pinned_http.dart';

const serviceName = '_fieldnote._tcp.local';

class DiscoveredGateway {
  const DiscoveredGateway({
    required this.name,
    required this.address,
    required this.fingerprintPrefix,
  });

  final String name;
  final GatewayAddress address;

  /// First 16 hex characters of the certificate fingerprint, from the TXT
  /// record. Shown to the user; never used for trust (ADR 0011).
  final String? fingerprintPrefix;
}

/// Browses the LAN for gateways for [timeout]. Returns what answered.
Future<List<DiscoveredGateway>> discoverGateways({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final client = MDnsClient(
    rawDatagramSocketFactory:
        (host, port, {reuseAddress = true, reusePort = false, ttl = 255}) =>
            RawDatagramSocket.bind(
              host,
              port,
              reuseAddress: true,
              reusePort: !Platform.isWindows,
              ttl: ttl,
            ),
  );
  await client.start();
  final found = <DiscoveredGateway>[];
  try {
    await for (final ptr in client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceName),
      timeout: timeout,
    )) {
      String? prefix;
      await for (final txt in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(ptr.domainName),
      )) {
        for (final line in txt.text.split('\n')) {
          if (line.startsWith('fp=')) prefix = line.substring(3);
        }
      }
      await for (final srv in client.lookup<SrvResourceRecord>(
        ResourceRecordQuery.service(ptr.domainName),
      )) {
        await for (final ip in client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(srv.target),
        )) {
          final name = ptr.domainName.replaceFirst('.$serviceName', '');
          found.add(
            DiscoveredGateway(
              name: name,
              address: GatewayAddress(ip.address.address, srv.port),
              fingerprintPrefix: prefix,
            ),
          );
        }
      }
    }
  } finally {
    client.stop();
  }
  return found;
}
