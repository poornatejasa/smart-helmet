import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

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

// Shared typography for every screen, dialog and control.
abstract final class AppText {
  static const page = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w700,
  );
  static const section = TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );
  static const label = TextStyle(
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(fontSize: 13, height: 1.45);
  static const muted = TextStyle(fontSize: 13, height: 1.45, color: C.muted);
  static const caption = TextStyle(fontSize: 12, height: 1.4, color: C.muted);
  static const action = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const value = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const brand = TextStyle(
    fontSize: 14,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: .6,
  );
  static const accent = TextStyle(fontSize: 13, height: 1.45, color: C.mint);
  static const warning = TextStyle(fontSize: 13, height: 1.45, color: C.amber);
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
      textTheme: const TextTheme(
        headlineSmall: AppText.page,
        titleLarge: AppText.section,
        titleMedium: AppText.label,
        titleSmall: AppText.label,
        bodyLarge: AppText.body,
        bodyMedium: AppText.body,
        bodySmall: AppText.caption,
        labelLarge: AppText.action,
        labelMedium: AppText.action,
        labelSmall: AppText.caption,
      ),
      iconTheme: const IconThemeData(size: 22),
      listTileTheme: const ListTileThemeData(
        dense: true,
        titleTextStyle: AppText.label,
        subtitleTextStyle: AppText.caption,
        horizontalTitleGap: 12,
        minLeadingWidth: 22,
        minVerticalPadding: 8,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(AppText.action),
        iconTheme: WidgetStatePropertyAll(IconThemeData(size: 22)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        selectedLabelTextStyle: AppText.action,
        unselectedLabelTextStyle: AppText.action,
        selectedIconTheme: IconThemeData(size: 22),
        unselectedIconTheme: IconThemeData(size: 22),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _buttonStyle),
      textButtonTheme: TextButtonThemeData(style: _buttonStyle),
      chipTheme: const ChipThemeData(labelStyle: AppText.action),
      tooltipTheme: const TooltipThemeData(
        textStyle: AppText.body,
        decoration: BoxDecoration(
          color: C.raised,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: C.panel,
        titleTextStyle: AppText.section,
        contentTextStyle: AppText.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: C.raised,
        contentTextStyle: AppText.body,
      ),
      cardTheme: const CardThemeData(color: C.panel),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: C.raised,
        isDense: true,
        labelStyle: AppText.body,
        hintStyle: AppText.muted,
        suffixStyle: AppText.muted,
        counterStyle: AppText.caption,
        errorStyle: AppText.body,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    home: const Shell(),
  );

  static const _buttonStyle = ButtonStyle(
    textStyle: WidgetStatePropertyAll(AppText.action),
    iconSize: WidgetStatePropertyAll(18),
    minimumSize: WidgetStatePropertyAll(Size(0, 40)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
  );
}

enum Page { overview, devices, settings }

const nav = <(String, IconData)>[
  ('Overview', Icons.space_dashboard_rounded),
  ('Devices', Icons.bluetooth_searching_rounded),
  ('Settings', Icons.tune_rounded),
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
  bool safetyDetails = false;

  void go(Page next) {
    if (next == page && !safetyDetails) return;
    setState(() {
      page = next;
      safetyDetails = false;
    });
  }

  void back() {
    if (safetyDetails) {
      setState(() => safetyDetails = false);
    } else if (page != Page.overview) {
      setState(() => page = Page.overview);
    }
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
    canPop: page == Page.overview && !safetyDetails,
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
                  if (desktop && !safetyDetails)
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
                          size: 22,
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
                        if (page == Page.overview && !safetyDetails)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.health_and_safety_rounded,
                                  color: C.mint,
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'SMART HELMET',
                                        style: AppText.brand,
                                      ),
                                      Text(
                                        'Rider companion',
                                        style: AppText.caption,
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
                              key: ValueKey((page, safetyDetails)),
                              child: switch (page) {
                                Page.overview =>
                                  safetyDetails
                                      ? SafetyDetails(
                                          helmet: helmet,
                                          close: back,
                                        )
                                      : Overview(
                                          helmet: helmet,
                                          openSafety: () => setState(
                                            () => safetyDetails = true,
                                          ),
                                        ),
                                Page.devices => Devices(
                                  helmet: helmet,
                                  run: run,
                                ),
                                Page.settings => Settings(
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
            bottomNavigationBar: desktop || safetyDetails
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
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                      Text(title, style: AppText.page),
                      const SizedBox(height: 4),
                      Text(subtitle, style: AppText.muted),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action!],
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: C.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: C.edge),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

enum SafetyState { unknown, normal, alert }

class SafetySignal {
  const SafetySignal(this.label, this.icon, this.state, this.value);
  final String label;
  final IconData icon;
  final SafetyState state;
  final String value;

  Color get borderColor => switch (state) {
    SafetyState.unknown => C.edge,
    SafetyState.normal => C.mint,
    SafetyState.alert => C.red,
  };

  String get stateLabel => switch (state) {
    SafetyState.unknown => 'Awaiting sensor data',
    SafetyState.normal => 'Within range',
    SafetyState.alert => 'Attention needed',
  };
}

// BLE connection or an empty packet is not evidence of a safe sensor reading.
const safetySignals = <SafetySignal>[
  SafetySignal('Sobriety', Icons.science_outlined, SafetyState.unknown, '—'),
  SafetySignal(
    'Drowsiness',
    Icons.visibility_outlined,
    SafetyState.unknown,
    '—',
  ),
  SafetySignal('Impact', Icons.emergency_outlined, SafetyState.unknown, '—'),
];

class Overview extends StatelessWidget {
  const Overview({super.key, required this.helmet, required this.openSafety});
  final HelmetController helmet;
  final VoidCallback openSafety;

  @override
  Widget build(BuildContext context) {
    final interval = helmet.config?.intervalMs;
    return Frame(
      title: 'Ride overview',
      subtitle: 'Live information from your Smart Helmet.',
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Live monitoring', style: AppText.section),
              const SizedBox(height: 4),
              Text(
                helmet.connected
                    ? helmet.packetsReceived == 0
                          ? 'Connected · waiting for the first update'
                          : 'Latest update received from the Helmet'
                    : 'Connect to the Helmet to see live updates',
                style: AppText.muted,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final items = [
                    _SummaryItem(
                      Icons.sensors_rounded,
                      'Updates',
                      '${helmet.packetsReceived} received',
                      C.mint,
                    ),
                    _SummaryItem(
                      Icons.notifications_active_outlined,
                      'Alerts',
                      '${helmet.alerts.length} received',
                      C.amber,
                    ),
                    _SummaryItem(
                      Icons.timer_outlined,
                      'Update interval',
                      interval == null ? '—' : '$interval ms',
                      C.blue,
                    ),
                  ];
                  if (constraints.maxWidth < 520) {
                    return Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          items[i],
                          if (i < items.length - 1)
                            const Divider(color: C.edge, height: 24),
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [for (final item in items) Expanded(child: item)],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          onTap: openSafety,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Safety dashboard', style: AppText.section),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 690 ? 3 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final signal in safetySignals)
                        SizedBox(width: width, child: _SafetyCard(signal)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your safety readings will appear here when available.',
                      style: AppText.caption,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: C.mint),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.muted),
            Text(value, style: AppText.label),
          ],
        ),
      ),
    ],
  );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard(this.signal);
  final SafetySignal signal;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.raised,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: signal.borderColor, width: 1.5),
    ),
    child: Row(
      children: [
        Icon(signal.icon, color: C.muted, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(signal.label, style: AppText.label),
              Text(signal.stateLabel, style: AppText.caption),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(signal.value, style: AppText.value),
      ],
    ),
  );
}

