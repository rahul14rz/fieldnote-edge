import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('fieldnote/multicast');

/// Runs [work] while holding Android's Wi-Fi multicast lock, which mDNS
/// browsing needs there. Other platforms need no lock.
Future<T> withMulticastLock<T>(Future<T> Function() work) async {
  if (!Platform.isAndroid) return work();
  await _channel.invokeMethod<void>('acquire');
  try {
    return await work();
  } finally {
    await _channel.invokeMethod<void>('release');
  }
}
