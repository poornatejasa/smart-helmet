import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'helmet_controller.dart';
import 'helmet_protocol.dart';

void main() => runApp(const SmartHelmetApp());

abstract final class C {
  static const bg = Color(0xFF07121B);
  static const panel = Color(0xFF10232F);
  static const raised = Color(0xFF1A3442);
  static const edge = Color(0xFF294656);
  static const mint = Color(0xFF79E8CF);
  static const blue = Color(0xFF8AC5FF);
  static const amber = Color(0xFFFFC57A);
  static const red = Color(0xFFFF888C);
  static const muted = Color(0xFFA3B9C4);
}

class SmartHelmetApp extends StatelessWidget {
  const SmartHelmetApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smart Helmet',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: C.mint,
        brightness: Brightness.dark,
      ),
      cardTheme: const CardThemeData(color: C.panel),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: C.raised,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    home: const Shell(),
  );
}

enum Page { overview, alerts, devices, settings, transfers }

const nav = <(String, IconData)>[
  ('Overview', Icons.space_dashboard_rounded),
  ('Alerts', Icons.notifications_active_rounded),
  ('Devices', Icons.bluetooth_searching_rounded),
  ('Settings', Icons.tune_rounded),
  ('Transfers', Icons.swap_vert_circle_rounded),
];

typedef RunAction = Future<void> Function(Future<void> Function(), [String?]);

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final HelmetController helmet = HelmetController();
  Page page = Page.overview;
  final List<Page> backStack = [];

  void go(Page next) {
    if (next == page) return;
    setState(() {
      backStack.add(page);
      page = next;
    });
  }

  void back() {
    if (backStack.isEmpty) return;
    setState(() => page = backStack.removeLast());
  }

  Future<void> run(Future<void> Function() action, [String? success]) async {
    try {
      await action();
      if (mounted && success != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    helmet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) back();
    },
    child: ListenableBuilder(
      listenable: helmet,
      builder: (context, _) => LayoutBuilder(
        builder: (context, size) {
          final desktop = size.maxWidth >= 850;
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  if (desktop)
                    NavigationRail(
                      backgroundColor: C.panel,
                      extended: size.maxWidth >= 1160,
                      labelType: size.maxWidth >= 1160
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      selectedIndex: page.index,
                      onDestinationSelected: (i) => go(Page.values[i]),
                      leading: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Icon(
                          Icons.health_and_safety_rounded,
                          color: C.mint,
                          size: 36,
                        ),
                      ),
                      destinations: [
                        for (final item in nav)
                          NavigationRailDestination(
                            icon: Icon(item.$2),
                            label: Text(item.$1),
                          ),
                      ],
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                          child: Row(
                            children: [
                              if (backStack.isNotEmpty)
                                IconButton(
                                  tooltip: 'Back',
                                  onPressed: back,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                ),
                              const Icon(
                                Icons.health_and_safety_rounded,
                                color: C.mint,
                                size: 34,
                              ),
                              const SizedBox(width: 11),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SMART HELMET',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.3,
                                      ),
                                    ),
                                    Text(
                                      'Rider companion',
                                      style: TextStyle(
                                        color: C.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ActionChip(
                                avatar: Icon(
                                  helmet.connected
                                      ? Icons.bluetooth_connected
                                      : Icons.bluetooth_disabled,
                                  color: helmet.connected ? C.mint : C.muted,
                                  size: 18,
                                ),
                                label: Text(
                                  helmet.connected ? 'Connected' : 'Connect',
                                ),
                                onPressed: () => go(Page.devices),
                              ),
                            ],
                          ),
                        ),
                        if (helmet.message != null)
                          MaterialBanner(
                            content: Text(helmet.message!),
                            backgroundColor: C.raised,
                            actions: [
                              TextButton(
                                onPressed: helmet.clearMessage,
                                child: const Text('Dismiss'),
                              ),
                            ],
                          ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: KeyedSubtree(
                              key: ValueKey(page),
                              child: switch (page) {
                                Page.overview => Overview(
                                  helmet: helmet,
                                  devices: () => go(Page.devices),
                                  alerts: () => go(Page.alerts),
                                ),
                                Page.alerts => Alerts(helmet: helmet),
                                Page.devices => Devices(
                                  helmet: helmet,
                                  run: run,
                                ),
                                Page.settings => Settings(
                                  helmet: helmet,
                                  run: run,
                                ),
                                Page.transfers => Transfers(
                                  helmet: helmet,
                                  run: run,
                                ),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: desktop
                ? null
                : NavigationBar(
                    backgroundColor: C.panel,
                    selectedIndex: page.index,
                    onDestinationSelected: (i) => go(Page.values[i]),
                    destinations: [
                      for (final item in nav)
                        NavigationDestination(
                          icon: Icon(item.$2),
                          label: item.$1,
                        ),
                    ],
                  ),
          );
        },
      ),
    ),
  );
}

