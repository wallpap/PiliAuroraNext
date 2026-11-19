final class DanmakuElement {
  DanmakuElement({
    this.id = 0,
    this.idStr = '',
    this.progress = 0,
    this.mode = 0,
    this.fontSize = 0,
    this.color = 0,
    this.midHash = '',
    this.content = '',
    this.weight = 0,
    this.pool = 0,
    this.likeCount = 0,
    this.vipGradient = false,
    this.count = 0,
    this.isSelf = false,
    int additionalStorageBytes = 0,
  }) : storageBytes =
           512 +
           2 * (idStr.length + midHash.length + content.length) +
           additionalStorageBytes;

  final int id;
  final String idStr;
  final int progress;
  final int mode;
  final int fontSize;
  final int color;
  final String midHash;
  final String content;
  final int pool;
  final int likeCount;
  final bool vipGradient;

  /// 缓存和 worker 沿用来源预算，包括投影不保留的协议元数据。
  final int storageBytes;

  int weight;
  int count;
  bool isSelf;
}
