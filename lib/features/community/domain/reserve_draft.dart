class ReserveDraft {
  const ReserveDraft({this.title = '', this.subType = 0, required this.date});
  final String title;
  final int subType;
  final DateTime date;
  (String, int, DateTime) get snapshot => (title, subType, date);
  ReserveDraft copy({String? title, int? subType, DateTime? date}) =>
      ReserveDraft(
        title: title ?? this.title,
        subType: subType ?? this.subType,
        date: date ?? this.date,
      );
}
