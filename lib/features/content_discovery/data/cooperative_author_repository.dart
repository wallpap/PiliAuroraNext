import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/http/video.dart';
import 'package:pili_aurora_next/utils/accounts.dart';
import 'package:pili_aurora_next/utils/parse_int.dart';

class CooperativeAuthorRepository {
  const CooperativeAuthorRepository();

  Future<Set<int>?> load(String bvid) async {
    final result = await VideoHttp.videoIntro(
      bvid: bvid,
      account: Accounts.main,
    );
    if (result case Success(:final response)) {
      final staff = response.staff;
      if (staff == null || staff.isEmpty) return null;
      final mids = <int>{
        ?response.owner?.mid,
        ...staff.map((author) => safeToInt(author.mid)).whereType<int>(),
      }..removeWhere((mid) => mid <= 0);
      return mids.isEmpty ? null : mids;
    }
    return null;
  }
}