class SafetyDetails extends StatelessWidget {
  const SafetyDetails({super.key, required this.helmet, required this.close});
  final HelmetController helmet;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    return Frame(
      title: 'Safety details',
      subtitle: 'Your ride readings and recent alerts.',
      action: TextButton(onPressed: close, child: const Text('Overview')),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 740 ? 3 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final signal in safetySignals)
                  SizedBox(width: width, child: _SafetyCard(signal)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Latest update', style: AppText.section),
              const SizedBox(height: 8),
              if (helmet.packetsReceived == 0)
                const Text('No updates received yet.', style: AppText.muted)
              else
                Text(
                  '${helmet.packetsReceived} updates received. Individual readings will appear when available.',
                  style: AppText.muted,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent alerts (${helmet.alerts.length})',
                style: AppText.section,
              ),
              const SizedBox(height: 8),
              if (helmet.alerts.isEmpty)
                const Text(
                  'No alerts received in this app session.',
                  style: AppText.muted,
                )
              else
                for (final alert in helmet.alerts.take(20)) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: alert.severity >= 3 ? C.red : C.amber,
                    ),
                    title: Text('${alert.severityLabel} alert'),
                    subtitle: Text(
                      'Received ${TimeOfDay.fromDateTime(alert.receivedAt).format(context)}',
                    ),
                  ),
                  const Divider(color: C.edge),
                ],
            ],
          ),
        ),
      ],
    );
  }
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
      tooltip: 'Refresh devices',
      onPressed: helmet.linkState == HelmetLinkState.connecting
          ? null
          : () => run(helmet.refreshDevices),
      icon: const Icon(Icons.refresh),
    ),
    children: [
      if (helmet.connected) ...[
        Panel(
          child: _DeviceEntry(
            name: helmet.deviceName,
            subtitle: 'Ready to monitor your ride',
            connected: true,
            action: OutlinedButton(
              onPressed: () => run(helmet.disconnect),
              child: const Text('Disconnect'),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (helmet.linkState == HelmetLinkState.reconnecting)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Connection lost. Retrying in a few seconds…',
            style: AppText.warning,
          ),
        ),
      if (!helmet.connected && helmet.devices.isEmpty)
        Panel(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.bluetooth_searching,
                    color: C.blue,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    helmet.scanning
                        ? 'Scanning nearby devices…'
                        : 'No devices found yet',
                    style: AppText.section,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
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
            child: _DeviceEntry(
              name: device.name?.isNotEmpty == true
                  ? device.name!
                  : 'Nearby device',
              subtitle: 'Tap Connect to pair',
              action: FilledButton.tonal(
                onPressed: helmet.linkState == HelmetLinkState.connecting
                    ? null
                    : () => run(() => helmet.connect(device)),
                child: const Text('Connect'),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      const SizedBox(height: 16),
      const Text(
        'Your phone may ask you to confirm pairing the first time you connect.',
        style: AppText.caption,
      ),
    ],
  );
}

class _DeviceEntry extends StatelessWidget {
  const _DeviceEntry({
    required this.name,
    required this.subtitle,
    required this.action,
    this.connected = false,
  });
  final String name, subtitle;
  final Widget action;
  final bool connected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Row(
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth,
            color: connected ? C.mint : C.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppText.label),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(14) > 18) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: content),
          const SizedBox(width: 12),
          action,
        ],
      );
    },
  );
}

