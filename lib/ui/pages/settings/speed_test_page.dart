import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:astral_game/data/models/speed_test_node.dart';
import 'package:astral_game/data/services/isp_info_service.dart';
import 'package:astral_game/data/services/screen_state_service.dart';
import 'package:astral_game/data/services/speed_test_service.dart';
import 'package:astral_game/data/state/speed_test_state.dart';
import 'package:astral_game/di.dart';
import 'package:astral_game/ui/widgets/astral_card.dart';
import 'package:astral_game/ui/widgets/empty_state_widget.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

class SpeedTestPage extends StatefulWidget {
  const SpeedTestPage({super.key});

  @override
  State<SpeedTestPage> createState() => _SpeedTestPageState();
}

class _SpeedTestPageState extends State<SpeedTestPage> {
  final SpeedTestState _state = getIt<SpeedTestState>();
  final IspInfoService _isp = getIt<IspInfoService>();
  final ScreenStateService _screen = getIt<ScreenStateService>();
  EffectCleanup? _defaultsEffect;

  @override
  void initState() {
    super.initState();
    if (_state.nodes.value.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _state.loadNodes());
    }
    _defaultsEffect = effect(() {
      if (_state.nodes.value.isEmpty) return;
      final province = _isp.province.value;
      final isp = _isp.isp.value;
      if (province.isEmpty && isp.isEmpty) return;
      _state.applyLocalDefaults(localProvince: province, localIsp: isp);
    });
  }

  @override
  void dispose() {
    _defaultsEffect?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final loaded = _state.nodes.value;
      final loading = _state.loading.value;
      final error = _state.error.value;
      final isNarrow = _screen.isNarrowSignal.value;

      return Scaffold(
        appBar: AppBar(
          title: const Text('网络测速'),
          actions: [
            IconButton(
              tooltip: '刷新节点表',
              onPressed: loading
                  ? null
                  : () => _state.loadNodes(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: switch ((loaded.isEmpty, loading, error)) {
            (true, true, _) => const Center(child: CircularProgressIndicator()),
            (true, false, final message?) => _ErrorView(
              message: message,
              onRetry: () => _state.loadNodes(forceRefresh: true),
            ),
            (true, _, _) => const EmptyStateWidget(
              icon: Icons.speed_outlined,
              message: '暂无测速节点',
              subtitle: '点右上角刷新重试',
            ),
            _ => isNarrow ? _narrowLayout() : _wideLayout(),
          },
        ),
      );
    });
  }

  Widget _narrowLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = EdgeInsets.fromLTRB(20, 16, 20, 24);
        return SingleChildScrollView(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 520,
                minHeight: math.max(
                  0,
                  constraints.maxHeight - padding.vertical,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NodeCard(state: _state),
                  const SizedBox(height: 14),
                  _MetricsCard(state: _state),
                  const SizedBox(height: 14),
                  _ChartCard(state: _state, chartHeight: 168),
                  const SizedBox(height: 20),
                  _StartButton(state: _state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _wideLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NodeCard(state: _state),
                  const SizedBox(height: 16),
                  _MetricsCard(state: _state),
                  const SizedBox(height: 20),
                  _StartButton(state: _state),
                ],
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: _ChartCard(state: _state, fill: true)),
        ],
      ),
    );
  }
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.state});

  final SpeedTestState state;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final node = state.selected.value;

      return AstralCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            _IconBadge(
              icon: Icons.router_outlined,
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node?.label ?? '未选择节点',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node == null
                        ? '请选择测速节点'
                        : (node.regionLabel.isEmpty
                              ? '测速节点'
                              : node.regionLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: state.running.value ? null : () => _pickNode(context),
              child: const Text('更换'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _pickNode(BuildContext context) async {
    final picked = await showModalBottomSheet<SpeedTestNode>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _NodePickerSheet(
        nodes: state.nodes.value,
        current: state.selected.value,
      ),
    );
    if (picked != null) state.selectNode(picked);
  }
}

class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({required this.nodes, required this.current});

  final List<SpeedTestNode> nodes;
  final SpeedTestNode? current;

  @override
  State<_NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<_NodePickerSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SpeedTestNode> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.nodes;
    return [
      for (final node in widget.nodes)
        if (node.label.toLowerCase().contains(query) ||
            node.ip.contains(query) ||
            node.regionLabel.toLowerCase().contains(query))
          node,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nodes = _filtered;

    return FractionallySizedBox(
      heightFactor: 0.75,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Text(
                    '选择测速节点',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '共 ${widget.nodes.length} 个',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SearchBar(
                controller: _controller,
                hintText: '搜索节点 / 地区',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: nodes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('没有匹配的节点'),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: nodes.length,
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        final selected =
                            node.endpoint == widget.current?.endpoint;
                        return ListTile(
                          selected: selected,
                          leading: _IconBadge(
                            icon: Icons.dns_outlined,
                            background: selected
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            foreground: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            size: 18,
                          ),
                          title: Text(node.label),
                          subtitle: Text(
                            node.regionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: scheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(node),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.state});

  final SpeedTestState state;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final samples = state.samples.value;
      final running = state.running.value;
      final phase = state.phase.value;
      final result = state.result.value;
      final finished = result != null && result.ok;

      final download = finished
          ? result.downloadMbps
          : _latestOf(samples, SpeedTestPhase.download);
      final upload = finished
          ? result.uploadMbps
          : _latestOf(samples, SpeedTestPhase.upload);
      final downloadLatency =
          result?.downloadLatencyMs ?? state.liveDownloadLatencyMs.value;
      final uploadLatency =
          result?.uploadLatencyMs ?? state.liveUploadLatencyMs.value;

      return AstralCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PhaseSteps(phase: phase, running: running, finished: finished),
            const SizedBox(height: 18),
            _BigMetric(
              icon: Icons.arrow_downward_rounded,
              label: '下行',
              value: download,
              latencyMs: downloadLatency,
              color: scheme.primary,
              container: scheme.primaryContainer,
              onContainer: scheme.onPrimaryContainer,
              onColor: scheme.onPrimary,
              active: running && phase == SpeedTestPhase.download,
            ),
            const SizedBox(height: 14),
            _BigMetric(
              icon: Icons.arrow_upward_rounded,
              label: '上行',
              value: upload,
              latencyMs: uploadLatency,
              color: scheme.tertiary,
              container: scheme.tertiaryContainer,
              onContainer: scheme.onTertiaryContainer,
              onColor: scheme.onTertiary,
              active: running && phase == SpeedTestPhase.upload,
            ),
            if (result != null && !result.ok) ...[
              const SizedBox(height: 14),
              _FailureBanner(message: result.error ?? '测速失败'),
            ],
          ],
        ),
      );
    });
  }

  double? _latestOf(List<SpeedTestSample> samples, SpeedTestPhase phase) {
    for (var i = samples.length - 1; i >= 0; i--) {
      if (samples[i].phase == phase) return samples[i].mbps;
    }
    return null;
  }
}

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps({
    required this.phase,
    required this.running,
    required this.finished,
  });

  final SpeedTestPhase? phase;
  final bool running;
  final bool finished;

  static const _labels = ['延迟', '下行', '上行'];
  static const _icons = [
    Icons.timer_outlined,
    Icons.arrow_downward_rounded,
    Icons.arrow_upward_rounded,
  ];

  int get _activeIndex => switch (phase) {
    SpeedTestPhase.latency => 0,
    SpeedTestPhase.download => 1,
    SpeedTestPhase.upload => 2,
    null => -1,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = running ? _activeIndex : -1;

    return Row(
      children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: (finished || (active >= 0 && i <= active))
                      ? scheme.primary
                      : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          _stepPill(context, index: i, active: active),
        ],
      ],
    );
  }

  Widget _stepPill(
    BuildContext context, {
    required int index,
    required int active,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isActive = index == active;
    final isDone = finished || (active >= 0 && index < active);

    final Color background;
    final Color foreground;
    if (isActive) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (isDone) {
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_rounded : _icons[index],
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Text(
            _labels[index],
            style: theme.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigMetric extends StatelessWidget {
  const _BigMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.latencyMs,
    required this.color,
    required this.container,
    required this.onContainer,
    required this.onColor,
    required this.active,
  });

  final IconData icon;
  final String label;
  final double? value;

  final double? latencyMs;
  final Color color;
  final Color container;
  final Color onContainer;
  final Color onColor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue = value != null && value! > 0;
    final text = hasValue ? value!.toStringAsFixed(1) : '0.0';

    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? color : container,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: active ? onColor : onContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: hasValue ? color : color.withValues(alpha: 0.25),
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Mbps',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _LatencyChip(latencyMs: latencyMs),
      ],
    );
  }
}

