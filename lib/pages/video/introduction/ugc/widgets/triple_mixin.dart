import 'dart:async';

import 'package:pili_aurora_next/pages/video/pay_coins/view.dart';
import 'package:pili_aurora_next/features/account/application/coin_balance.dart';
import 'package:pili_aurora_next/platform/platform_info.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

mixin TripleMixin {
  TickerProvider get tripleVsync;
  // 是否点赞
  final hasLike = ValueNotifier(false);
  // 投币数量
  final coinNum = ValueNotifier<num>(0);
  // 是否投币
  bool get hasCoin => coinNum.value != 0;
  // 是否收藏
  final hasFav = ValueNotifier(false);

  bool get hasTriple => hasLike.value && hasCoin && hasFav.value;

  bool get isLogin;

  bool isHasCopyright(int copyright) {
    return copyright != 2;
  }

  bool reachCoinLimit(bool hasCopyRight, num coinNum) {
    return (!hasCopyRight && coinNum >= 1) || coinNum >= 2;
  }

  int get copyright;

  FutureOr<void> onPayCoin(int coin, bool coinWithLike);

  OnPayCoin get payCoinCallback => onPayCoin;

  void actionCoinVideo() {
    if (!isLogin) {
      SmartDialog.showToast('账号未登录');
      return;
    }

    final coinNum = this.coinNum.value;
    final copyright = this.copyright;
    final hasCopyright = isHasCopyright(copyright);
    if (reachCoinLimit(hasCopyright, coinNum)) {
      SmartDialog.showToast('达到投币上限啦~');
      return;
    }

    final availableCoins = CoinBalance.instance.amount;
    if (availableCoins != null && availableCoins < 1) {
      SmartDialog.showToast('硬币不足');
    }

    PayCoinsPage.toPayCoinsPage(
      onPayCoin: payCoinCallback,
      hasCoin: coinNum == 1,
      hasCopyright: hasCopyright,
      availableCoins: availableCoins,
    );
  }

  void actionTriple();
  void actionLikeVideo();

  // no need for pugv
  AnimationController? _tripleAnimCtr;
  Animation<double>? _tripleAnimation;

  AnimationController get tripleAnimCtr =>
      _tripleAnimCtr ??= AnimationController(
        vsync: tripleVsync,
        duration: const Duration(milliseconds: 1200),
        reverseDuration: const Duration(milliseconds: 400),
      );

  Animation<double> get tripleAnimation => _tripleAnimation ??= tripleAnimCtr
      .drive(CurveTween(curve: Curves.easeInOut));

  Timer? _timer;

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  bool get isTripling => _tripleAnimCtr?.status == .forward;

  static final _duration = PlatformUtils.isMobile
      ? const Duration(milliseconds: 200)
      : const Duration(milliseconds: 255);

  void onStartTriple() {
    _timer ??= Timer(_duration, () {
      HapticFeedback.lightImpact();
      if (hasTriple) {
        SmartDialog.showToast('已完成三连');
      } else {
        tripleAnimCtr.forward().whenComplete(() {
          tripleAnimCtr.reset();
          actionTriple();
        });
      }
      _cancelTimer();
    });
  }

  void onCancelTriple([bool isTapUp = false]) {
    if (tripleAnimCtr.status == .forward) {
      tripleAnimCtr.reverse();
    } else if (_timer != null && _timer!.tick == 0) {
      _cancelTimer();
      if (isTapUp) {
        actionLikeVideo();
      }
    }
  }

  void disposeTriple() {
    _cancelTimer();
    _tripleAnimCtr?.dispose();
    hasLike.dispose();
    coinNum.dispose();
    hasFav.dispose();
  }
}
