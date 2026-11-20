enum ReplyOptionType {
  allow('允许评论'),
  close('关闭评论'),
  choose('精选评论'),
  ;

  final String title;
  const ReplyOptionType(this.title);
}
