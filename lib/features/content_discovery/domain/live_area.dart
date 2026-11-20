final class AreaItem {
  final Object? id;
  final String? name;
  final String? pic;
  final Object? parentId;
  final String? parentName;

  const AreaItem({
    this.id,
    this.name,
    this.pic,
    this.parentId,
    this.parentName,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is AreaItem) {
      return id == other.id && parentId == other.parentId;
    }
    return false;
  }

  @override
  int get hashCode => Object.hash(id, parentId);
}

final class AreaList {
  AreaList({this.name, Iterable<AreaItem> areaList = const []})
    : areaList = List.unmodifiable(areaList);

  final String? name;
  final List<AreaItem> areaList;
}
