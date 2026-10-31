import 'package:fieldnote_gateway_client/fieldnote_gateway_client.dart';
import 'package:flutter/material.dart';

import '../routing/routing_policy.dart';
import 'app_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8787');
  final _code = TextEditingController();
  List<DiscoveredGateway> _found = const [];
  bool _searching = false;
  String? _pairMessage;

  AppController get c => widget.controller;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final found = await c.findGateways();
      setState(() => _found = found);
    } on Object catch (e) {
      setState(
        () => _pairMessage = 'Search failed: $e. Enter the address by hand.',
      );
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _pair() async {
    final port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty || port == null) {
      setState(() => _pairMessage = 'Enter the Mac address and port.');
      return;
    }
    final error = await c.pairWith(
      GatewayAddress(_host.text.trim(), port),
      _code.text,
    );
    setState(() => _pairMessage = error ?? 'Paired.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'On-device models',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            'Speech (Whisper base): ${c.speechReady ? 'installed' : 'not installed'}'
            '${c.speechProgress == null ? '' : ' (${c.speechProgress}%)'}',
          ),
          Text(
            'Summary (Gemma 4 E2B): ${c.summaryReady ? 'installed' : 'not installed'}'
            '${c.summaryProgress == null ? '' : ' (${c.summaryProgress}%)'}',
          ),
          if (!c.speechReady || !c.summaryReady)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: c.installModels,
                child: const Text('Download models'),
              ),
            ),
          const Divider(height: 32),
          Text('Mac', style: Theme.of(context).textTheme.titleLarge),
          SwitchListTile(
            title: const Text('Send jobs to my Mac when needed'),
            value: c.settings.allowMac,
            onChanged: c.setAllowMac,
          ),
          if (c.paired case final paired?) ...[
            Text(
              'Paired with ${paired.address}. Status: ${switch (c.macStatus) {
                MacStatus.online => 'online',
                MacStatus.pairedOffline => 'not reachable',
                MacStatus.unpaired => 'not paired',
              }}.',
            ),
            Text('Certificate: ${paired.fingerprint.substring(0, 16)}…'),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: c.unpair,
                child: const Text('Unpair'),
              ),
            ),
          ] else ...[
            const Text(
              'On the Mac, start the gateway on the LAN and run "pair". Then enter the code here.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _searching ? null : _search,
                child: Text(_searching ? 'Searching…' : 'Find my Mac'),
              ),
            ),
            for (final g in _found)
              ListTile(
                title: Text(g.name),
                subtitle: Text(
                  '${g.address}  certificate ${g.fingerprintPrefix ?? 'unknown'}…',
                ),
                onTap: () => setState(() {
                  _host.text = g.address.host;
                  _port.text = '${g.address.port}';
                }),
              ),
            TextField(
              controller: _host,
              decoration: const InputDecoration(labelText: 'Mac address'),
            ),
            TextField(
              controller: _port,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Pairing code'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(onPressed: _pair, child: const Text('Pair')),
            ),
          ],
          if (_pairMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_pairMessage!),
            ),
        ],
      ),
    ),
  );
}
