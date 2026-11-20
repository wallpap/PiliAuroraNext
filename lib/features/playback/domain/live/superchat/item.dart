import 'package:pili_aurora_next/features/playback/domain/live/medals/uinfo_medal.dart';
import 'package:pili_aurora_next/features/playback/domain/live/superchat/user_info.dart';
import 'package:pili_aurora_next/features/playback/domain/live/medals/guard_pendant.dart';
import 'package:pili_aurora_next/core/parsing/parse_int.dart';
import 'package:pili_aurora_next/core/parsing/parse_string.dart';
import 'package:pili_aurora_next/core/random/random_text.dart';

class SuperChatItem {
  int id;
  int uid;
  int price;
  String? backgroundImage;
  String backgroundColor;
  String backgroundBottomColor;
  String backgroundPriceColor;
  String messageFontColor;
  int startSime;
  int endTime;
  String message;
  String token;
  int ts;
  UserInfo userInfo;
  late bool expired = false;
  late bool deleted = false;
  UinfoMedal? medalInfo;
  int roomid;

  SuperChatItem({
    required this.id,
    required this.uid,
    required this.price,
    this.backgroundImage,
    required this.backgroundColor,
    required this.backgroundBottomColor,
    required this.backgroundPriceColor,
    required this.messageFontColor,
    required this.startSime,
    required this.endTime,
    required this.message,
    required this.token,
    required this.ts,
    required this.userInfo,
    this.medalInfo,
    required this.roomid,
  });

  static SuperChatItem random({required bool showFanMedals}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return SuperChatItem.fromJson(
      {
        "id": sharedRandom.nextInt(2147483647),
        "uid": 0,
        "price": 66,
        "start_time": now,
        "end_time": now + 5,
        "message": generateRandomString(55),
        "user_info": {
          "face": "",
          'face_frame': liveGuardPendant(sharedRandom.nextInt(4)),
          "uname": "UNAME",
        },
        'token': '',
        'ts': now,
        'uinfo': {
          'medal': {
            "name": "Medal",
            "level": sharedRandom.nextInt(40),
            "id": 123,
            "ruid": 456,
            "v2_medal_color_start": "#4C7DFF99",
            "v2_medal_color_text": "#FFFFFF",
          },
        },
      },
      sharedRandom.nextInt(2147483647),
      showFanMedals: showFanMedals,
    );
  }

  factory SuperChatItem.fromJson(
    Map<String, dynamic> json,
    int roomid, {
    required bool showFanMedals,
  }) =>
      SuperChatItem(
        id: safeToInt(json['id']) ?? sharedRandom.nextInt(2147483647),
        uid: safeToInt(json['uid'])!,
        price: json['price'],
        backgroundImage: nonNullOrEmptyString(json['background_image']),
        backgroundColor: json['background_color'] ?? '#EDF5FF',
        backgroundBottomColor: json['background_bottom_color'] ?? '#2A60B2',
        backgroundPriceColor: json['background_price_color'] ?? '#7497CD',
        messageFontColor: json['message_font_color'] ?? '#FFFFFF',
        startSime: safeToInt(json['start_time'])!,
        endTime: safeToInt(json['end_time'])!,
        message: json['message'],
        token: json['token'],
        ts: safeToInt(json['ts'])!,
        userInfo: UserInfo.fromJson(json['user_info'] as Map<String, dynamic>),
        medalInfo:
            !showFanMedals || json['uinfo']?['medal'] == null
            ? null
            : UinfoMedal.fromJson(json['uinfo']['medal']),
        roomid: roomid,
      );

  SuperChatItem copyWith({
    int? id,
    int? uid,
    int? price,
    String? backgroundColor,
    String? backgroundBottomColor,
    String? backgroundPriceColor,
    String? messageFontColor,
    int? startSime,
    int? endTime,
    String? message,
    String? token,
    int? ts,
    UserInfo? userInfo,
    bool? expired,
    UinfoMedal? medalInfo,
  }) {
    return SuperChatItem(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      price: price ?? this.price,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundBottomColor:
          backgroundBottomColor ?? this.backgroundBottomColor,
      backgroundPriceColor: backgroundPriceColor ?? this.backgroundPriceColor,
      messageFontColor: messageFontColor ?? this.messageFontColor,
      startSime: startSime ?? this.startSime,
      endTime: endTime ?? this.endTime,
      message: message ?? this.message,
      token: token ?? this.token,
      ts: ts ?? this.ts,
      userInfo: userInfo ?? this.userInfo,
      medalInfo: medalInfo ?? this.medalInfo,
      roomid: roomid,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'uid': uid,
    'price': price,
    'background_image': backgroundImage,
    'background_color': backgroundColor,
    'background_bottom_color': backgroundBottomColor,
    'background_price_color': backgroundPriceColor,
    'message_font_color': messageFontColor,
    'start_time': startSime,
    'end_time': endTime,
    'message': message,
    'token': token,
    'ts': ts,
    'user_info': userInfo.toJson(),
    'medal': ?medalInfo?.toJson(),
    'roomid': roomid,
  };
}
