import 'package:flutter_test/flutter_test.dart';
import 'package:pili_aurora_next/models/common/video/cdn_type.dart';
import 'package:pili_aurora_next/models/common/video/video_decode_type.dart';
import 'package:pili_aurora_next/services/diagnostics/diagnostics.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/codec.dart';
import 'package:pili_aurora_next/models/remote/live/live_room_play_info/url_info.dart';
import 'package:pili_aurora_next/utils/storage.dart';
import 'package:pili_aurora_next/utils/storage_key.dart';
import 'package:pili_aurora_next/utils/storage_pref.dart';
import 'package:pili_aurora_next/features/playback/application/media_source_selection.dart';

import '../support/memory_box.dart';

void main() {
  setUpAll(() {
    GStorage.setting = MemoryBox<dynamic>();
  });

  setUp(() => GStorage.setting.clear());

  test('单来源空输入始终明确失败，多来源仍交付空候选', () {
    for (final service in CDNService.values) {
      for (final empty in [
        <String>[],
        ['', '  '],
      ]) {
        expect(
          () =>
              MediaSourceSelection.getCdnUrl(empty, defaultCDNService: service),
          throwsA(
            isA<FormatException>().having(
              (error) => error.source,
              'source',
              isNull,
            ),
          ),
        );
        expect(
          MediaSourceSelection.getCdnUrls(empty, defaultCDNService: service),
          isEmpty,
        );
      }
    }
  });

  test('未知和相对来源保持原文，日志不包含地址或签名', () {
    const url =
        'https://unknown.example.test/private-path?private-signature=secret';
    expect(
      MediaSourceSelection.getCdnUrl([url], defaultCDNService: CDNService.hw),
      url,
    );
    final record = Diagnostics.instance.recentLogs.lastWhere(
      (record) => record['message'].toString().contains('未识别的 CDN'),
    );
    expect(record.toString(), isNot(contains('unknown.example.test')));
    expect(record.toString(), isNot(contains('private-path')));
    expect(record.toString(), isNot(contains('private-signature')));
    expect(record.toString(), isNot(contains('secret')));
    expect(
      MediaSourceSelection.getCdnUrl([
        '/relative-video?signature=x',
      ], defaultCDNService: CDNService.hw),
      '/relative-video?signature=x',
    );
  });

  test('来源解析错误提示不带输入，保留原始原因和堆栈', () {
    for (final url in [
      'https://[private.szbdyd.com/video?private-signature=secret',
      'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?os=%FF&private-signature=secret',
      'https://foo.szbdyd.com/video?xy_usource=%5Bprivate-signature',
    ]) {
      for (final select in <Object Function()>[
        () => MediaSourceSelection.getCdnUrl([
          url,
        ], defaultCDNService: CDNService.hw),
        () => MediaSourceSelection.getCdnUrls([
          url,
        ], defaultCDNService: CDNService.hw),
      ]) {
        expect(
          select,
          throwsA(
            isA<VideoSelectionException>()
                .having(
                  (error) => error.toString(),
                  'message',
                  isNot(contains('private-signature')),
                )
                .having((error) => error.source, 'source', isNull)
                .having((error) => error.cause, 'cause', isNotNull)
                .having(
                  (error) => error.stackTrace.toString(),
                  'stack',
                  isNotEmpty,
                ),
          ),
        );
      }
    }
  });

  test('编码保持偏好排序，无匹配时沿用首项，空或未知编码明确失败', () {
    expect(
      MediaSourceSelection.selectCodec(
        ['avc1.640028', 'hvc1.1'],
        [VideoDecodeFormatType.HEVC, VideoDecodeFormatType.AVC],
      ),
      VideoDecodeFormatType.HEVC,
    );
    expect(
      MediaSourceSelection.selectCodec(['avc1.640028', 'hvc1.1'], []),
      VideoDecodeFormatType.AVC,
    );
    expect(
      MediaSourceSelection.selectCodec(
        ['avc1.640028'],
        [VideoDecodeFormatType.AV1],
      ),
      VideoDecodeFormatType.AVC,
    );
    expect(
      () => MediaSourceSelection.selectCodec([], []),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MediaSourceSelection.selectCodec(['private-codec'], []),
      throwsA(
        isA<VideoSelectionException>().having(
          (error) => error.toString(),
          'message',
          isNot(contains('private-codec')),
        ),
      ),
    );
    expect(
      MediaSourceSelection.selectCodec(
        ['private-codec', 'avc1.640028'],
        [VideoDecodeFormatType.AVC],
      ),
      VideoDecodeFormatType.AVC,
    );
  });

  test('直播空来源明确失败，越界索引仍按首项回退', () {
    final item = CodecItem(
      currentQn: 1,
      acceptQn: [1],
      baseUrl: '/stream.flv',
      urlInfo: [],
    );
    expect(
      () => MediaSourceSelection.getLiveCdnUrl(item),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => MediaSourceSelection.getLiveCdnUrls(item),
      throwsA(isA<FormatException>()),
    );
    item.urlInfo.add(
      UrlInfo(host: 'https://a.example.test', extra: '?signature=x'),
    );
    for (final index in [-1, 1]) {
      expect(
        MediaSourceSelection.getLiveCdnUrl(item, index: index),
        'https://a.example.test/stream.flv?signature=x',
      );
    }
  });

  test('接口没有 Akamai 地址时不使用其它 CDN 的签名构造地址', () async {
    const original =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos';
    const backup =
        'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/video?sign=ali';
    expect(
      MediaSourceSelection.getCdnUrl(
        [original, backup],
        defaultCDNService: CDNService.akamai,
      ),
      original,
    );

    await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
    final urls = MediaSourceSelection.getCdnUrls(
      [original, backup],
      defaultCDNService: CDNService.cos,
    );
    expect(
      urls,
      isNot(
        contains(
          original.replaceFirst(
            'upos-sz-mirrorcos.bilivideo.com',
            'upos-hz-mirrorakam.akamaized.net',
          ),
        ),
      ),
    );
  });

  test('Akamai 来源只使用原始令牌，普通 CDN 从普通签名来源改写', () async {
    const akamai =
        'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/video?hdnts=A%2bb%2F&key=1&key=2';
    const cos =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos';
    final hw = cos.replaceFirst('mirrorcos', 'mirrorhw');
    for (final service in CDNService.values) {
      expect(
        MediaSourceSelection.getCdnUrl([akamai], defaultCDNService: service),
        akamai,
      );
    }
    expect(
      MediaSourceSelection.getCdnUrl([
        akamai,
        cos,
      ], defaultCDNService: CDNService.hw),
      hw,
    );
    expect(
      MediaSourceSelection.getCdnUrl([
        akamai,
        cos,
      ], defaultCDNService: CDNService.akamai),
      akamai,
    );
    await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
    await GStorage.setting.put(SettingBoxKey.cdnFallbackOrder, ['hw']);
    expect(
      MediaSourceSelection.getCdnUrls([
        akamai,
      ], defaultCDNService: CDNService.hw),
      [
        akamai,
      ],
    );
    expect(
      MediaSourceSelection.getCdnUrls([
        akamai,
        cos,
      ], defaultCDNService: CDNService.hw),
      [hw, akamai, cos],
    );
  });

  test('其它 CDN 保持首个镜像地址的改写优先级', () {
    const original =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos';
    const other =
        'https://foo.szbdyd.com/video?xy_usource=upos-sz-mirrorali.bilivideo.com';
    expect(
      MediaSourceSelection.getCdnUrl(
        [original, other],
        defaultCDNService: CDNService.hw,
      ),
      original.replaceFirst('mirrorcos', 'mirrorhw'),
    );
  });

  test('各镜像主机优先使用接口原文，签名和来源顺序均保留', () {
    const legacy = 'https://foo.szbdyd.com/video?xy_usource=legacy.example.com';
    for (final service in CDNService.values.where(
      (service) => service.host?.startsWith('upos-') == true,
    )) {
      final signed =
          'https://${service.host}/upgcxcode/video?sign=A%2bb%2F&key=1&key=2';
      expect(
        MediaSourceSelection.getCdnUrl([
          legacy,
          signed,
          signed.replaceFirst('sign=A', 'sign=other'),
        ], defaultCDNService: service),
        signed,
        reason: service.name,
      );
    }
    expect(
      MediaSourceSelection.getCdnUrl([
        legacy,
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos',
      ], defaultCDNService: CDNService.hw),
      'https://legacy.example.com/video?xy_usource=legacy.example.com',
    );
  });

  test('mcdn 回退优先使用最后一个 upgcxcode 来源，否则包装资源地址', () {
    const resource = 'https://a.mcdn.bilivideo.cn:4483/v1/resource?token=x';
    const upgcxcode =
        'https://cn-bcache.bilivideo.com/upgcxcode/video?sign=original';
    expect(
      MediaSourceSelection.getCdnUrl([
        resource,
        '$upgcxcode&old=1',
        upgcxcode,
      ], defaultCDNService: CDNService.hw),
      'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/video?sign=original',
    );
    final proxy = Uri.parse(
      MediaSourceSelection.getCdnUrl(
        [resource],
        defaultCDNService: CDNService.backupUrl,
      ),
    );
    expect(proxy.host, 'proxy-tf-all-ws.bilivideo.com');
    expect(proxy.queryParameters['url'], resource);
  });

  test('签名来源在首选和回退中保持原文、有序且不重复', () async {
    await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
    await GStorage.setting.put(SettingBoxKey.cdnFallbackOrder, ['hw']);
    const cos =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos';
    const ali =
        'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/video?sign=ali';
    const akamai =
        'https://upos-hz-mirrorakam.akamaized.net/upgcxcode/video?hdnts=A%2Bb';
    const hw =
        'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/video?sign=cos';
    for (final (service, expected) in [
      (CDNService.cos, [cos, hw, akamai, ali]),
      (CDNService.ali, [ali, hw, cos, akamai]),
      (CDNService.akamai, [akamai, hw, cos, ali]),
      (CDNService.hw, [hw, cos, akamai, ali]),
    ]) {
      const sources = [cos, akamai, ali, cos];
      expect(
        MediaSourceSelection.getCdnUrl(sources, defaultCDNService: service),
        expected.first,
        reason: service.name,
      );
      expect(
        MediaSourceSelection.getCdnUrls(sources, defaultCDNService: service),
        expected,
        reason: service.name,
      );
    }
  });

  test('直播备用源保留当前选择，按当前编码提供原始备用 host', () async {
    final codec = CodecItem(
      currentQn: 10000,
      acceptQn: [10000],
      baseUrl: '/stream.flv',
      urlInfo: [
        UrlInfo(host: 'https://a.example.com', extra: '?a=1'),
        UrlInfo(host: 'https://b.example.com', extra: '?b=2'),
      ],
    );
    expect(MediaSourceSelection.getLiveCdnUrls(codec, index: 1), [
      'https://b.example.com/stream.flv?b=2',
    ]);
    await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
    GStorage.setting.put(
      SettingBoxKey.liveCdnUrl,
      'https://custom.example.com',
    );
    expect(MediaSourceSelection.getLiveCdnUrls(codec, index: 1), [
      'https://custom.example.com/stream.flv?b=2',
      'https://a.example.com/stream.flv?a=1',
      'https://b.example.com/stream.flv?b=2',
    ]);
  });

  test(
    'default fallback uses CDN list order after the preferred source',
    () async {
      await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
      const primary =
          'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?deadline=1';
      const backup =
          'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/video?deadline=1';

      final urls = MediaSourceSelection.getCdnUrls(
        [primary, backup, primary],
        defaultCDNService: CDNService.hw,
      );

      expect(urls.take(5), [
        'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/video?deadline=1',
        primary,
        backup,
        'https://upos-sz-mirroralib.bilivideo.com/upgcxcode/video?deadline=1',
        'https://upos-sz-mirroralio1.bilivideo.com/upgcxcode/video?deadline=1',
      ]);
      expect(urls.toSet().length, urls.length);
    },
  );

  test(
    'custom fallback order persists and deduplicates the preferred CDN',
    () async {
      await GStorage.setting.put(SettingBoxKey.enableMultiCdn, true);
      await GStorage.setting.put(
        SettingBoxKey.cdnFallbackOrder,
        ['hw', 'ali', 'removed-cdn', 'hw', 'cos'],
      );
      expect(Pref.cdnFallbackOrder, [
        CDNService.hw,
        CDNService.ali,
        CDNService.cos,
      ]);
      const primary =
          'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?deadline=1';
      const backup = 'https://backup.example.com/video?deadline=1';
      expect(
        MediaSourceSelection.getCdnUrls([
          primary,
          backup,
        ], defaultCDNService: CDNService.ali),
        [
          'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/video?deadline=1',
          'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/video?deadline=1',
          primary,
          backup,
        ],
      );

      await GStorage.setting.put(SettingBoxKey.enableMultiCdn, false);
      expect(
        MediaSourceSelection.getCdnUrls([
          primary,
          backup,
        ], defaultCDNService: CDNService.ali),
        [
          'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/video?deadline=1',
        ],
      );
    },
  );

  test('默认单源，启用和关闭回退只改变候选列表，空来源没有候选', () async {
    const cos =
        'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/video?sign=cos';
    const hw =
        'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/video?sign=cos';
    await GStorage.setting.put(SettingBoxKey.cdnFallbackOrder, ['hw']);
    for (final enabled in [null, true, false]) {
      if (enabled != null) {
        await GStorage.setting.put(SettingBoxKey.enableMultiCdn, enabled);
      }
      expect(
        MediaSourceSelection.getCdnUrls([
          cos,
        ], defaultCDNService: CDNService.cos),
        enabled == true ? [cos, hw] : [cos],
        reason: 'enableMultiCdn=$enabled',
      );
      for (final empty in [
        <String>[],
        ['', ''],
      ]) {
        expect(MediaSourceSelection.getCdnUrls(empty), isEmpty);
      }
    }
  });

  for (final multiCdn in [false, true]) {
    test('音频 CDN 开关在多源=$multiCdn 时保留首选与原始备用', () async {
      await GStorage.setting.put(SettingBoxKey.enableMultiCdn, multiCdn);
      await GStorage.setting.put(SettingBoxKey.cdnFallbackOrder, ['hw']);
      const cos =
          'https://upos-sz-mirrorcos.bilivideo.com/upgcxcode/audio?deadline=1';
      const ali =
          'https://upos-sz-mirrorali.bilivideo.com/upgcxcode/audio?deadline=1';
      const hw =
          'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/audio?deadline=1';
      for (final disabled in [false, true]) {
        GStorage.setting.put(SettingBoxKey.disableAudioCDN, disabled);
        expect(
          MediaSourceSelection.getCdnUrls(
            [cos, ali],
            defaultCDNService: CDNService.ali,
            isAudio: true,
          ),
          disabled
              ? (multiCdn ? [cos, ali] : [cos])
              : (multiCdn ? [ali, hw, cos] : [ali]),
          reason: 'disableAudioCDN=$disabled',
        );
      }
    });
  }
}
