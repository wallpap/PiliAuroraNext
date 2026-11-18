import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pili_aurora_next/models/common/member/archive_sort_type_app.dart';
import 'package:pili_aurora_next/models/common/member/web_ss_type.dart';
import 'package:pili_aurora_next/pages/member_video_web/base/view.dart';
import 'package:get/get.dart';

class MemberSSWeb extends ConsumerStatefulWidget {
  const MemberSSWeb({super.key});

  @override
  ConsumerState<MemberSSWeb> createState() => _MemberSSWebState();

  static Future<void>? toMemberSSWeb({
    required WebSsType type,
    required Object id,
    required Object mid,
    required String name,
  }) {
    return Get.toNamed(
      '/ssWeb',
      arguments: {
        'type': type,
        'id': id,
        'mid': mid,
        'name': name,
      },
    );
  }
}

class _MemberSSWebState
    extends BaseVideoWebState<MemberSSWeb, ArchiveSortTypeApp> {
  @override
  ArchiveSortTypeApp get selectedOrder => controller.sort;

  @override
  List<ArchiveSortTypeApp> get values => ArchiveSortTypeApp.values;
}
