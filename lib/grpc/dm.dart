import 'package:pili_aurora_next/features/danmaku/data/danmaku_segments.dart';
import 'package:pili_aurora_next/generated/bilibili/community/service/dm/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/grpc/url.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/danmaku/application/work_quota.dart';

abstract final class DmGrpc {
  static Future<LoadingState<DmSegMobileReply>> dmSegMobile({
    required int cid,
    required int segmentIndex,
    int type = 1,
    DanmakuWorkToken? workToken,
    Future<void> Function(DmSegMobileReply, DanmakuWorkLease)? consume,
  }) {
    return requestRawDanmakuSegment(
      cid: cid,
      segmentIndex: segmentIndex,
      type: type,
      workToken: workToken,
      consume: consume,
    );
  }

  static Future<LoadingState<DmViewReply>> dmView(int aid, int cid) {
    return GrpcReq.request(
      GrpcUrl.dmView,
      DmViewReq(pid: Int64(aid), oid: Int64(cid), type: 1),
      DmViewReply.fromBuffer,
      kind: .query,
    );
  }
}
