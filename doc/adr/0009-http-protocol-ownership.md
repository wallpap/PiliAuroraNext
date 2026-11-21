# 路由表与请求协议分开维护

`Api` 只保存当前使用的地址，不把历史请求抓包、示例令牌和旧路由当作协议说明。编号、表单、身份、签名和分页由实际发出请求的模块持有。更新接口时变更对应请求实现和测试，避免路由注释和实际请求各自维护一套参数。

- 点赞、点踩和投币使用 APP 接口，不把旧 Web 路由当作可互换的备用地址；合集、普通视频和直播仍沿用各自的实现。入口见 [`video.dart`](../../lib/http/video.dart) 和 [`live.dart`](../../lib/http/live.dart)。
- 收藏夹列表、批量收录和取消收录由收藏请求构造，普通列表、跨收藏夹搜索和批量写入不能混用参数。关注列表的排序使用领域枚举，而非复制请求示例。入口见 [`fav.dart`](../../lib/http/fav.dart) 和 [`follow_order_type.dart`](../../lib/features/following/domain/follow_order_type.dart)。
- 账号挑战信息只交给相应登录请求，不把抓包的会话值、时间戳或签名固化到仓库。私信列表和已读更新以消息模块的现行请求和会话归属为准。入口见 [`login.dart`](../../lib/http/login.dart) 和[消息模块](../../lib/services/messaging/README.md)。
