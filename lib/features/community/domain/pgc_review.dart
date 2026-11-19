enum PgcReviewType {
  long('长评'),
  short('短评');

  const PgcReviewType(this.label);
  final String label;
}

enum PgcReviewSortType {
  def('默认'),
  latest('最新');

  const PgcReviewSortType(this.label);
  final String label;
}

enum PgcReviewAction { like, dislike, delete }

typedef PgcReviewAuthor = ({
  String? avatar,
  int? level,
  int? mid,
  String? uname,
  bool annualVip,
});

typedef PgcReviewStat = ({bool liked, bool disliked, int? likes});

class PgcReviewItem {
  const PgcReviewItem({
    this.author,
    this.title,
    this.content,
    this.pushTimeStr,
    this.reviewId,
    this.score = 0,
    this.articleId,
    this.stat = (liked: false, disliked: false, likes: null),
  });

  final PgcReviewAuthor? author;
  final String? title, content, pushTimeStr;
  final int? reviewId, articleId;
  final int score;
  final PgcReviewStat stat;

  PgcReviewItem withStat(PgcReviewStat next) => PgcReviewItem(
    author: author,
    title: title,
    content: content,
    pushTimeStr: pushTimeStr,
    reviewId: reviewId,
    score: score,
    articleId: articleId,
    stat: next,
  );
}