class _LatencyChip extends StatelessWidget {
  const _LatencyChip({required this.latencyMs});

  final double? latencyMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue = latencyMs != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            hasValue ? '延迟 ${latencyMs!.toStringAsFixed(0)} ms' : '延迟 —',
            style: theme.textTheme.labelMedium?.copyWith(
              color: hasValue
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.state});

  final SpeedTestState state;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final running = state.running.value;
      final enabled = state.selected.value != null && !running;
      return SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: enabled ? () => state.startTest() : null,
          icon: running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed_rounded),
          label: Text(
            running ? '测速中' : '开始测速',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    });
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.state, this.chartHeight, this.fill = false});

  final SpeedTestState state;
  final double? chartHeight;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final samples = state.samples.value;
      final running = state.running.value;
      final phase = state.phase.value;

      final chart = _AnimatedSpeedChart(
        samples: samples,
        running: running,
        activePhase: phase,
        downloadColor: scheme.primary,
        uploadColor: scheme.tertiary,
        gridColor: scheme.outlineVariant,
        labelStyle:
            theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
            ) ??
            TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
      );

      return AstralCard(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '实时速率',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 16),
                _Legend(
                  icon: Icons.arrow_downward_rounded,
                  color: scheme.primary,
                  label: '下行',
                ),
                const SizedBox(width: 12),
                _Legend(
                  icon: Icons.arrow_upward_rounded,
                  color: scheme.tertiary,
                  label: '上行',
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    _phaseLabel(phase),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (fill)
              Expanded(child: chart)
            else
              SizedBox(height: chartHeight ?? 170, child: chart),
          ],
        ),
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.icon, required this.color, required this.label});

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _AnimatedSpeedChart extends StatefulWidget {
  const _AnimatedSpeedChart({
    required this.samples,
    required this.running,
    required this.activePhase,
    required this.downloadColor,
    required this.uploadColor,
    required this.gridColor,
    required this.labelStyle,
  });

  final List<SpeedTestSample> samples;
  final bool running;
  final SpeedTestPhase? activePhase;
  final Color downloadColor;
  final Color uploadColor;
  final Color gridColor;
  final TextStyle labelStyle;

  @override
  State<_AnimatedSpeedChart> createState() => _AnimatedSpeedChartState();
}

