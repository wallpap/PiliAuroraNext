import 'package:pili_aurora_next/core/random/random_text.dart';

String makeHeroTag(Object? value) =>
    '$value${sharedRandom.nextInt(9999)}';
