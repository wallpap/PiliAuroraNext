import 'package:pili_aurora_next/features/community/domain/comment.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart'
    as wire;

final _replySources = Expando<wire.ReplyInfo>();
final _contentSources = Expando<wire.Content>();

CommentReply commentFromProtocol(wire.ReplyInfo reply) {
  reply.freeze();
  final member = reply.member;
  final garb = reply.memberV2.garb;
  final control = reply.replyControl;
  final content = commentContentFromProtocol(reply.content);
  _replySources[content] = reply;
  return CommentReply(
    id: reply.id,
    oid: reply.oid,
    type: reply.type,
    mid: reply.mid,
    rootId: reply.hasRoot() ? reply.root : null,
    parent: reply.parent,
    dialog: reply.dialog,
    ctime: reply.ctime,
    count: reply.count,
    like: reply.like,
    member: (
      mid: member.mid,
      name: member.name,
      face: member.face,
      level: member.level.toInt(),
      vipStatus: member.vipStatus.toInt(),
      vipType: member.vipType.toInt(),
      officialVerifyType: member.officialVerifyType.toInt(),
      isSeniorMember: member.isSeniorMember == 1,
      pendantImage: member.hasGarbPendantImage()
          ? member.garbPendantImage
          : null,
      medalLevel: member.hasFansMedalLevel()
          ? member.fansMedalLevel.toInt()
          : null,
      medalName: member.fansMedalName,
      medalColor: member.fansMedalColor.toInt(),
      medalNameColor: member.fansMedalColorName.toInt(),
    ),
    garb: (
      cardImage: garb.hasCardImage() ? garb.cardImage : null,
      cardNumber: garb.hasCardNumber() ? garb.cardNumber : null,
      cardFanColor: garb.cardFanColor,
      fanNumPrefix: garb.fanNumPrefix,
    ),
    authorLevel: reply.hasMember()
        ? member.level.toInt()
        : reply.memberV2.hasBasic()
        ? reply.memberV2.basic.level.toInt()
        : null,
    replyControl: CommentControl(
      action: control.action,
      isUpTop: control.isUpTop,
      showTranslation: control.showTranslation,
      canTranslate:
          control.translationSwitch == .TRANSLATION_SWITCH_SHOW_TRANSLATION,
      upReply: control.upReply,
      isNote: control.isNote,
      isNoteV2: control.isNoteV2,
      cardLabels: List.unmodifiable(
        control.cardLabels.map((label) => label.textContent),
      ),
      location: control.hasLocation() ? control.location : null,
      voteOption: control.hasVoteOption()
          ? (
              side: switch (control.voteOption.labelKind) {
                .RED => .red,
                .BLUE => .blue,
                _ => .other,
              },
              desc: control.voteOption.desc,
            )
          : null,
    ),
    content: content,
    translatedContent: reply.hasTranslatedContent()
        ? commentContentFromProtocol(reply.translatedContent)
        : null,
    replies: reply.replies.map(commentFromProtocol).toList(),
  );
}

CommentContent commentContentFromProtocol(wire.Content content) {
  content.freeze();
  final projected = CommentContent(
    message: content.message,
    pictures: List.unmodifiable(
      content.pictures.map(
        (picture) => (
          imgSrc: picture.imgSrc,
          imgWidth: picture.imgWidth,
          imgHeight: picture.imgHeight,
        ),
      ),
    ),
    emotes: Map.unmodifiable(
      content.emotes.map(
        (key, emote) => MapEntry(key, (
          size: emote.size.toInt(),
          url: emote.url,
          webpUrl: emote.hasWebpUrl() ? emote.webpUrl : null,
          gifUrl: emote.hasGifUrl() ? emote.gifUrl : null,
          jumpUrl: emote.hasJumpUrl() ? emote.jumpUrl : null,
        )),
      ),
    ),
    urls: Map.unmodifiable(
      content.urls.map(
        (key, url) => MapEntry(key, (
          title: url.title,
          prefixIcon: url.hasPrefixIcon() ? url.prefixIcon : null,
          isNote: url.clickReport.startsWith('{"cvid'),
          isWordSearch: url.extra.isWordSearch,
          appUrlSchema: url.appUrlSchema,
        )),
      ),
    ),
    topics: Set.unmodifiable(content.topics.keys),
    atNameToMid: Map.unmodifiable(content.atNameToMid),
    vote: (title: content.vote.title, id: content.vote.id),
    noteUrl: content.richText.note.hasClickUrl()
        ? content.richText.note.clickUrl
        : null,
    opusId: content.richText.opus.hasOpusId()
        ? content.richText.opus.opusId
        : null,
  );
  _contentSources[projected] = content;
  return projected;
}

