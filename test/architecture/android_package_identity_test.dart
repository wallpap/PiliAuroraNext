import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _package = 'com.wallpap.piliauroranext';
const _packagePath = 'com/wallpap/piliauroranext';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test(
    'Android components and build variants share the application namespace',
    () {
      final gradle = _read('android/app/build.gradle.kts');
      expect(gradle, contains('namespace = "$_package"'));
      expect(gradle, contains('applicationId = "$_package"'));
      for (final suffix in ['debug', 'profile', 'dev']) {
        expect(gradle, contains('applicationIdSuffix = ".$suffix"'));
      }

      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('package="$_package"'));
      expect(
        manifest,
        contains('android:authorities="\${applicationId}.MTDataFilesProvider"'),
      );
      expect(manifest, contains('android:name=".MainActivity"'));
      expect(manifest, contains('android:name="$_package.SHORTCUT"'));

      final activity = _read(
        'android/app/src/main/kotlin/$_packagePath/MainActivity.kt',
      );
      for (final alias in ['Chibi', 'Upright', 'Tilted', 'Portrait']) {
        expect(manifest, contains('android:name=".${alias}Launcher"'));
        expect(activity, contains('"${alias}Launcher"'));
      }
      expect(activity, contains('ComponentName(this, "$_package.\$alias")'));
      expect(
        _read('android/app/src/main/res/xml-v25/shortcuts.xml'),
        contains('android:action="$_package.SHORTCUT"'),
      );
    },
  );

  test('Android launcher refresh marker is not a public launcher entry', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:name=".PiliAuroraApplication"'));
    expect(
      manifest,
      matches(
        r'<receiver\s+android:name="\.LauncherIconRefreshMarker"'
        r'\s+android:exported="false"\s*/>',
      ),
    );
  });

  test('JNI bindings resolve the Java classes in the source package', () {
    for (final language in ['java', 'kotlin']) {
      final directory = Directory(
        'android/app/src/main/$language/$_packagePath',
      );
      final sources = directory.listSync().whereType<File>().where(
        (file) => file.path.endsWith('.java') || file.path.endsWith('.kt'),
      );
      expect(sources, isNotEmpty);
      for (final source in sources) {
        expect(
          RegExp(
            r'^package\s+([^;\s]+)',
            multiLine: true,
          ).firstMatch(source.readAsStringSync())?.group(1),
          _package,
        );
      }
    }

    expect(_read('tool/jnigen.dart'), contains("'$_package.AndroidHelper'"));
    final bindings = _read('lib/platform/android/bindings.g.dart');
    for (final name in ['AndroidHelper', 'AndroidHelper\$ToDart']) {
      expect(bindings, contains("r'$_packagePath/$name'"));
      expect(bindings, contains("r'L$_packagePath/$name;'"));
    }
  });
}
