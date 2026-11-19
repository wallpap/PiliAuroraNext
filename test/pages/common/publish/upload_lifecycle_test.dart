import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pili_aurora_next/features/community/data/dynamic_picture_upload.dart';
import 'package:pili_aurora_next/models/dynamics/result.dart' show FilePicModel;
import 'package:pili_aurora_next/pages/common/publish/common_rich_text_pub_page.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/accounts/account.dart';
import 'package:pili_aurora_next/utils/storage.dart';

import '../../../support/memory_box.dart';

class _Composer extends CommonRichTextPubPage {
  const _Composer({super.key}) : super(autofocus: false);
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends CommonRichTextPubPageState<_Composer> {
  final upload = Completer<Map<String, dynamic>>();
  DynamicPictureUpload? token;
  Account? uploadAccount;
  int submissions = 0;
  @override
  Future<Map<String, dynamic>> uploadPicture(
    FilePicModel image,
    DynamicPictureUpload cancelToken, {
    required Account account,
  }) {
    token = cancelToken;
    uploadAccount = account;
    return upload.future;
  }

  @override
  Future<void> onCustomPublish({List? pictures}) async {
    submissions++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
    GStorage.localCache = MemoryBox<dynamic>();
  });
  testWidgets('关闭编辑器取消上传并阻止后续发布', (tester) async {
    final key = GlobalKey<_ComposerState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: FlutterSmartDialog.init(),
        home: _Composer(key: key),
      ),
    );
    final state = key.currentState!
      ..addDraftImage(FilePicModel(path: 'synthetic'));
    final operation = state.onPublish();
    await tester.pump();
    expect(state.token, isNotNull);
    expect(state.uploadAccount, same(Accounts.main));
    await tester.pumpWidget(const SizedBox());
    expect(state.token!.isCancelled, isTrue);
    state.upload.complete({'img_src': 'synthetic'});
    await tester.pumpAndSettle();
    await operation;
    expect(state.submissions, 0);
  });
}
