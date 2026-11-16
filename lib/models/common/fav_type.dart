enum FavTabType {
  video('视频'),
  bangumi('追番'),
  cinema('追剧'),
  article('专栏'),
  note('笔记'),
  topic('话题'),
  cheese('课堂');

  const FavTabType(this.title);
  final String title;
}
