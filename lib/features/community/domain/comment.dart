import 'package:fixnum/fixnum.dart';

typedef CommentSubject = ({
  Int64 upMid,
  String title,
  String rootText,
  bool inputDisable,
});
typedef CommentVoteCard = ({Int64 voteId, String title, Int64 count});

typedef CommentPage = ({
  Int64 cursor,
  String offset,
  bool isEnd,
  CommentSubject subject,
  int count,
  CommentVoteCard? vote,
  CommentReply? top,
  CommentReply? root,
  List<CommentReply> rows,
});

typedef CommentMember = ({
  Int64 mid,
  String name,
  String face,
  int level,
  int vipStatus,
  int vipType,
  int officialVerifyType,
  bool isSeniorMember,
  String? pendantImage,
  int? medalLevel,
  String medalName,
  int medalColor,
  int medalNameColor,
});

typedef CommentGarb = ({
  String? cardImage,
  String? cardNumber,
  String cardFanColor,
  String fanNumPrefix,
});

typedef CommentPicture = ({String imgSrc, double imgWidth, double imgHeight});
typedef CommentEmote = ({
  int size,
  String url,
  String? webpUrl,
  String? gifUrl,
  String? jumpUrl,
});
typedef CommentUrl = ({
  String title,
  String? prefixIcon,
  bool isNote,
  bool isWordSearch,
  String appUrlSchema,
});

enum CommentVoteSide { red, blue, other }

typedef CommentVoteOption = ({CommentVoteSide side, String desc});

const emptyCommentContent = CommentContent(
  message: '',
  pictures: [],
  emotes: {},
  urls: {},
  topics: {},
  atNameToMid: {},
  vote: (title: '', id: Int64.ZERO),
);

final class CommentContent {
  const CommentContent({
    required this.message,
    required this.pictures,
    required this.emotes,
    required this.urls,
    required this.topics,
    required this.atNameToMid,
    required this.vote,
    this.noteUrl,
    this.opusId,
  });

  final String message;
  final List<CommentPicture> pictures;
  final Map<String, CommentEmote> emotes;
  final Map<String, CommentUrl> urls;
  final Set<String> topics;
  final Map<String, Int64> atNameToMid;
  final ({String title, Int64 id}) vote;
  final String? noteUrl;
  final Int64? opusId;
}

final class CommentControl {
  CommentControl({
    required this.action,
    required this.isUpTop,
    required this.showTranslation,
    required this.canTranslate,
    required this.upReply,
    required this.isNote,
    required this.isNoteV2,
    required this.cardLabels,
    this.location,
    this.voteOption,
  });

  Int64 action;
  bool isUpTop;
  bool showTranslation;
  final bool canTranslate;
  final bool upReply;
  final bool isNote;
  final bool isNoteV2;
  final List<String> cardLabels;
  final String? location;
  final CommentVoteOption? voteOption;

  CommentControl _copy() => CommentControl(
    action: action,
    isUpTop: isUpTop,
    showTranslation: showTranslation,
    canTranslate: canTranslate,
    upReply: upReply,
    isNote: isNote,
    isNoteV2: isNoteV2,
    cardLabels: cardLabels,
    location: location,
    voteOption: voteOption,
  );
}

final class CommentReply {
  CommentReply({
    required this.id,
    required this.oid,
    required this.type,
    required this.mid,
    required this.rootId,
    required this.parent,
    required this.dialog,
    required this.ctime,
    required this.count,
    required this.like,
    required this.member,
    required this.garb,
    required this.replyControl,
    required this.content,
    required this.replies,
    this.authorLevel,
    this.translatedContent,
  });

  final Int64 id;
  final Int64 oid;
  final Int64 type;
  final Int64 mid;
  Int64 get authorMid => mid > Int64.ZERO ? mid : member.mid;
  final Int64? rootId;
  Int64 get root => rootId ?? Int64.ZERO;
  final Int64 parent;
  final Int64 dialog;
  final Int64 ctime;
  Int64 count;
  Int64 like;
  final CommentMember member;
  final CommentGarb garb;
  final int? authorLevel;
  final CommentControl replyControl;
  final CommentContent content;
  CommentContent? translatedContent;
  final List<CommentReply> replies;

  CommentReply copy({List<CommentReply>? replies}) => CommentReply(
    id: id,
    oid: oid,
    type: type,
    mid: mid,
    rootId: rootId,
    parent: parent,
    dialog: dialog,
    ctime: ctime,
    count: count,
    like: like,
    member: member,
    garb: garb,
    authorLevel: authorLevel,
    replyControl: replyControl._copy(),
    content: content,
    translatedContent: translatedContent,
    replies: replies ?? [for (final child in this.replies) child.copy()],
  );
}
