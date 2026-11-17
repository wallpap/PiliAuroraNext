import 'package:pili_aurora_next/models/remote/bubble/category_list.dart';
import 'package:pili_aurora_next/models/remote/bubble/sort_info.dart';

class BubbleCatalog {
  BubbleCatalog({
    this.title,
    List<CategoryList> categories = const [],
    this.sort,
  }) : categories = List.unmodifiable(categories);
  final String? title;
  final List<CategoryList> categories;
  final SortInfo? sort;
}
