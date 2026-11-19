enum FollowKind { fans, same, followed }

bool isCustomFollowTag(int id) => id != 0 && id != -10 && id != -2;

class FollowTag {
  const FollowTag({required this.id, required this.name, this.count, this.tip});

  final int id;
  final String name;
  final int? count;
  final String? tip;

  bool get isCustom => isCustomFollowTag(id);
}