class _AnimatedSpeedChartState extends State<_AnimatedSpeedChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.running) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _AnimatedSpeedChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.running && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _axisMaxMbps(widget.samples)),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, maxMbps, _) {
        return CustomPaint(
          size: Size.infinite,
          painter: _SpeedChartPainter(
            samples: widget.samples,
            maxMbps: maxMbps,
            maxSeconds: _axisMaxSeconds(widget.samples),
            activePhase: widget.activePhase,
            downloadColor: widget.downloadColor,
            uploadColor: widget.uploadColor,
            gridColor: widget.gridColor,
            labelStyle: widget.labelStyle,
            textDirection: Directionality.of(context),
            pulse: _pulse.value,
            repaint: _pulse,
          ),
          child: widget.samples.isEmpty
              ? Center(
                  child: Text(
                    '开始测速后这里会绘制实时速率曲线',
                    style: widget.labelStyle.copyWith(
                      color: widget.labelStyle.color?.withValues(alpha: 0.7),
                    ),
                  ),
                )
              : const SizedBox.expand(),
        );
      },
    );
  }
}

class _SpeedChartPainter extends CustomPainter {
  _SpeedChartPainter({
    required this.samples,
    required this.maxMbps,
    required this.maxSeconds,
    required this.activePhase,
    required this.downloadColor,
    required this.uploadColor,
    required this.gridColor,
    required this.labelStyle,
    required this.textDirection,
    required this.pulse,
    super.repaint,
  });

  final List<SpeedTestSample> samples;
  final double maxMbps;
  final double maxSeconds;
  final SpeedTestPhase? activePhase;
  final Color downloadColor;
  final Color uploadColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final TextDirection textDirection;

  final double pulse;

