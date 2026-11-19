import 'package:dio/dio.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/generated/bilibili/app/im/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/grpc/url.dart';
import 'package:pili_aurora_next/http/init.dart';
import 'package:pili_aurora_next/services/messaging/session.dart';
import 'package:pili_aurora_next/services/messaging/settings.dart';
import 'package:pili_aurora_next/services/messaging/settings_models.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/controlled_interceptor.dart';
import '../../support/memory_box.dart';
import 'messaging_fixtures.dart';

void main() {
  final interceptor = ControlledInterceptor(
    headers: Headers.fromMap({
      'grpc-status': ['0'],
    }),
  );
  final requests = interceptor.requests;
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.video = MemoryBox();
    GStorage.localCache = MemoryBox();
    Request();
    Request.dio.interceptors
      ..clear()
      ..add(interceptor);
  });
  setUp(requests.clear);
  tearDown(() {
    for (final request in requests) {
      if (!request.reply.isCompleted) request.reply.complete(<int>[]);
    }
  });
  tearDownAll(() async {
    Request.dio.close(force: true);
    await interceptor.close();
  });

  List<int> response(Map<int, Setting> settings) => GrpcReq.compressProtobuf(
    GetImSettingsReply(
      pageTitle: '消息设置',
      settings: settings.entries,
    ).writeToBuffer(),
  );
  final saved = GrpcReq.compressProtobuf(SetImSettingsReply().writeToBuffer());

  final firstSetting = Setting(
    switch_1: SettingSwitch(title: '通知', switchOn: false),
  );
  final secondSetting = Setting(
    switch_1: SettingSwitch(title: '陌生人', switchOn: false),
  );
  Future<WhisperSettingsHandle> load({
    Map<int, Setting>? settings,
    MessagingSession? sharedSession,
  }) async {
    final session = sharedSession ?? sessionFixture();
    final handle = WhisperSettingsHandle(session: session, type: .all);
    if (sharedSession == null) addTearDown(session.dispose);
    addTearDown(handle.dispose);
    final index = requests.length;
    final refresh = handle.refresh();
    await interceptor.waitForRequests(index + 1);
    requests[index].reply.complete(
      response(settings ?? {1: firstSetting, 2: secondSetting}),
    );
    await refresh;
    return handle;
  }

  bool enabled(WhisperSettingsHandle handle, int key) =>
      (handle.state.value.loadingState.dataOrNull![key]!
              as WhisperSettingToggle)
          .enabled;

  SetImSettingsReq writeAt(int index) => SetImSettingsReq.fromBuffer(
    GrpcReq.decompressProtobuf(requests[index].options.data),
  );

  test('私信置顶区分两种写入，失败保留服务端已确认状态', () async {
    final session = sessionFixture();
    final settings = ConversationSettingsHandle(
      session: session,
      talkerUid: 456,
    );
    addTearDown(session.dispose);
    addTearDown(settings.dispose);

    final load = settings.getIsPinned();
    await interceptor.waitForRequests(1);
    final read = requests.single;
    expect(read.options.path, endsWith(GrpcUrl.sessionUpdate));
    final request = SessionUpdateReq.fromBuffer(
      GrpcReq.decompressProtobuf(read.options.data),
    );
    expect(request.sessionId.privateId.talkerUid, Int64(456));
    read.reply.complete(
      GrpcReq.compressProtobuf(
        SessionUpdateReply(session: Session(isPinned: true)).writeToBuffer(),
      ),
    );
    await load;
    expect(settings.state.value.isPinned, isTrue);

    final unpin = settings.setPinned();
    await interceptor.waitForRequests(2);
    expect(requests[1].options.path, endsWith(GrpcUrl.unpinSession));
    requests[1].reply.complete(
      GrpcReq.compressProtobuf(UnPinSessionReply().writeToBuffer()),
    );
    expect((await unpin).isSuccess, isTrue);
    expect(settings.state.value.isPinned, isFalse);

    final pin = settings.setPinned();
    await interceptor.waitForRequests(3);
    expect(requests[2].options.path, endsWith(GrpcUrl.pinSession));
    requests[2].reply.complete(<int>[]);
    expect((await pin).isSuccess, isFalse);
    expect(settings.state.value.isPinned, isFalse);
  });

  test('同键写入串行、不同键并行，失败回到已确认值，刷新等待写入', () async {
    final handle = await load();
    final first = handle.edit(1, const SetWhisperToggle(true));
    await interceptor.waitForRequests(2);
    final queued = handle.edit(1, const SetWhisperToggle(false));
    final other = handle.edit(2, const SetWhisperToggle(true));
    await interceptor.waitForRequests(3);
    expect(writeAt(2).settings.keys, [2]);
    expect(enabled(handle, 1), isFalse);
    expect(enabled(handle, 2), isTrue);
    final refresh = handle.refresh();
    expect(requests, hasLength(3));

    requests[1].reply.complete(saved);
    expect((await first).isSuccess, isTrue);
    await interceptor.waitForRequests(4);
    expect(writeAt(3).settings[1]!.switch_1.switchOn, isFalse);
    expect(enabled(handle, 1), isFalse);
    requests[3].reply.complete(<int>[]);
    expect((await queued).isSuccess, isFalse);
    expect(enabled(handle, 1), isTrue);
    expect(requests, hasLength(4));

    requests[2].reply.complete(<int>[]);
    expect((await other).isSuccess, isFalse);
    await interceptor.waitForRequests(5);
    requests.last.reply.complete(response({1: firstSetting, 2: secondSetting}));
    await refresh;
    expect(enabled(handle, 1), isFalse);
    expect(enabled(handle, 2), isFalse);
  });

  test('离开页面后放弃排队写入', () async {
    final handle = await load();
    final first = handle.edit(1, const SetWhisperToggle(true));
    await interceptor.waitForRequests(2);
    final queued = handle.edit(1, const SetWhisperToggle(false));
    handle.dispose();
    requests[1].reply.complete(saved);
    expect((await first).isSuccess, isFalse);
    expect((await queued).isSuccess, isFalse);
    expect(requests, hasLength(2));
  });

  test('同名窗口选项按位置选择并保留其他协议信息', () async {
    final window = Setting(
      redirect: SettingRedirect(
        title: '消息推送时段',
        subtitle: '工作日',
        selectedSummary: '全天',
        windowSelect: redirectWindowSelect(
          title: '选择时段',
          item: [
            SelectItem(itemType: 1, text: '全天', selected: true),
            SelectItem(itemType: 2, text: '自定义'),
            SelectItem(itemType: 3, text: '自定义'),
          ],
        ),
      ),
    );
    window.unknownFields.mergeVarintField(99, Int64(42));
    final handle = await load(settings: {8: window});
    final operation = handle.edit(8, const SelectWhisperOption(2, '自定义'));
    await interceptor.waitForRequests(2);
    final written = writeAt(1).settings[8]!;
    expect(written.redirect.subtitle, '工作日');
    expect(written.redirect.windowSelect.title, '选择时段');
    expect(written.redirect.selectedSummary, '自定义');
    expect(
      written.redirect.windowSelect.item.map(
        (option) => (option.itemType, option.selected),
      ),
      [(1, false), (2, false), (3, true)],
    );
    expect(written.unknownFields, window.unknownFields);
    requests[1].reply.complete(saved);
    expect((await operation).isSuccess, isTrue);
  });

  test('子页确认值更新同会话的父页摘要', () async {
    final parent = await load(
      settings: {
        8: Setting(
          redirect: SettingRedirect(
            selectedSummary: '关闭',
            settingPage: redirect2SettingPage(
              subSettings: {1: firstSetting}.entries,
            ),
          ),
        ),
      },
    );
    final child = await load(sharedSession: parent.session);
    final other = await load();

    String? summary() =>
        (parent.state.value.loadingState.dataOrNull![8]!
                as WhisperSettingRedirect)
            .summary;

    final otherEdit = other.edit(2, const SetWhisperToggle(true));
    await interceptor.waitForRequests(4);
    requests.last.reply.complete(saved);
    parent.mergeChild(8, (await otherEdit).dataOrNull!);
    expect(summary(), '关闭');

    final childEdit = child.edit(1, const SetWhisperToggle(true));
    await interceptor.waitForRequests(5);
    expect(summary(), '关闭');
    requests.last.reply.complete(saved);
    parent.mergeChild(8, (await childEdit).dataOrNull!);
    expect(summary(), '通知');
  });
}
