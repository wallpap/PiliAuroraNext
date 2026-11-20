class VoteOptionDraft {
  VoteOptionDraft({Object? id, this.text = '', this.image = ''})
    : id = id ?? Object();
  final Object id;
  final String text, image;
  VoteOptionDraft copy({String? text, String? image}) => VoteOptionDraft(
    id: id,
    text: text ?? this.text,
    image: image ?? this.image,
  );
}

class VoteDraft {
  VoteDraft({
    this.title = '',
    this.description = '',
    this.type = 0,
    this.choices = 1,
    required this.deadline,
    required List<VoteOptionDraft> options,
  }) : options = List.unmodifiable(options);
  final String title, description;
  final int type, choices;
  final DateTime deadline;
  final List<VoteOptionDraft> options;
  List<Object?> get snapshot => [
    title,
    description,
    type,
    choices,
    deadline,
    for (final option in options) (option.text, option.image),
  ];
  VoteDraft copy({
    String? title,
    String? description,
    int? type,
    int? choices,
    DateTime? deadline,
    List<VoteOptionDraft>? options,
  }) => VoteDraft(
    title: title ?? this.title,
    description: description ?? this.description,
    type: type ?? this.type,
    choices: choices ?? this.choices,
    deadline: deadline ?? this.deadline,
    options: options ?? this.options,
  );
}
