import 'package:pili_aurora_next/models/search/result.dart';
import 'package:pili_aurora_next/models/search/search_esports.dart';
import 'package:pili_aurora_next/pages/search_panel/video/controller.dart';

class SearchAllController extends SearchVideoController with SearchVideoMixin {
  SearchAllController({
    required super.keyword,
    required super.searchType,
    required super.tag,
  });
  List<SearchUser>? get searchUser => results?.users;
  List<SearchPgcItemModel>? get searchMedia => results?.media;
  List<SearchActivity>? get searchActivity => results?.activities;
  SearchEsports? get searchEsports => results?.esports;
}