  static const _left = 44.0;
  static const _right = 6.0;
  static const _top = 10.0;
  static const _bottom = 20.0;
  static const _ticks = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );
    if (plot.width <= 12 || plot.height <= 12) return;

    _paintGrid(canvas, plot);
    canvas.save();
    canvas.clipRect(plot.inflate(14));
    _paintSeries(
      canvas,
      plot,
      phase: SpeedTestPhase.download,
      color: downloadColor,
      pulseEnd: activePhase == SpeedTestPhase.download,
    );
    _paintSeries(
      canvas,
      plot,
      phase: SpeedTestPhase.upload,
      color: uploadColor,
      pulseEnd: activePhase == SpeedTestPhase.upload,
    );
    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Rect plot) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (var i = 0; i <= _ticks; i++) {
      final ratio = i / _ticks;
      final y = plot.bottom - plot.height * ratio;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _paintText(
        canvas,
        _formatTick(maxMbps * ratio),
        Offset(plot.left - 8, y),
        alignRight: true,
      );
    }
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);

    for (var i = 0; i <= _ticks; i++) {
      final ratio = i / _ticks;
      final x = plot.left + plot.width * ratio;
      _paintText(
        canvas,
        '${(maxSeconds * ratio).round()}s',
        Offset(x, plot.bottom + 5),
        center: true,
      );
    }
  }

  void _paintSeries(
    Canvas canvas,
    Rect plot, {
    required SpeedTestPhase phase,
    required Color color,
    required bool pulseEnd,
  }) {
    final points = <Offset>[];
    for (final sample in samples) {
      if (sample.phase != phase) continue;
      final seconds = sample.elapsed.inMilliseconds / 1000;
      points.add(
        Offset(
          plot.left + plot.width * (seconds / maxSeconds).clamp(0.0, 1.0),
          plot.bottom - plot.height * (sample.mbps / maxMbps).clamp(0.0, 1.0),
        ),
      );
    }
    if (points.isEmpty) return;

    final fillPath = _smoothPath(points)
      ..lineTo(points.last.dx, plot.bottom)
      ..lineTo(points.first.dx, plot.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, plot.top),
          Offset(0, plot.bottom),
          [color.withValues(alpha: 0.26), color.withValues(alpha: 0.02)],
        ),
    );

    canvas.drawPath(
      _smoothPath(points),
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final head = points.last;
    if (pulseEnd) {
      canvas.drawCircle(
        head,
        3.5 + 9 * pulse,
        Paint()..color = color.withValues(alpha: 0.28 * (1 - pulse)),
      );
    }
    canvas.drawCircle(head, 3.5, Paint()..color = color);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midX = (current.dx + next.dx) / 2;
      path.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
    }
    return path;
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: textDirection,
    )..layout();
    final dx = alignRight
        ? anchor.dx - painter.width
        : (center ? anchor.dx - painter.width / 2 : anchor.dx);
    final dy = alignRight ? anchor.dy - painter.height / 2 : anchor.dy;
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(_SpeedChartPainter old) =>
      old.samples != samples ||
      old.maxMbps != maxMbps ||
      old.maxSeconds != maxSeconds ||
      old.activePhase != activePhase ||
      old.pulse != pulse ||
      old.labelStyle != labelStyle ||
      old.downloadColor != downloadColor ||
      old.uploadColor != uploadColor;
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.background,
    required this.foreground,
    this.size = 20,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 20,
      height: size + 20,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: size, color: foreground),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyStateWidget(
              icon: Icons.speed_outlined,
              message: '网络测速暂不可用',
              subtitle: message,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

String _phaseLabel(SpeedTestPhase? phase) => switch (phase) {
  SpeedTestPhase.latency => '延迟探测中',
  SpeedTestPhase.download => '下行测速中',
  SpeedTestPhase.upload => '上行测速中',
  null => '就绪',
};

double _axisMaxMbps(List<SpeedTestSample> samples) {
  if (samples.isEmpty) return 100;
  final peak = samples
      .map((sample) => sample.mbps)
      .reduce((a, b) => a > b ? a : b);
  if (peak <= 0) return 100;
  return _pickAxis(peak, const [
    4.0,
    8.0,
    20.0,
    40.0,
    60.0,
    80.0,
    100.0,
    200.0,
    400.0,
    600.0,
    800.0,
    1000.0,
    2000.0,
    4000.0,
    10000.0,
  ]);
}

double _axisMaxSeconds(List<SpeedTestSample> samples) {
  if (samples.isEmpty) return 12;
  final seconds = samples
      .map((sample) => sample.elapsed.inMilliseconds / 1000)
      .reduce((a, b) => a > b ? a : b);
  return _pickAxis(seconds, const [
    4.0,
    8.0,
    12.0,
    16.0,
    20.0,
    24.0,
    32.0,
    40.0,
    60.0,
    80.0,
    120.0,
  ]);
}

double _pickAxis(double value, List<double> steps) {
  for (final step in steps) {
    if (step >= value) return step;
  }
  return (value / 4).ceilToDouble() * 4;
}

String _formatTick(double value) {
  if (value >= 100) return value.round().toString();
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}
