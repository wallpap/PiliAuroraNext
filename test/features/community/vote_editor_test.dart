import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/application/account_draft_editor.dart';
import 'package:pili_aurora_next/features/community/application/vote_editor.dart';
import 'package:pili_aurora_next/features/community/data/vote_repository.dart';
import 'package:pili_aurora_next/features/community/domain/vote.dart';
import 'package:pili_aurora_next/features/community/domain/vote_draft.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/account/domain/account_type.dart';
import 'package:pili_aurora_next/pages/dynamics_create_vote/view.dart';
import 'package:pili_aurora_next/features/account/application/accounts.dart';
import 'package:pili_aurora_next/features/account/application/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../support/memory_box.dart';

class _Repository extends VoteRepository {
  final loads = <Completer<LoadingState<VoteDraft>>>[];
  final uploads = <Completer<LoadingState<String?>>>[];
  final saves = <Completer<LoadingState<VoteInfo>>>[];
  final submitted = <({Account account, int? id, VoteDraft draft})>[];
  @override
  Future<LoadingState<VoteDraft>> load(Account account, int id) {
    final pending = Completer<LoadingState<VoteDraft>>();
    loads.add(pending);
    return pending.future;
  }

  @override
  Future<LoadingState<String?>> upload(Account account, String path) {
    final pending = Completer<LoadingState<String?>>();
    uploads.add(pending);
    return pending.future;
  }

  @override
  Future<LoadingState<VoteInfo>> save(
    Account account,
    int? id,
    VoteDraft draft,
  ) {
    submitted.add((account: account, id: id, draft: draft));
    final pending = Completer<LoadingState<VoteInfo>>();
    saves.add(pending);
    return pending.future;
  }
}

VoteDraft _draft(String title) => VoteDraft(
  title: title,
  deadline: DateTime.now().add(const Duration(days: 1)),
  options: [
    VoteOptionDraft(text: '甲'),
    VoteOptionDraft(text: '乙'),
  ],
);

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
      overrides: [voteRepositoryProvider.overrideWithValue(repository)],
    );
  });
  tearDown(() => container.dispose());

  NotifierProvider<VoteEditor, DraftEditorState<VoteDraft>> voteProvider({
    int? id,
  }) {
    final provider = voteEditorProvider((owner: Object(), id: id));
    container.listen(provider, (_, _) {});
    return provider;
  }

  test('详情乱序与加载期间的新草稿受保护，刷新成功才重新允许保存', () async {
    final provider = voteProvider(id: 7);
    final editor = container.read(provider.notifier);
    await Future<void>.delayed(Duration.zero);
    final newer = editor.queryData();
    repository.loads[1].complete(Success(_draft('新详情')));
    await newer;
    repository.loads[0].complete(Success(_draft('旧详情')));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(provider).draft.title, '新详情');
    final pending = editor.queryData();
    editor.update((draft) => draft.copy(title: '本地草稿'));
    repository.loads[2].complete(Success(_draft('迟到详情')));
    await pending;
    expect(container.read(provider).draft.title, '本地草稿');
    expect(editor.canCreate, isFalse);
    final retry = editor.queryData();
    repository.loads[3].complete(Success(_draft('核对详情')));
    await retry;
    expect(editor.canCreate, isTrue);
  });

  test('保存固定账号与草稿，成功采用远端 ID，失败保留编辑内容', () async {
    final provider = voteProvider();
    final editor = container.read(provider.notifier)
      ..update((_) => _draft('原草稿'));
    final original = Accounts.main;
    final pending = editor.onCreate();
    expect(await editor.onCreate(), isA<Error>());
    editor.update((draft) => draft.copy(title: '新草稿'));
    expect(repository.submitted.single.account, same(original));
    expect(repository.submitted.single.draft.title, '原草稿');
    repository.saves[0].complete(Success(VoteInfo(voteId: 7)));
    await pending;
    final retry = editor.onCreate();
    expect(repository.submitted.last.id, 7);
    expect(repository.submitted.last.draft.title, '新草稿');
    repository.saves[1].complete(const Error('保存失败'));
    expect(await retry, isA<Error>());
    expect(container.read(provider).saving, isFalse);
    expect(container.read(provider).draft.title, '新草稿');
  });

  test('上传只接受同一选项的最新结果，删除选项后不回写', () async {
    final provider = voteProvider();
    final editor = container.read(provider.notifier)..addOption();
    final id = container.read(provider).draft.options.last.id;
    final first = editor.onUpload(id, 'first');
    final second = editor.onUpload(id, 'second');
    repository.uploads[1].complete(const Success('new'));
    expect(await second, isA<Success<void>>());
    repository.uploads[0].complete(const Success('old'));
    expect(await first, isA<Error>());
    expect(container.read(provider).draft.options.last.image, 'new');
    final removed = editor.onUpload(id, 'removed');
    editor.onDel(2);
    repository.uploads[2].complete(const Success('removed'));
    expect(await removed, isA<Error>());
    expect(container.read(provider).draft.options, hasLength(2));
  });

  test('同 UID 凭据替换立即停止编辑，拒绝在途保存和上传结果', () async {
    final provider = voteProvider();
    final editor = container.read(provider.notifier)
      ..update((_) => _draft('保留草稿'));
    final saving = editor.onCreate();
    final uploading = editor.onUpload(
      container.read(provider).draft.options.first.id,
      'path',
    );
    Accounts.replaceCredentials(account('replacement'));
    expect(container.read(provider).active, isFalse);
    expect(container.read(provider).saving, isFalse);
    repository.saves.single.complete(Success(VoteInfo(voteId: 9)));
    repository.uploads.single.complete(const Success('stale'));
    expect(await saving, isA<Error>());
    expect(await uploading, isA<Error>());
    editor.update((draft) => draft.copy(title: '不应写入'));
    expect(container.read(provider).draft.title, '保留草稿');
    expect(await editor.onCreate(), isA<Error>());
    expect(repository.saves, hasLength(1));
  });

  test('不同页面独立草稿，释放页面拒绝迟到保存', () async {
    final first = voteProvider();
    final second = voteProvider();
    final editor = container.read(first.notifier)..update((_) => _draft('第一页'));
    expect(container.read(second).draft.title, isEmpty);
    final pending = editor.onCreate();
    container.dispose();
    repository.saves.single.complete(Success(VoteInfo(voteId: 7)));
    expect(await pending, isA<Error>());
    expect(editor.isCurrent, isFalse);
  });

  testWidgets('详情快照更新输入，输入后重建保留光标与内容', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [voteRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: CreateVotePage(voteId: 7)),
      ),
    );
    await tester.pump();
    repository.loads.single.complete(Success(_draft('远端标题')));
    await tester.pumpAndSettle();
    final title = find.byType(TextFormField).first;
    expect(find.text('远端标题'), findsOneWidget);
    await tester.enterText(title, '本地标题');
    await tester.pump();
    expect(find.text('本地标题'), findsOneWidget);
    final input = tester.widget<EditableText>(
      find.descendant(of: title, matching: find.byType(EditableText)),
    );
    expect(input.controller.selection.baseOffset, 4);
    await tester.pumpWidget(const SizedBox());
  });
}
