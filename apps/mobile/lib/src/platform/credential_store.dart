import 'dart:convert';

import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the paired gateway's credential lives. The device secret must not be
/// stored in plain files.
abstract interface class CredentialStore {
  Future<PairedGateway?> read();
  Future<void> write(PairedGateway gateway);
  Future<void> delete();
}

/// Android Keystore-backed storage on Android, Keychain on macOS.
class SecureCredentialStore implements CredentialStore {
  static const _key = 'paired_gateway';
  final _storage = const FlutterSecureStorage();

  @override
  Future<PairedGateway?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null
        ? null
        : PairedGateway.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> write(PairedGateway gateway) =>
      _storage.write(key: _key, value: jsonEncode(gateway.toJson()));

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