class _HelmetNameDialog extends StatefulWidget {
  const _HelmetNameDialog({required this.initialName});
  final String initialName;

  @override
  State<_HelmetNameDialog> createState() => _HelmetNameDialogState();
}

class _HelmetNameDialogState extends State<_HelmetNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _input = TextEditingController(
    text: helmetNameBase(widget.initialName),
  );

  @override
  void dispose() {
    // Keep the controller alive until the dialog's exit transition completes.
    _input.dispose();
    super.dispose();
  }

  void submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(helmetNameBase(_input.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Helmet name'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _input,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Name',
          suffixText: ' Helmet',
          helperText: 'Up to 13 characters. Extra spaces are ignored.',
          helperMaxLines: 2,
          errorMaxLines: 2,
        ),
        validator: (value) {
          final base = helmetNameBase(value ?? '');
          if (base.length > 13) return 'Use up to 13 characters before Helmet.';
          if (!RegExp(r'^[\x20-\x7E]*$').hasMatch(base)) {
            return 'Use English letters, numbers or punctuation.';
          }
          return null;
        },
        onFieldSubmitted: (_) => submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Save')),
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
  bool saving = false;

  Future<void> save(Future<void> Function() action, String success) async {
    setState(() => saving = true);
    await widget.run(action, success);
    if (mounted) setState(() => saving = false);
  }

  Future<void> rename() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _HelmetNameDialog(
        initialName: widget.helmet.config?.deviceName ?? '',
      ),
    );
    if (name != null && mounted) {
      await save(() => widget.helmet.setDeviceName(name), 'Name saved.');
    }
  }

  Future<void> confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Restore Helmet settings?'),
        content: const Text(
          'This resets the name, update interval and alert preference. Your pairing and installed update stay in place.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await save(widget.helmet.resetSettings, 'Defaults restored.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.helmet.config;
    final enabled = widget.helmet.connected && config != null && !saving;
    return Frame(
      title: 'Helmet settings',
      subtitle: 'Make your helmet work the way you like.',
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
              const Text('Device name', style: AppText.section),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined, color: C.blue),
                title: Text(config?.deviceName ?? 'Connect to read the name'),
                subtitle: Text(
                  config == null ? 'Connect to edit' : 'Tap to edit',
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
              const Text('Live monitoring', style: AppText.section),
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        FirmwareUpdate(helmet: widget.helmet, run: widget.run),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Restore defaults', style: AppText.section),
              const SizedBox(height: 8),
              const Text(
                'Reset name, interval and alerts. Your pairing stays.',
                style: AppText.muted,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: enabled ? confirmReset : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset settings'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class FirmwareUpdate extends StatefulWidget {
  const FirmwareUpdate({super.key, required this.helmet, required this.run});
  final HelmetController helmet;
  final RunAction run;

  @override
  State<FirmwareUpdate> createState() => _FirmwareUpdateState();
}

class _FirmwareUpdateState extends State<FirmwareUpdate> {
  Uint8List? bytes;
  String? fileName;

  Future<void> pick() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Helmet update file', extensions: ['bin']),
      ],
    );
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Update Helmet firmware?'),
        content: Text(
          '$name will be sent to your helmet. Keep your phone and helmet nearby, and do not turn either off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start transfer'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await widget.run(
        () => widget.helmet.sendFile(data, name, TransferKind.firmware),
        'Firmware verified. Reboot the Helmet when ready.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.helmet.otaStatus;
    final busy = widget.helmet.transferring;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Firmware update', style: AppText.section),
          const SizedBox(height: 8),
          const Text(
            'Choose an update file made for this helmet. The update takes effect after a reboot.',
            style: AppText.muted,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => widget.run(pick),
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose firmware'),
          ),
          if (fileName != null) ...[
            const SizedBox(height: 8),
            Text(
              '$fileName · ${bytes?.length ?? 0} bytes',
              style: AppText.accent,
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: widget.helmet.connected && bytes != null && !busy
                    ? send
                    : null,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Send update'),
              ),
              if (busy)
                OutlinedButton(
                  onPressed: () => widget.run(widget.helmet.abortTransfer),
                  child: const Text('Stop transfer'),
                ),
              if (status?.state == TransferState.completed && !busy)
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
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: status == null ? 0 : status.progress / 100,
            minHeight: 7,
            borderRadius: BorderRadius.circular(7),
          ),
          const SizedBox(height: 8),
          Text(
            status == null
                ? 'Connect to read update status'
                : '${status.state.name.toUpperCase()} · ${status.bytesReceived} / ${status.totalSize} bytes',
            style: AppText.caption,
          ),
          const SizedBox(height: 8),
          const Text(
            'Keep both devices connected until the update is complete.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}
