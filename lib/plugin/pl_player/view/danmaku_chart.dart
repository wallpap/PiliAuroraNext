import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/danmaku/application/danmaku_preferences.dart';

class DanmakuTrendChart extends StatefulWidget {
  const DanmakuTrendChart({
    super.key,
    required this.themeColor,
    required this.trend,
    required this.bottom,
  });

  final Color themeColor;
  final List<double> trend;
  final double bottom;

  @override
  State<DanmakuTrendChart> createState() => _DanmakuTrendChartState();
}

class _DanmakuTrendChartState extends State<DanmakuTrendChart> {
  late List<FlSpot> _spots = _buildSpots();
  late double _maxY = widget.trend.max;

  List<FlSpot> _buildSpots() => [
    for (final (index, value) in widget.trend.indexed)
      FlSpot(index.toDouble(), value),
  ];

  @override
  void didUpdateWidget(DanmakuTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.trend, widget.trend)) {
      _spots = _buildSpots();
      _maxY = widget.trend.max;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = DanmakuPreferences.chartColor ?? widget.themeColor;
    return IgnorePointer(
      child: Container(
        height: 12,
        margin: EdgeInsets.only(bottom: widget.bottom),
        child: LineChart(
          LineChartData(
            titlesData: const FlTitlesData(show: false),
            lineTouchData: const LineTouchData(enabled: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: _spots.last.x,
            minY: 0,
            maxY: _maxY,
            lineBarsData: [
              LineChartBarData(
                spots: _spots,
                isCurved: true,
                barWidth: 1,
                color: color,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: color.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
