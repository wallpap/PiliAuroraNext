/// 编辑器拥有的面板交互记忆；不持有请求、订阅或 Flutter 控制器。
class CommunityPickerMemory<T> {
  String keyword = '';
  Object? account;
  final selected = <T>{};
}
