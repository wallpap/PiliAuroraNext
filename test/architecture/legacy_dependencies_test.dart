import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'dart_source.dart';

const _getxTypes = {
  'FullLifeCycleController',
  'GetLifeCycleBase',
  'GetLifeCycleMixin',
  'GetxController',
  'GetxService',
  'GetxServiceMixin',
  'RxController',
  'SuperController',
  'GetTickerProviderStateMixin',
  'GetSingleTickerProviderStateMixin',
};

const _getxRegistryCalls = {
  'Get.create',
  'Get.delete',
  'Get.find',
  'Get.isRegistered',
  'Get.lazyPut',
  'Get.put',
  'Get.putAsync',
  'Get.putOrFind',
  'Get.replace',
  'GetInstance.create',
  'GetInstance.delete',
  'GetInstance.find',
  'GetInstance.lazyPut',
  'GetInstance.put',
  'GetInstance.putAsync',
  'GetInstance.putOrFind',
  'GetInstance.replace',
};

const _legacyUtilities = {
  'features/account/application/accounts.dart',
  'features/account/application/login_sync.dart',
  'utils/accounts.dart',
  'utils/app_sign.dart',
  'utils/credential_cipher.dart',
  'utils/global_data.dart',
  'utils/login_utils.dart',
  'utils/media_author_filter.dart',
  'utils/recommend_filter.dart',
  'utils/reply_filter.dart',
  'utils/reply_utils.dart',
  'utils/request_utils.dart',
  'utils/storage.dart',
  'utils/storage_pref.dart',
  'utils/storage_utils.dart',
  'utils/video_utils.dart',
  'utils/wbi_sign.dart',
};

bool _isPresentation(String source) =>
    source.startsWith('pages/') ||
    source.startsWith('common/widgets/') ||
    (source.startsWith('features/') && source.contains('/presentation/'));

bool _isRestricted(String target) =>
    (target.startsWith('http/') && target != 'http/loading_state.dart') ||
    target.startsWith('grpc/') ||
    target.startsWith('generated/') ||
    target.startsWith('features/account/data/') ||
    _legacyUtilities.contains(target) ||
    target.startsWith('package:dlna_dart/') ||
    target.startsWith('package:dio/') ||
    target.startsWith('package:grpc/') ||
    target.startsWith('package:hive_ce/') ||
    target.startsWith('package:shared_preferences/');

bool _isTransport(String target) =>
    (target.startsWith('http/') && target != 'http/loading_state.dart') ||
    target.startsWith('grpc/') ||
    target.startsWith('package:dio/') ||
    target.startsWith('package:grpc/');

void main() {
  test(
    'presentation has no transport, storage or GetX business dependencies',
    () {
      final registry = jsonDecode(
        File('third_party/dependencies.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final vendoredImplementations = <String>[
        for (final entry in registry['packages'] as List<dynamic>)
          'package:${entry['name']}/src/',
        '../third_party/',
      ];
      final baseTypes = <String, Set<String>>{};
      final violations = <String>{};
      final directTransport = <String>{};
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = path
            .relative(file.path, from: 'lib')
            .replaceAll('\\', '/');
        if (source.startsWith('generated/') || source.endsWith('.g.dart')) {
          continue;
        }
        final unit = parseSource(file.readAsStringSync());
        for (final call in matchingUnitStaticCalls(unit, _getxRegistryCalls)) {
          violations.add('$source -> $call');
        }
        if (_isPresentation(source)) {
          for (final uri in unitDependencies(unit)) {
            final target = localDependency(file, uri) ?? uri;
            if (_isTransport(target)) directTransport.add('$source -> $target');
            final readsSettingsCatalog =
                target == 'services/settings/stored_preferences.dart' &&
                !source.startsWith('pages/setting/');
            if (_isRestricted(target) ||
                readsSettingsCatalog ||
                vendoredImplementations.any(target.startsWith)) {
              violations.add('$source -> $target');
            }
          }
        }
        for (final (:name, :base) in typeInheritance(unit)) {
          baseTypes.putIfAbsent(base, () => {}).add('$source#$name');
        }
      }

      final pending = _getxTypes.toList();
      final visited = <String>{};
      while (pending.isNotEmpty) {
        final base = pending.removeLast();
        if (!visited.add(base)) continue;
        for (final subtype in baseTypes[base] ?? const <String>{}) {
          violations.add('$subtype -> $base');
          pending.add(subtype.split('#').last);
        }
      }

      final forbidden = violations.toList()..sort();
      expect(
        directTransport,
        isEmpty,
        reason: 'Presentation must not access transport directly',
      );
      expect(
        forbidden,
        isEmpty,
        reason: 'Forbidden dependencies:\n${forbidden.join('\n')}',
      );
    },
  );
}
