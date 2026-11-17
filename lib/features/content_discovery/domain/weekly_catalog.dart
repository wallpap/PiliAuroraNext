import 'package:pili_aurora_next/models/remote/popular/popular_series_list/list.dart';
import 'package:pili_aurora_next/models/remote/popular/popular_series_one/config.dart';

class WeeklyCatalog {
  WeeklyCatalog({
    required List<PopularSeriesListItem> series,
    this.number,
    this.config,
    this.reminder,
  }) : series = List.unmodifiable(series);
  final List<PopularSeriesListItem> series;
  final int? number;
  final PopularSeriesConfig? config;
  final String? reminder;
}
