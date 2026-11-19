final class BlockedAuthor {
  const BlockedAuthor({
    this.mid,
    this.mtime,
    this.uname,
    this.face,
  });

  final int? mid;
  final int? mtime;
  final String? uname;
  final String? face;
}

typedef BlockedAuthorPage = ({List<BlockedAuthor> items, int? total});