class Frame extends StatelessWidget {
  const Frame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(subtitle, style: const TextStyle(color: C.muted)),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 22),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: C.panel,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: C.edge),
    ),
    child: child,
  );
}

class Overview extends StatelessWidget {
  const Overview({
    super.key,
    required this.helmet,
    required this.devices,
    required this.alerts,
  });
  final HelmetController helmet;
  final VoidCallback devices;
  final VoidCallback alerts;

  @override
  Widget build(BuildContext context) {
    final sample = helmet.telemetry;
    return Frame(
      title: 'Ride overview',
      subtitle: 'Connection, alerts and the latest live signal.',
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D5850), Color(0xFF13394A), Color(0xFF102635)],
            ),
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: C.mint.withValues(alpha: .35)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 20,
            children: [
              SizedBox(
                width: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIVE CONNECTION',
                      style: TextStyle(
                        color: C.mint,
                        fontSize: 12,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      helmet.connected
                          ? helmet.deviceName
                          : 'Connect your helmet',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      helmet.connected
                          ? 'Receiving encrypted BLE telemetry and alerts.'
                          : 'Find the Helmet to follow its live safety signals.',
                      style: const TextStyle(color: Color(0xFFD8E9E8)),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: devices,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: Text(
                        helmet.connected ? 'Manage connection' : 'Find helmet',
                      ),
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 67,
                backgroundColor: C.mint.withValues(alpha: .12),
                child: Icon(
                  helmet.connected
                      ? Icons.health_and_safety_rounded
                      : Icons.bluetooth_disabled,
                  color: C.mint,
                  size: 67,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = constraints.maxWidth > 760
                ? 3
                : constraints.maxWidth > 480
                ? 2
                : 1;
            final tileWidth = (constraints.maxWidth - (count - 1) * 12) / count;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    Icons.sensors_rounded,
                    'Telemetry',
                    '${helmet.packetsReceived} packets',
                    C.mint,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    Icons.notification_important_rounded,
                    'Alerts',
                    '${helmet.alerts.length} received',
                    C.amber,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _Metric(
                    Icons.timer_outlined,
                    'Update interval',
                    helmet.config == null
                        ? '—'
                        : '${helmet.config!.intervalMs} ms',
                    C.blue,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Latest telemetry',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 12),
              if (sample == null)
                const Text(
                  'No packet yet. Connect to the Helmet to begin.',
                  style: TextStyle(color: C.muted),
                )
              else ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Chip(label: Text('Protocol v${sample.version}')),
                    Chip(
                      label: Text(
                        'Flags 0x${sample.flags.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                      ),
                    ),
                    Chip(label: Text('Sequence ${sample.sequence}')),
                    Chip(
                      label: Text(
                        'Uptime ${(sample.timestampMs / 1000).toStringAsFixed(1)} s',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SelectableText(
                  'Payload: ${sample.payload.isEmpty ? '(empty)' : hexBytes(sample.payload)}',
                  style: const TextStyle(
                    color: C.muted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Safety modules',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              SizedBox(height: 8),
              Text(
                'Sobriety, drowsiness and impact values will appear when the STM32 telemetry payload is defined and integrated.',
                style: TextStyle(color: C.muted),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Sobriety · awaiting data')),
                  Chip(label: Text('Drowsiness · awaiting data')),
                  Chip(label: Text('Impact · awaiting data')),
                ],
              ),
            ],
          ),
        ),
        if (helmet.alerts.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: alerts,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('View alerts'),
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 15),
        Text(label, style: const TextStyle(color: C.muted)),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
        ),
      ],
    ),
  );
}

class Alerts extends StatelessWidget {
  const Alerts({super.key, required this.helmet});
  final HelmetController helmet;
  @override
  Widget build(BuildContext context) => Frame(
    title: 'Alert history',
    subtitle: 'Notifications received during this app session.',
    action: helmet.alerts.isEmpty
        ? null
        : IconButton(
            tooltip: 'Clear history',
            onPressed: helmet.clearAlerts,
            icon: const Icon(Icons.delete_outline),
          ),
    children: [
      if (helmet.alerts.isEmpty)
        const Panel(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 45),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 48, color: C.muted),
                  SizedBox(height: 12),
                  Text(
                    'No alerts received yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Helmet notifications will appear here.',
                    style: TextStyle(color: C.muted),
                  ),
                ],
              ),
            ),
          ),
        )
      else
        for (final alert in helmet.alerts) ...[
          Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 34,
                  color: alert.severity == 3 ? C.red : C.amber,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${alert.severityLabel} · code ${alert.code}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Sequence ${alert.sequence} · device uptime ${(alert.timestampMs / 1000).toStringAsFixed(1)} s',
                        style: const TextStyle(color: C.muted),
                      ),
                      if (alert.payload.isNotEmpty)
                        SelectableText(
                          'Payload: ${hexBytes(alert.payload)}',
                          style: const TextStyle(
                            color: C.muted,
                            fontFamily: 'monospace',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 12),
      const Text(
        'Alert codes are shown exactly as sent by the Helmet. Location and emergency messaging need an agreed alert-code mapping and phone permissions.',
        style: TextStyle(color: C.muted, fontSize: 12),
      ),
    ],
  );
}