List<Object?> commentPicturesForAntifraud(CommentReply reply) =>
    _contentSources[reply.content]?.pictures
        .map((picture) => picture.toProto3Json())
        .toList() ??
    const [];

wire.ReplyInfo commentForArchive(
  CommentReply reply, {
  bool includeReplies = true,
}) {
  final source = _replySources[reply.content]!;
  final result = source.deepCopy();
  if (reply.like != source.like) result.like = reply.like;
  if (reply.count != source.count) result.count = reply.count;
  final control = reply.replyControl;
  if (control.action != source.replyControl.action) {
    result.ensureReplyControl().action = control.action;
  }
  if (control.isUpTop != source.replyControl.isUpTop) {
    result.ensureReplyControl().isUpTop = control.isUpTop;
  }
  if (control.showTranslation != source.replyControl.showTranslation) {
    result.ensureReplyControl().showTranslation = control.showTranslation;
  }
  final translated = reply.translatedContent;
  if (translated != null) {
    final translatedSource = _contentSources[translated]!;
    if (!identical(translatedSource, source.translatedContent)) {
      result.translatedContent = translatedSource.deepCopy();
    }
  }
  result.replies.clear();
  if (includeReplies) {
    result.replies.addAll(reply.replies.map(commentForArchive));
  }
  return result;
}

CommentPage mainCommentPage(wire.MainListReply data) => _commentPage(
  cursor: data.cursor,
  offset: data.paginationReply.nextOffset,
  subject: data.subjectControl,
  count: data.subjectControl.hasCount()
      ? data.subjectControl.count.toInt()
      : -1,
  vote: data.hasVoteCard()
      ? (
          voteId: data.voteCard.voteId,
          title: data.voteCard.title,
          count: data.voteCard.count,
        )
      : null,
  top: data.hasUpTop() ? data.upTop : null,
  rows: data.replies,
);

CommentPage detailCommentPage(wire.DetailListReply data) => _commentPage(
  cursor: data.cursor,
  offset: data.paginationReply.nextOffset,
  subject: data.subjectControl,
  count: data.root.count.toInt(),
  root: data.hasRoot() ? data.root : null,
  rows: data.root.replies,
);

CommentPage dialogCommentPage(wire.DialogListReply data) => _commentPage(
  cursor: data.cursor,
  offset: data.paginationReply.nextOffset,
  subject: data.subjectControl,
  count: -1,
  rows: data.replies,
);

CommentPage _commentPage({
  required wire.CursorReply cursor,
  required String offset,
  required wire.SubjectControl subject,
  required int count,
  required List<wire.ReplyInfo> rows,
  CommentVoteCard? vote,
  wire.ReplyInfo? top,
  wire.ReplyInfo? root,
}) => (
  cursor: cursor.next,
  offset: offset,
  isEnd: cursor.isEnd,
  subject: (
    upMid: subject.upMid,
    title: subject.title,
    rootText: subject.rootText,
    inputDisable: subject.inputDisable,
  ),
  count: count,
  vote: vote,
  top: top == null ? null : commentFromProtocol(top),
  root: root == null ? null : commentFromProtocol(root),
  rows: rows.map(commentFromProtocol).toList(),
);
