import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_cursor.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_item.dart';
import 'package:pili_aurora_next/features/content_discovery/domain/discovery_page.dart';
import 'package:pili_aurora_next/generated/bilibili/app/dynamic/v2.pb.dart'
    show
        Description,
        DynamicItem,
        ModuleAuthor,
        ModuleDesc,
        ModuleOpusSummary,
        TextNode,
        UserInfo;
import 'package:pili_aurora_next/grpc/dyn.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';

final dynamicActivityRepositoryProvider = Provider(
  (ref) => const DynamicActivityRepository(),
);

class DynamicActivityRepository {
  const DynamicActivityRepository();
  Future<
    LoadingState<DiscoveryPage<DynamicActivityAuthor, DynamicActivityCursor>>
  >
  likes(
    Account account,
    String id,
    int page,
    DynamicActivityCursor? cursor,
  ) async {
    final result = await DynGrpc.likeList(
      account: account,
      dynamicId: id,
      page: page,
      uidOffset: cursor?.offset == null
          ? null
          : Int64.parseInt(cursor!.offset!),
    );
    if (result case Success(:final response)) {
      return Success(
        _page(
          [
            for (final item in response.list)
              _author(item.author, item.mid.toString()),
          ],
          response.list.lastOrNull?.mid.toString(),
          response.hasMore,
          response.totalCount.toInt(),
          cursor,
        ),
      );
    }
    return result as Error;
  }

  Future<LoadingState<DiscoveryPage<DynamicRepostEntry, DynamicActivityCursor>>>
  reposts(
    Account account,
    String id,
    DynamicActivityCursor? cursor,
  ) async {
    final result = await DynGrpc.repostList(
      account: account,
      dynamicId: id,
      offset: cursor?.offset,
    );
    if (result case Success(:final response)) {
      return Success(
        _page(
          response.list.map(_repost).toList(),
          response.offset,
          response.hasMore,
          response.totalCount.toInt(),
          cursor,
        ),
      );
    }
    return result as Error;
  }

  DiscoveryPage<T, DynamicActivityCursor> _page<T>(
    List<T> items,
    String? offset,
    bool more,
    int total,
    DynamicActivityCursor? cursor,
  ) {
    final seen = {...?cursor?.seen};
    final hasMore =
        more && offset != null && offset.isNotEmpty && seen.add(offset);
    return DiscoveryPage(
      items,
      metadata: DynamicActivityCursor(offset, Set.unmodifiable(seen), total),
      hasMore: hasMore,
    );
  }
}

DynamicActivityAuthor _author(UserInfo author, String mid) =>
    DynamicActivityAuthor(
      mid: mid,
      name: author.name,
      face: author.face,
      level: author.level,
      isSeniorMember: author.isSeniorMember == 1,
      hasAnnualVip: author.vip.status > 0 && author.vip.type == 2,
      sign: author.hasSign() ? author.sign : null,
      pendantImage: author.hasPendant() ? author.pendant.image : null,
      vipStatus: author.hasVip() ? author.vip.status : null,
      officialType: author.hasOfficial() ? author.official.type : null,
    );

DynamicRepostEntry _repost(DynamicItem item) {
  ModuleAuthor? author;
  ModuleDesc? description;
  ModuleOpusSummary? summary = item.extend.hasOpusSummary()
      ? item.extend.opusSummary
      : null;
  for (final module in item.modules) {
    switch (module.moduleType) {
      case .module_author:
        author = module.moduleAuthor;
      case .module_opus_summary:
        summary ??= module.moduleOpusSummary;
      case .module_desc:
        description = module.moduleDesc;
      default:
    }
  }

  final id = item.extend.dynIdStr;
  final user = author?.author;
  return DynamicRepostEntry(
    id: id,
    key: id.isEmpty ? _UnidentifiedRepostKey(item..freeze()) : id,
    author: user == null ? null : _author(user, user.mid.toString()),
    timeLabel: author?.ptimeLabelText ?? '',
    content: switch ((summary, description)) {
      (final summary?, _) => List.unmodifiable(
        summary.summary.text.nodes.map(_summaryContent),
      ),
      (null, final description?) => List.unmodifiable(
        description.desc.map(_descriptionContent),
      ),
      _ => null,
    },
  );
}

class _UnidentifiedRepostKey {
  const _UnidentifiedRepostKey(this._item);

  final DynamicItem _item;

  @override
  bool operator ==(Object other) =>
      other is _UnidentifiedRepostKey && _item == other._item;

  @override
  int get hashCode => _item.hashCode;
}

RepostContent _summaryContent(TextNode node) {
  if (node.nodeType == .EMOTE && node.hasEmote()) {
    final emote = node.emote;
    final size = emote.emoteWidth;
    return RepostEmote(
      emote.rawText.words,
      emote.emoteUrl,
      size.hasEmojiSize() ? size.emojiSize : 1,
    );
  }
  if (!node.hasLink()) return RepostText(node.rawText);

  final link = node.link;
  return switch (link.linkTypeEnum) {
    .REPOST_PIC_DYN_URL ||
    .REPOST_PIC_URL when link.hasLinkPics() => RepostImages(
      List.unmodifiable(
        link.linkPics.items.map(
          (image) => (
            url: image.src,
            width: image.width.toInt(),
            height: image.height.toInt(),
          ),
        ),
      ),
    ),
    .VOTE when link.hasBizId() => RepostVote(
      node.rawText,
      int.tryParse(link.bizId) ?? -1,
    ),
    final type => RepostLink(
      link.hasShowText() ? link.showText.words : node.rawText,
      link.link,
      kind: switch (type) {
        .URL => .external,
        .OGV_SS || .OGV_EP => .series,
        _ => .plain,
      },
    ),
  };
}

RepostContent _descriptionContent(Description description) =>
    switch (description.type) {
      .desc_type_emoji => RepostEmote(
        description.text,
        description.uri,
        description.hasEmojiSize() ? description.emojiSize : 1,
      ),
      _ when description.hasUri() => RepostLink(
        description.text,
        description.uri,
      ),
      _ => RepostText(description.text),
    };