class Devices extends StatelessWidget {
  const Devices({super.key, required this.helmet, required this.run});
  final HelmetController helmet;
  final RunAction run;
  @override
  Widget build(BuildContext context) => Frame(
    title: 'Devices',
    subtitle: 'Find and connect to the Smart Helmet.',
    action: IconButton.filledTonal(
      tooltip: helmet.scanning ? 'Stop scan' : 'Scan nearby',
      onPressed: helmet.connected
          ? null
          : () => run(helmet.scanning ? helmet.stopScan : helmet.scan),
      icon: Icon(helmet.scanning ? Icons.stop : Icons.refresh),
    ),
    children: [
      if (helmet.connected) ...[
        Panel(
          child: Row(
            children: [
              const Icon(Icons.bluetooth_connected, color: C.mint, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      helmet.deviceName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      helmet.deviceId ?? '',
                      style: const TextStyle(color: C.muted),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: () => run(helmet.disconnect),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (helmet.linkState == HelmetLinkState.reconnecting)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Text(
            'Connection lost. Retrying in a few seconds…',
            style: TextStyle(color: C.amber),
          ),
        ),
      if (!helmet.connected && helmet.devices.isEmpty)
        Panel(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 42),
              child: Column(
                children: [
                  const Icon(
                    Icons.bluetooth_searching,
                    color: C.blue,
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    helmet.scanning
                        ? 'Scanning nearby devices…'
                        : 'No devices found yet',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: helmet.scanning ? null : () => run(helmet.scan),
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Start scan'),
                  ),
                ],
              ),
            ),
          ),
        )
      else if (!helmet.connected)
        for (final device in helmet.devices) ...[
          Panel(
            child: Row(
              children: [
                const Icon(Icons.bluetooth, color: C.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name?.isNotEmpty == true
                            ? device.name!
                            : 'Unnamed BLE device',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${device.deviceId}${device.rssi == null ? '' : ' · ${device.rssi} dBm'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: helmet.linkState == HelmetLinkState.connecting
                      ? null
                      : () => run(() => helmet.connect(device)),
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 16),
      const Text(
        'The app verifies the Smart Helmet service after connecting. Your phone or PC may request pairing for encrypted access.',
        style: TextStyle(color: C.muted, fontSize: 12),
      ),
    ],
  );
}

class Settings extends StatefulWidget {
  const Settings({super.key, required this.helmet, required this.run});
  final HelmetController helmet;
  final RunAction run;
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  double? draftInterval;
  bool saving = false;

  Future<void> save(Future<void> Function() action, String success) async {
    setState(() => saving = true);
    await widget.run(action, success);
    if (mounted) setState(() => saving = false);
  }

  Future<void> rename() async {
    final input = TextEditingController(
      text: widget.helmet.config?.deviceName ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Helmet name'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null && mounted) {
      await save(
        () => widget.helmet.setDeviceName(name),
        'Name saved. Reconnect to see it in scans.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.helmet.config;
    final enabled = widget.helmet.connected && config != null && !saving;
    final interval = (draftInterval ?? (config?.intervalMs ?? 1000).toDouble())
        .clamp(100.0, 60000.0);
    return Frame(
      title: 'Helmet settings',
      subtitle: 'Stored on your Helmet and changed over encrypted BLE.',
      action: IconButton(
        tooltip: 'Refresh',
        onPressed: widget.helmet.connected
            ? () => widget.run(widget.helmet.refresh)
            : null,
        icon: const Icon(Icons.refresh),
      ),
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Device identity',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined, color: C.blue),
                title: Text(config?.deviceName ?? 'Connect to read the name'),
                subtitle: Text(
                  config == null
                      ? 'Unavailable'
                      : 'Protocol version ${config.version}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: enabled ? rename : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live monitoring',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Alerts enabled'),
                subtitle: const Text('Allow the Helmet to send alerts.'),
                value: config?.alertsEnabled ?? false,
                onChanged: enabled
                    ? (value) => save(
                        () => widget.helmet.setAlertsEnabled(value),
                        'Alert preference saved.',
                      )
                    : null,
              ),
              const Divider(color: C.edge),
              Row(
                children: [
                  const Expanded(child: Text('Telemetry interval')),
                  Text(
                    '${interval.round()} ms',
                    style: const TextStyle(color: C.mint),
                  ),
                ],
              ),
              Slider(
                min: 100,
                max: 60000,
                divisions: 599,
                value: interval,
                onChanged: enabled
                    ? (value) => setState(() => draftInterval = value)
                    : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: enabled && draftInterval != null
                      ? () async {
                          final value = draftInterval!.round();
                          await save(
                            () => widget.helmet.setInterval(value),
                            'Interval saved.',
                          );
                          if (mounted) setState(() => draftInterval = null);
                        }
                      : null,
                  child: const Text('Save interval'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Row(
            children: [
              const Icon(Icons.restart_alt, color: C.amber),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Restore defaults',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Reset name, interval and alert preference.',
                      style: TextStyle(color: C.muted),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: enabled
                    ? () => save(
                        widget.helmet.resetSettings,
                        'Defaults restored.',
                      )
                    : null,
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class Transfers extends StatefulWidget {
  const Transfers({super.key, required this.helmet, required this.run});
  final HelmetController helmet;
  final RunAction run;
  @override
  State<Transfers> createState() => _TransfersState();
}

class _TransfersState extends State<Transfers> {
  TransferKind kind = TransferKind.firmware;
  Uint8List? bytes;
  String? fileName;
  final typeInput = TextEditingController(text: '1');

  @override
  void dispose() {
    typeInput.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final file = await openFile();
    if (file == null) return;
    final data = await file.readAsBytes();
    if (mounted) {
      setState(() {
        bytes = data;
        fileName = file.name;
      });
    }
  }

  Future<void> send() async {
    final data = bytes;
    final name = fileName;
    if (data == null || name == null) return;
    final fileType = int.tryParse(typeInput.text);
    if (kind == TransferKind.file &&
        (fileType == null || fileType < 1 || fileType > 255)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File type must be 1–255.')));
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          kind == TransferKind.firmware ? 'Update firmware?' : 'Send file?',
        ),
        content: Text(
          '$name (${data.length} bytes) will be SHA-256 verified by the Helmet. Keep the devices nearby.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.run(
        () => widget.helmet.sendFile(data, name, kind, fileType: fileType ?? 1),
        'Transfer verified by the Helmet.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.helmet.statusFor(kind);
    final busy = widget.helmet.transferring;
    return Frame(
      title: 'Transfers',
      subtitle: 'Verified firmware and file transfer over BLE.',
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TransferKind>(
                segments: const [
                  ButtonSegment(
                    value: TransferKind.firmware,
                    label: Text('Firmware'),
                    icon: Icon(Icons.system_update_alt),
                  ),
                  ButtonSegment(
                    value: TransferKind.file,
                    label: Text('File'),
                    icon: Icon(Icons.insert_drive_file_outlined),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: busy
                    ? null
                    : (values) => setState(() {
                        kind = values.first;
                        bytes = null;
                        fileName = null;
                      }),
              ),
              const SizedBox(height: 20),
              Text(
                kind == TransferKind.firmware
                    ? 'ESP32-C6 firmware image'
                    : 'Generic storage file',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                kind == TransferKind.firmware
                    ? 'Choose a compatible .bin image. The inactive OTA slot is verified before reboot.'
                    : 'The Helmet stores one file. The receiving firmware must define what its file type means.',
                style: const TextStyle(color: C.muted),
              ),
              if (kind == TransferKind.file) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: 170,
                  child: TextField(
                    controller: typeInput,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'File type (1–255)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 17),
              OutlinedButton.icon(
                onPressed: busy ? null : () => widget.run(pick),
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose file'),
              ),
              if (fileName != null) ...[
                const SizedBox(height: 10),
                Text(
                  '$fileName · ${bytes?.length ?? 0} bytes',
                  style: const TextStyle(color: C.mint),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: widget.helmet.connected && bytes != null && !busy
                        ? send
                        : null,
                    icon: const Icon(Icons.upload),
                    label: const Text('Send to Helmet'),
                  ),
                  if (busy)
                    OutlinedButton(
                      onPressed: () => widget.run(widget.helmet.abortTransfer),
                      child: const Text('Stop transfer'),
                    ),
                  if (kind == TransferKind.firmware &&
                      status?.state == TransferState.completed &&
                      !busy)
                    OutlinedButton.icon(
                      onPressed: () => widget.run(
                        widget.helmet.rebootUpdatedFirmware,
                        'Helmet reboot requested.',
                      ),
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reboot into update'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.data_usage, color: C.blue),
                  const SizedBox(width: 10),
                  const Text(
                    'Helmet status',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const Spacer(),
                  Text(
                    status?.state.name.toUpperCase() ?? 'NOT CONNECTED',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: status == null ? 0 : status.progress / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 9),
              Text(
                status == null
                    ? 'Connect to read transfer status'
                    : '${status.bytesReceived} / ${status.totalSize} bytes · ${status.progress}%',
                style: const TextStyle(color: C.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'The app waits for each small batch to be acknowledged. A disconnect aborts an active transfer.',
          style: TextStyle(color: C.muted, fontSize: 12),
        ),
      ],
    );
  }
}
