import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Description;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/dynamic_activity.dart';
import 'package:pili_aurora_next/features/community/domain/dynamic_activity_item.dart';
import 'package:pili_aurora_next/generated/bilibili/app/dynamic/v2.pb.dart'
    show
        Description,
        DescType,
        DynamicItem,
        DynModuleType,
        EmoteNode,
        EmoteSize,
        Extend,
        LikeListReply,
        LikeListReq,
        LinkNode,
        LinkNodeType,
        MdlDynDraw,
        MdlDynDrawItem,
        Module,
        ModuleAuthor,
        ModuleDesc,
        ModuleOpusSummary,
        OfficialVerify,
        Paragraph,
        RepostListRsp,
        RepostListReq,
        TextNode,
        TextNode_TextNodeType,
        TextParagraph,
        UserInfo,
        UserPendant,
        VipInfo,
        WordNode;
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/pages/common/dyn/like_list/view.dart';
import 'package:pili_aurora_next/pages/common/dyn/repost_list/view.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final interceptor = ControlledInterceptor(
    headers: Headers.fromMap({
      'grpc-status': ['0'],
    }),
  );
  final requests = interceptor.requests;
  late ProviderContainer container;
  LoginAccount account([String csrf = 'fixture']) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': csrf}),
    null,
    null,
  );
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(() {
    requests.clear();
    Accounts.accountMode[AccountType.main.index] = account();
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    for (final request in requests) {
      if (!request.reply.isCompleted) request.reply.complete(<int>[]);
    }
    await tick();
    Get.reset();
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  test('点赞作者保留外层成员 ID、空签名的存在性及头像装饰', () async {
    final provider = dynamicLikesProvider((owner: Object(), id: '12'));
    container.listen(provider, (_, _) {});
    final first = container.read(provider.notifier).activate();
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(
      GrpcReq.compressProtobuf(
        LikeListReply(
          list: [
            ModuleAuthor(
              mid: Int64.parseInt('9007199254740993'),
              author: UserInfo(
                mid: Int64(2),
                name: '作者',
                face: 'avatar',
                sign: '',
                level: 6,
                isSeniorMember: 1,
                vip: VipInfo(status: 1, type: 2),
                official: OfficialVerify(type: 0),
                pendant: UserPendant(image: 'pendant'),
              ),
            ),
            ModuleAuthor(mid: Int64(3)),
          ],
        ).writeToBuffer(),
      ),
    );
    await first;

    final [author, missing] = container.read(provider).loading.data;
    expect(
      author,
      isA<DynamicActivityAuthor>()
          .having((author) => author.mid, '成员 ID', '9007199254740993')
          .having((author) => author.name, '名字', '作者')
          .having((author) => author.face, '头像', 'avatar')
          .having((author) => author.sign, '空签名', '')
          .having((author) => author.level, '等级', 6)
          .having((author) => author.isSeniorMember, '资深会员', isTrue)
          .having((author) => author.hasAnnualVip, '年费大会员', isTrue)
          .having((author) => author.vipStatus, '大会员状态', 1)
          .having((author) => author.officialType, '认证类型', 0)
          .having((author) => author.pendantImage, '挂件', 'pendant'),
    );
    expect(missing.sign, isNull);
    expect(missing.vipStatus, isNull);
    expect(missing.officialType, isNull);
    expect(missing.pendantImage, isNull);
  });

  test('转发保留摘要优先级、富文本类型及无 ID 条目的分页去重', () async {
    Module author(int mid, String time) => Module(
      moduleType: DynModuleType.module_author,
      moduleAuthor: ModuleAuthor(
        mid: Int64(100),
        author: UserInfo(mid: Int64(mid)),
        ptimeLabelText: time,
      ),
    );
    ModuleOpusSummary summary(List<TextNode> nodes) => ModuleOpusSummary(
      summary: Paragraph(text: TextParagraph(nodes: nodes)),
    );
    Module fallbackSummary(String text) => Module(
      moduleType: DynModuleType.module_opus_summary,
      moduleOpusSummary: summary([TextNode(rawText: text)]),
    );
    Module description(List<Description> pieces) => Module(
      moduleType: DynModuleType.module_desc,
      moduleDesc: ModuleDesc(desc: pieces),
    );
    final rich = DynamicItem(
      extend: Extend(
        dynIdStr: '9',
        opusSummary: summary([
          TextNode(rawText: '原文'),
          TextNode(
            nodeType: TextNode_TextNodeType.EMOTE,
            emote: EmoteNode(
              rawText: WordNode(words: '[表情]'),
              emoteUrl: 'emote',
              emoteWidth: EmoteSize(emojiSize: 2),
            ),
          ),
          TextNode(
            rawText: '投票题目',
            link: LinkNode(linkTypeEnum: LinkNodeType.VOTE, bizId: 'bad'),
          ),
          TextNode(
            rawText: '链接原文',
            link: LinkNode(
              linkTypeEnum: LinkNodeType.URL,
              showText: WordNode(words: '链接名称'),
              link: 'https://example.com',
            ),
          ),
          TextNode(
            rawText: '节目',
            link: LinkNode(
              linkTypeEnum: LinkNodeType.OGV_EP,
              link: 'bilibili://bangumi/season/ep42',
            ),
          ),
          TextNode(
            link: LinkNode(
              linkTypeEnum: LinkNodeType.REPOST_PIC_DYN_URL,
              linkPics: MdlDynDraw(
                items: [
                  MdlDynDrawItem(
                    src: 'picture',
                    width: Int64(120),
                    height: Int64(240),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
      modules: [
        author(1, '旧作者'),
        fallbackSummary('不显示模块摘要'),
        description([Description(text: '不显示旧式描述')]),
        author(2, '刚刚'),
      ],
    );
    final fallback = DynamicItem(
      modules: [
        author(3, ''),
        fallbackSummary('首个模块摘要'),
        fallbackSummary('第二个模块摘要'),
      ],
    );
    final legacy = DynamicItem(
      modules: [
        author(3, ''),
        description([Description(text: '旧描述')]),
        description([
          Description(text: '文字'),
          Description(text: '空链接', uri: ''),
          Description(
            type: DescType.desc_type_emoji,
            text: '[表情]',
            uri: 'legacy-emote',
          ),
        ]),
      ],
    );
    final empty = DynamicItem(modules: [author(4, '')]);
    final provider = dynamicRepostsProvider((owner: Object(), id: '12'));
    container.listen(provider, (_, _) {});
    final notifier = container.read(provider.notifier);
    final first = notifier.activate();
    await interceptor.waitForRequests(1);
    requests[0].reply.complete(
      GrpcReq.compressProtobuf(
        RepostListRsp(
          list: [rich, fallback, legacy, empty, DynamicItem()],
          hasMore: true,
          offset: 'next',
        ).writeToBuffer(),
      ),
    );
    await first;

    final [entry, moduleSummary, oldDescription, noContent, noAuthor] =
        container.read(provider).loading.data;
    expect(entry.id, '9');
    expect(entry.author?.mid, '2');
    expect(entry.timeLabel, '刚刚');
    expect(
      entry.content!.map(_contentValue),
      [
        '原文',
        (text: '[表情]', url: 'emote', scale: 2),
        (title: '投票题目', id: -1),
        (
          text: '链接名称',
          url: 'https://example.com',
          kind: RepostLinkKind.external,
        ),
        (
          text: '节目',
          url: 'bilibili://bangumi/season/ep42',
          kind: RepostLinkKind.series,
        ),
        [(url: 'picture', width: 120, height: 240)],
      ],
    );
    expect(moduleSummary.content!.map(_contentValue), ['首个模块摘要']);
    expect(oldDescription.content!.map(_contentValue), [
      '文字',
      (text: '空链接', url: '', kind: RepostLinkKind.plain),
      (text: '[表情]', url: 'legacy-emote', scale: 1),
    ]);
    expect(noContent.content, isNull);
    expect(noAuthor.author, isNull);

    final next = notifier.onLoadMore();
    await interceptor.waitForRequests(2);
    requests[1].reply.complete(
      GrpcReq.compressProtobuf(
        RepostListRsp(
          list: [
            fallback,
            DynamicItem(modules: fallback.modules, serverInfo: 'distinct'),
          ],
        ).writeToBuffer(),
      ),
    );
    await next;
    expect(container.read(provider).loading.data, hasLength(6));
  });

  for (final likes in [true, false]) {
    final label = likes ? '点赞' : '转发';
    dynamic response(
      List<int> ids,
      String offset, {
      bool more = true,
      int total = 12,
    }) => GrpcReq.compressProtobuf(
      likes
          ? LikeListReply(
              totalCount: Int64(total),
              hasMore: more,
              list: [
                for (final id in ids)
                  ModuleAuthor(
                    mid: Int64(id),
                    author: UserInfo(name: '用户 $id', sign: '签名 $id'),
                  ),
              ],
            ).writeToBuffer()
          : RepostListRsp(
              totalCount: Int64(total),
              hasMore: more,
              offset: offset,
              list: [
                for (final id in ids)
                  DynamicItem(
                    extend: Extend(dynIdStr: '$id'),
                    modules: [
                      Module(
                        moduleType: DynModuleType.module_author,
                        moduleAuthor: ModuleAuthor(
                          author: UserInfo(mid: Int64(id), name: '用户 $id'),
                          ptimeLabelText: '刚刚',
                        ),
                      ),
                      Module(
                        moduleType: DynModuleType.module_desc,
                        moduleDesc: ModuleDesc(
                          desc: [Description(text: '转发正文 $id')],
                        ),
                      ),
                    ],
                  ),
              ],
            ).writeToBuffer(),
    );
    void expectCursor(int index, String cursor, int page) {
      final data = GrpcReq.decompressProtobuf(requests[index].options.data);
      if (likes) {
        final request = LikeListReq.fromBuffer(data);
        expect(request.dynamicId, '12');
        expect(request.uidOffset.toString(), cursor.isEmpty ? '0' : cursor);
        expect(request.page, page);
      } else {
        final request = RepostListReq.fromBuffer(data);
        expect(request.dynamicId, '12');
        expect(request.offset, cursor);
      }
    }

    test('$label 标题订阅不提前查询，首次激活互斥，失败保留名单与计数并重试原页', () async {
      final query = (owner: Object(), id: '12');
      final provider = likes
          ? dynamicLikesProvider(query)
          : dynamicRepostsProvider(query);
      container.listen(provider, (_, _) {});
      final DynamicActivity<Object> notifier = likes
          ? container.read(dynamicLikesProvider(query).notifier)
          : container.read(dynamicRepostsProvider(query).notifier);
      await tick();
      expect(requests, isEmpty);
      final first = notifier.activate();
      await notifier.activate();
      await interceptor.waitForRequests(1);
      expectCursor(0, '', 1);
      requests[0].reply.complete(response([1, 2], '2'));
      await first;
      expect(container.read(provider).metadata?.total, 12);
      final failed = notifier.onLoadMore();
      await interceptor.waitForRequests(2);
      expectCursor(1, '2', 2);
      requests[1].reply.complete(<int>[]);
      await failed;
      expect(container.read(provider).loading.data, hasLength(2));
      expect(container.read(provider).metadata?.total, 12);
      expect(container.read(provider).canLoadMore, isFalse);
      final retry = notifier.retry();
      await interceptor.waitForRequests(3);
      expectCursor(2, '2', 2);
      requests[2].reply.complete(response([2, 3], '3', total: 13));
      await retry;
      expect(container.read(provider).loading.data, hasLength(3));
      expect(container.read(provider).metadata?.total, 13);
    });

    test('$label 刷新保留快照，迟到分页不改计数，相同动态的第二页面独立查询', () async {
      final query = (owner: Object(), id: '12');
      final provider = likes
          ? dynamicLikesProvider(query)
          : dynamicRepostsProvider(query);
      container.listen(provider, (_, _) {});
      final DynamicActivity<Object> notifier = likes
          ? container.read(dynamicLikesProvider(query).notifier)
          : container.read(dynamicRepostsProvider(query).notifier);
      final first = notifier.activate();
      await interceptor.waitForRequests(1);
      requests[0].reply.complete(response([1], '1'));
      await first;
      final old = notifier.onLoadMore();
      await interceptor.waitForRequests(2);
      final refresh = notifier.onRefresh();
      await interceptor.waitForRequests(3);
      expect(container.read(provider).loading.data, hasLength(1));
      expect(container.read(provider).metadata?.total, 12);
      expectCursor(2, '', 1);
      requests[2].reply.complete(response([4], '4', more: false, total: 4));
      await refresh;
      requests[1].reply.complete(response([2], '2', total: 99));
      await old;
      expect(container.read(provider).loading.data, hasLength(1));
      expect(container.read(provider).metadata?.total, 4);
      final secondQuery = (owner: Object(), id: '12');
      final second = likes
          ? dynamicLikesProvider(secondQuery)
          : dynamicRepostsProvider(secondQuery);
      final sub = container.listen(second, (_, _) {});
      final DynamicActivity<Object> other = likes
          ? container.read(dynamicLikesProvider(secondQuery).notifier)
          : container.read(dynamicRepostsProvider(secondQuery).notifier);
      final start = other.activate();
      await interceptor.waitForRequests(4);
      requests[3].reply.complete(response([5], '5', more: false, total: 5));
      await start;
      expect(container.read(second).metadata?.total, 5);
      expect(container.read(provider).metadata?.total, 4);
      sub.close();
      await container.pump();
      Accounts.replaceCredentials(account('new'));
      expect(container.read(provider).metadata, isNull);
      expect(container.read(provider).loading, isA<Loading>());
      await interceptor.waitForRequests(5);
      requests[4].reply.complete(response([6], '6', more: false, total: 6));
      await tick();
      expect(requests, hasLength(5));
    });

    testWidgets('$label 实际面板激活与错误重试，替换资源后旧响应不回写', (tester) async {
      final owner = Object();
      Widget panel(String id) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: likes
                ? DynLikePage(query: (owner: owner, id: id), isPortrait: false)
                : DynRepostPage(
                    query: (owner: owner, id: id),
                    isPortrait: false,
                  ),
          ),
        ),
      );
      Future<void> until(int count) async {
        for (var i = 0; i < 100 && requests.length < count; i++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(requests, hasLength(count));
      }

      await tester.pumpWidget(panel('12'));
      await until(1);
      requests[0].reply.complete(<int>[]);
      await tester.pumpAndSettle();
      final button = find.text('点击重试');
      expect(button, findsWidgets);
      await tester.tap(button.first);
      await until(2);
      await tester.pumpWidget(panel('13'));
      await until(3);
      requests[1].reply.complete(response([2], '', more: false, total: 88));
      requests[2].reply.complete(response([3], '', more: false, total: 1));
      await tester.pumpAndSettle();
      final query = (owner: owner, id: '13');
      final state = likes
          ? container.read(dynamicLikesProvider(query))
          : container.read(dynamicRepostsProvider(query));
      expect(state.metadata?.total, 1);
      expect(find.text('用户 2'), findsNothing);
      expect(find.text('用户 3'), findsOneWidget);
      expect(
        find.text(likes ? '签名 3' : '转发正文 3', findRichText: true),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}

Object _contentValue(RepostContent content) => switch (content) {
  RepostText(:final text) => text,
  RepostEmote(:final text, :final url, :final scale) => (
    text: text,
    url: url,
    scale: scale,
  ),
  RepostLink(:final text, :final url, :final kind) => (
    text: text,
    url: url,
    kind: kind,
  ),
  RepostVote(:final title, :final id) => (title: title, id: id),
  RepostImages(:final images) => images,
};
