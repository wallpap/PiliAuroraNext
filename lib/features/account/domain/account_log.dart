typedef LogRow = List<(int, String)>;

enum LogType {
  login('登录记录', [(3, '时间'), (2, '变化'), (3, '地理位置')]),
  coin('硬币记录', [(3, '时间'), (1, '变化'), (4, '原因')]),
  exp('经验记录', [(2, '时间'), (1, '变化'), (2, '原因')]);

  const LogType(this.title, this.header);
  final String title;
  final LogRow header;

  LogRow row(String time, String change, String detail) => List.unmodifiable([
    (header[0].$1, time),
    (header[1].$1, change),
    (header[2].$1, detail),
  ]);
}
