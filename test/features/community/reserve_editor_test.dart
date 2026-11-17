import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/application/reserve_editor.dart';
import 'package:pili_aurora_next/features/community/data/reserve_repository.dart';
import 'package:pili_aurora_next/features/community/domain/reserve.dart';
import 'package:pili_aurora_next/features/community/domain/reserve_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/models/common/account_type.dart';
import 'package:pili_aurora_next/pages/dynamics_create_reserve/view.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

class _Repository extends ReserveRepository {
  final loads = <Completer<LoadingState<ReserveDraft>>>[];
  final saves = <Completer<LoadingState<ReserveInfoData>>>[];
  final submitted = <({Account account, int? id, ReserveDraft draft})>[];
  @override
  Future<LoadingState<ReserveDraft>> load(Account account, int id) {
    final pending = Completer<LoadingState<ReserveDraft>>();
    loads.add(pending);
    return pending.future;
  }

  @override
  Future<LoadingState<ReserveInfoData>> save(
    Account account,
    int? id,
    ReserveDraft draft,
  ) {
    submitted.add((account: account, id: id, draft: draft));
    final pending = Completer<LoadingState<ReserveInfoData>>();
    saves.add(pending);
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LoginAccount account(String token) => LoginAccount(
    BiliCookieJar.fromJson({'DedeUserID': '1', 'bili_jct': token}),
    null,
    null,
  );
  late _Repository repository;
  late ProviderContainer container;
  setUpAll(() {
    GStorage.setting = MemoryBox();
    GStorage.localCache = MemoryBox();
  });
  setUp(() {
    Accounts.accountMode[AccountType.main.index] = account('original');
    repository = _Repository();
    container = ProviderContainer(
      overrides: [reserveRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => container.dispose());

  NotifierProvider<ReserveEditor, DraftEditorState<ReserveDraft>>
  reserveProvider({
    int? id,
  }) {
    final provider = reserveEditorProvider((owner: Object(), id: id));
    container.listen(provider, (_, _) {});
    return provider;
  }

  test('新预约默认次日二十点，标题和过去时间验证不依赖界面', () async {
    final provider = reserveProvider();
    final editor = container.read(provider.notifier);
    final expected = editor.now;
    expect(
      container.read(provider).draft.date,
      DateTime(expected.year, expected.month, expected.day + 1, 20),
    );
    expect(await editor.onCreate(), isA<Error>());
    editor.update((draft) => draft.copy(title: '超出十四个字符长度限制的预约标题'));
    expect(await editor.onCreate(), isA<Error>());
    editor.update((draft) => draft.copy(title: '预约', date: expected));
    expect(await editor.onCreate(), isA<Error>());
    expect(repository.saves, isEmpty);
  });

  test('保存固定标题类型时间，采用成功 ID 后更新，失败保留新草稿', () async {
    final provider = reserveProvider();
    final editor = container.read(provider.notifier)
      ..update((draft) => draft.copy(title: '原预约', subType: 1));
    final original = container.read(provider).draft;
    final pending = editor.onCreate();
    expect(await editor.onCreate(), isA<Error>());
    editor.update(
      (draft) => draft.copy(
        title: '新预约',
        subType: 0,
        date: draft.date.add(const Duration(days: 1)),
      ),
    );
    expect(repository.submitted.single.draft, same(original));
    expect(repository.submitted.single.account, same(Accounts.main));
    repository.saves.single.complete(Success(ReserveInfoData(id: 7)));
    await pending;
    final retry = editor.onCreate();
    expect(repository.submitted.last.id, 7);
    expect(repository.submitted.last.draft.title, '新预约');
    repository.saves.last.complete(const Error('保存失败'));
    expect(await retry, isA<Error>());
    expect(container.read(provider).saving, isFalse);
    expect(container.read(provider).draft.title, '新预约');
  });

  test('详情加载期间改稿后保留本地内容，失败可重试', () async {
    final provider = reserveProvider(id: 7);
    final editor = container.read(provider.notifier);
    await Future<void>.delayed(Duration.zero);
    editor.update((draft) => draft.copy(title: '本地预约'));
    repository.loads.single.complete(
      Success(container.read(provider).draft.copy(title: '远端预约')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).draft.title, '本地预约');
    expect(editor.canCreate, isFalse);
    final retry = editor.queryData();
    repository.loads.last.complete(const Error('加载失败'));
    await retry;
    expect(container.read(provider).draft.title, '本地预约');
    expect(container.read(provider).error?.errMsg, '加载失败');
    final confirmed = editor.queryData();
    repository.loads.last.complete(
      Success(container.read(provider).draft.copy(title: '核对预约')),
    );
    await confirmed;
    expect(editor.canCreate, isTrue);
  });

  test('同 UID 换凭据废弃在途保存，独立编辑器与迟到详情不串页', () async {
    final first = reserveProvider();
    final second = reserveProvider(id: 8);
    final editor = container.read(first.notifier)
      ..update((draft) => draft.copy(title: '第一页'));
    final pending = editor.onCreate();
    await Future<void>.delayed(Duration.zero);
    Accounts.replaceCredentials(account('replacement'));
    repository.saves.single.complete(Success(ReserveInfoData(id: 7)));
    repository.loads.single.complete(
      Success(container.read(second).draft.copy(title: '旧账号详情')),
    );
    expect(await pending, isA<Error>());
    await Future<void>.delayed(Duration.zero);
    expect(container.read(first).draft.title, '第一页');
    expect(container.read(second).draft.title, isEmpty);
    expect(container.read(first).saving, isFalse);
    expect(container.read(second).loading, isFalse);
    expect(await editor.onCreate(), isA<Error>());
  });

  testWidgets('页面参数替换时旧保存不关闭新预约，详情同步输入后释放', (tester) async {
    int? id;
    late StateSetter rebuild;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reserveRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CreateReservePage(sid: id);
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), '本地预约');
    await tester.pump();
    final saveButton = find.widgetWithText(FilledButton, '添加预约');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(repository.saves, hasLength(1));
    rebuild(() => id = 7);
    await tester.pump();
    repository.saves.single.complete(Success(ReserveInfoData(id: 5)));
    await tester.pump();
    expect(find.byType(CreateReservePage), findsOneWidget);
    repository.loads.single.complete(
      Success(
        ReserveDraft(
          title: '新预约详情',
          date: DateTime.now().add(const Duration(days: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新预约详情'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
