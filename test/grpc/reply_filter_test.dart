import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/common/constants.dart';
import 'package:pili_aurora_next/generated/bilibili/main/community/reply/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/grpc/reply.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';

import '../support/memory_box.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MainListReply body;
  ReplyInfo reply(int id, String text, [List<ReplyInfo>? children]) =>
      ReplyInfo(
        id: Int64(id),
        content: Content(message: text),
        replies: children,
      );
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                headers: Headers.fromMap({
                  'grpc-status': ['0'],
                }),
                data: GrpcReq.compressProtobuf(body.writeToBuffer()),
              ),
            );
          },
        ),
      );
  });
  setUp(() async {
    await GStorage.setting.putAll({
      SettingBoxKey.banWordForReply: 'blocked',
      SettingBoxKey.antiGoodsReply: true,
    });
  });
  tearDownAll(() => Request.dio.close(force: true));

  Future<MainListReply> query() async => (await ReplyGrpc.mainList(
    account: const NoAccount(),
    oid: 1,
    mode: Mode.MAIN_LIST_HOT,
    offset: null,
    cursorNext: null,
  )).dataOrNull!;

  test(
    'top and ordinary replies filter keyword and goods child previews equally',
    () async {
      List<ReplyInfo> children() => [
        reply(2, 'blocked'),
        reply(3, Constants.goodsUrlPrefix),
        reply(4, 'allowed'),
      ];
      body = MainListReply(
        upTop: reply(1, 'allowed', children()),
        replies: [reply(5, 'allowed', children())],
      );
      final result = await query();
      expect(result.upTop.replies.map((r) => r.id.toInt()), [4]);
      expect(result.replies.single.replies.map((r) => r.id.toInt()), [4]);
    },
  );

  test(
    'blocked top reply is removed and disabled filters preserve children',
    () async {
      body = MainListReply(upTop: reply(1, 'blocked'));
      expect((await query()).hasUpTop(), isFalse);
      await GStorage.setting.putAll({
        SettingBoxKey.banWordForReply: '',
        SettingBoxKey.antiGoodsReply: false,
      });
      body = MainListReply(upTop: reply(1, 'allowed', [reply(2, 'blocked')]));
      expect((await query()).upTop.replies.single.id.toInt(), 2);
    },
  );
}
