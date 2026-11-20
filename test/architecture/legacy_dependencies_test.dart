import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _implementationEntries = {
  'features/account/application/accounts.dart',
  'features/account/application/login_sync.dart',
  'services/settings/storage.dart',
};

bool _isRestricted(String target) =>
    _isTransport(target) ||
    target.startsWith('generated/') ||
    featureLayer(target, 'data') ||
    _implementationEntries.contains(target) ||
    const [
      'package:dlna_dart/',
      'package:protobuf/',
      'package:hive_ce/',
      'package:shared_preferences/',
    ].any(target.startsWith);

bool _isTransport(String target) =>
    (target.startsWith('http/') && target != 'http/loading_state.dart') ||
    target.startsWith('grpc/') ||
    target.startsWith('package:dio/') ||
    target.startsWith('package:grpc/');

bool _isProtocolAdapter(String source) =>
    featureLayer(source, 'data') ||
    source.startsWith('grpc/') ||
    source.startsWith('http/') ||
    const {
      'services/messaging/conversation_adapter.dart',
      'services/messaging/session_adapter.dart',
      'services/messaging/settings_adapter.dart',
    }.contains(source);

bool _violatesFeatureDirection(String source, String target) {
  if (!source.startsWith('features/')) return false;
  final presentation = featureLayer(source, 'presentation');
  if (target.startsWith('package:get/') &&
      !(presentation && target == 'package:get/route_manager.dart')) {
    return true;
  }
  if (featureLayer(source, 'domain')) {
    return isPresentation(target) ||
        featureLayer(target, 'application') ||
        featureLayer(target, 'data') ||
        _isRestricted(target) && !target.startsWith('package:hive_ce/') ||
        const [
          'dart:ui',
          'package:flutter',
          'package:material_ui/',
          'platform/',
          'router/',
          'services/settings/',
        ].any(target.startsWith);
  }
  if (featureLayer(source, 'application') || featureLayer(source, 'data')) {
    return isPresentation(target) ||
        target.startsWith('package:flutter_smart_dialog/');
  }
  return false;
}

void main() {
  test(
    'application source respects presentation, feature and protocol boundaries',
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
      for (final file in dartFiles('lib')) {
        final source = libPath(file);
        final unit = parseSource(file.readAsStringSync());
        for (final call in matchingUnitStaticCalls(unit, _getxRegistryCalls)) {
          violations.add('$source -> $call');
        }
        for (final uri in unitDependencies(unit)) {
          final target = localDependency(file, uri) ?? uri;
          final usesStoredPreferences =
              target == 'services/settings/stored_preferences.dart' &&
              !source.startsWith('pages/setting/');
          if ((isPresentation(source) &&
                  (_isRestricted(target) ||
                      usesStoredPreferences ||
                      vendoredImplementations.any(target.startsWith))) ||
              (_violatesFeatureDirection(source, target)) ||
              (target.startsWith('generated/bilibili/') &&
                  !_isProtocolAdapter(source))) {
            violations.add('$source -> $target');
          }
        }
        for (final directive in unit.directives.whereType<ExportDirective>()) {
          final targets = [
            directive.uri.stringValue,
            for (final configuration in directive.configurations)
              configuration.uri.stringValue,
          ];
          for (final uri in targets.whereType<String>()) {
            final target = localDependency(file, uri) ?? uri;
            if (!featureLayer(source, 'data') && _isRestricted(target)) {
              violations.add('$source exports $target');
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
        forbidden,
        isEmpty,
        reason: 'Forbidden dependencies:\n${forbidden.join('\n')}',
      );
    },
  );
}
