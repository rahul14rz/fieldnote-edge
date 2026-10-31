import 'dart:convert';
import 'dart:io';

class AppSettings {
  const AppSettings({this.allowMac = true});
  final bool allowMac;

  AppSettings copyWith({bool? allowMac}) =>
      AppSettings(allowMac: allowMac ?? this.allowMac);
}

/// Settings in a small JSON file next to the job store, written atomically.
class SettingsStore {
  SettingsStore(this.file);
  final File file;

  Future<AppSettings> read() async {
    if (!file.existsSync()) return const AppSettings();
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return AppSettings(allowMac: json['allowMac'] as bool? ?? true);
  }

  Future<void> write(AppSettings settings) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'allowMac': settings.allowMac}),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
