import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/pages/video/controller.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';

Widget buildDmChart(
  Color themeColor,
  List<double> dmTrend,
  VideoDetailController videoDetailController, [
  double offset = 0,
]) {
  final color = Pref.dmChartColor ?? themeColor;
  return IgnorePointer(
    child: Container(
      height: 12,
      margin: EdgeInsets.only(
        bottom:
            videoDetailController.viewPointList.isNotEmpty &&
                videoDetailController.showVP.value
            ? 19.25 + offset
            : 4.25 + offset,
      ),
      child: LineChart(
        LineChartData(
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (dmTrend.length - 1).toDouble(),
          minY: 0,
          maxY: dmTrend.max,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                dmTrend.length,
                (index) => FlSpot(
                  index.toDouble(),
                  dmTrend[index],
                ),
              ),
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
