import 'package:pili_aurora_next/features/playback/domain/interactive_video/choice.dart';

class Question {
  List<Choice>? choices;

  Question({
    this.choices,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    choices: (json['choices'] as List<dynamic>?)
        ?.map((e) => Choice.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
