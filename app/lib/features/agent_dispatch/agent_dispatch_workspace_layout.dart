import 'package:flutter/material.dart';

import 'agent_dispatch_section_header.dart';

/// Responsive shell for the Agent Dispatch project workspace.
///
/// The caller supplies the four functional panes. This module owns only their
/// placement and scrolling behavior, so the pane implementations can evolve
/// without duplicating responsive layout rules.
class AgentDispatchWorkspace extends StatelessWidget {
  const AgentDispatchWorkspace({
    required this.worker,
    required this.skill,
    required this.settings,
    required this.log,
    super.key,
  });

  static const _wideBreakpoint = 1280.0;
  static const _mediumBreakpoint = 900.0;

  final Widget worker;
  final Widget skill;
  final Widget settings;
  final Widget log;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return _WideWorkspace(
            settings: settings,
            worker: worker,
            skill: skill,
            log: log,
          );
        }
        if (constraints.maxWidth >= _mediumBreakpoint) {
          return _MediumWorkspace(
            settings: settings,
            worker: worker,
            skill: skill,
            log: log,
          );
        }
        return _CompactWorkspace(
          constraints: constraints,
          settings: settings,
          worker: worker,
          skill: skill,
          log: log,
        );
      },
    );
  }
}

class _WideWorkspace extends StatelessWidget {
  const _WideWorkspace({
    required this.settings,
    required this.worker,
    required this.skill,
    required this.log,
  });

  final Widget settings;
  final Widget worker;
  final Widget skill;
  final Widget log;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('agent-dispatch-layout-wide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 10,
          child: _ScrollableSettingsPane(child: settings),
        ),
        const VerticalDivider(width: 20),
        Expanded(
          flex: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              worker,
              const SizedBox(height: 12),
              Expanded(child: skill),
            ],
          ),
        ),
        const VerticalDivider(width: 20),
        Expanded(flex: 12, child: log),
      ],
    );
  }
}

class _MediumWorkspace extends StatelessWidget {
  const _MediumWorkspace({
    required this.settings,
    required this.worker,
    required this.skill,
    required this.log,
  });

  final Widget settings;
  final Widget worker;
  final Widget skill;
  final Widget log;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('agent-dispatch-layout-medium'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 10,
          child: _ScrollableSettingsPane(child: settings),
        ),
        const VerticalDivider(width: 20),
        Expanded(
          flex: 14,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final supportMaxHeight =
                  (constraints.maxHeight * 0.42).clamp(120.0, 360.0).toDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: supportMaxHeight),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          worker,
                          const SizedBox(height: 12),
                          skill,
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  Expanded(child: log),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactWorkspace extends StatelessWidget {
  const _CompactWorkspace({
    required this.constraints,
    required this.settings,
    required this.worker,
    required this.skill,
    required this.log,
  });

  final BoxConstraints constraints;
  final Widget settings;
  final Widget worker;
  final Widget skill;
  final Widget log;

  double get _logHeight {
    if (!constraints.maxHeight.isFinite) return 400;
    return (constraints.maxHeight * 0.6).clamp(360.0, 520.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('agent-dispatch-layout-compact'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AgentDispatchSectionHeader(
            title: 'Configuration',
            tone: AgentDispatchSectionTone.configuration,
          ),
          const SizedBox(height: 12),
          settings,
          const Divider(height: 32),
          worker,
          const SizedBox(height: 12),
          skill,
          const Divider(height: 32),
          SizedBox(height: _logHeight, child: log),
        ],
      ),
    );
  }
}

class _ScrollableSettingsPane extends StatelessWidget {
  const _ScrollableSettingsPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AgentDispatchSectionHeader(
          title: 'Configuration',
          tone: AgentDispatchSectionTone.configuration,
        ),
        const SizedBox(height: 12),
        Expanded(child: SingleChildScrollView(child: child)),
      ],
    );
  }
}
