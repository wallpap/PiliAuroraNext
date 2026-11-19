import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:pili_aurora_next/features/danmaku/data/danmaku_protobuf.dart';
import 'package:pili_aurora_next/features/danmaku/domain/danmaku_element.dart';
import 'package:pili_aurora_next/generated/bilibili/community/service/dm/v1.pb.dart';
import 'package:pili_aurora_next/grpc/grpc_req.dart';
import 'package:pili_aurora_next/grpc/url.dart';
import 'package:pili_aurora_next/http/loading_state.dart';
import 'package:pili_aurora_next/features/danmaku/application/work_quota.dart';

typedef _Segment = ({List<DanmakuElement> elements, bool sendingDisabled});

_Segment _decodeSegment(Uint8List bytes) {
  final reply = DmSegMobileReply.fromBuffer(bytes);
  return (
    elements: reply.elems.map(projectDanmakuElement).toList(growable: false),
    sendingDisabled: reply.state == 1,
  );
}

/// 播放投影在预留两份存储的解析阶段完成，消费方仅接收领域值并共用原租约。
Future<bool> loadDanmakuSegment({
  required int cid,
  required int segmentIndex,
  required DanmakuWorkToken workToken,
  required Future<void> Function(
    List<DanmakuElement> elements,
    bool sendingDisabled,
    DanmakuWorkLease lease,
  )
  consume,
}) async {
  final response = await _requestSegment(
    cid: cid,
    segmentIndex: segmentIndex + 1,
    type: 1,
    parse: _decodeSegment,
    workToken: workToken,
    consume: (segment, lease) =>
        consume(segment.elements, segment.sendingDisabled, lease),
  );
  return response.isSuccess;
}

Future<LoadingState<DmSegMobileReply>> requestRawDanmakuSegment({
  required int cid,
  required int segmentIndex,
  required int type,
  DanmakuWorkToken? workToken,
  Future<void> Function(DmSegMobileReply, DanmakuWorkLease)? consume,
}) => _requestSegment(
  cid: cid,
  segmentIndex: segmentIndex,
  type: type,
  parse: DmSegMobileReply.fromBuffer,
  workToken: workToken,
  consume: consume,
);

Future<LoadingState<T>> _requestSegment<T>({
  required int cid,
  required int segmentIndex,
  required int type,
  required T Function(Uint8List) parse,
  DanmakuWorkToken? workToken,
  Future<void> Function(T, DanmakuWorkLease)? consume,
}) => GrpcReq.request(
  GrpcUrl.dmSegMobile,
  DmSegMobileReq(
    oid: Int64(cid),
    segmentIndex: Int64(segmentIndex),
    type: type,
  ),
  parse,
  kind: .query,
  isolate: true,
  danmakuWork: true,
  inspectDecoded: inspectDanmakuProtobuf,
  workToken: workToken,
  consume: consume,
);
