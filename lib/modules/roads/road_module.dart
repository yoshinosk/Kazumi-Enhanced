class Road {
  String name;
  List<String> data;
  List<String> identifier;

  /// 可选的稳定页面标识（与 [data] 一一对应）。本地媒体库远程播放时
  /// [data] 是带 token 的 HTTP 流地址，而历史 / 续播必须使用稳定的
  /// `kazumi-lan://` 伪路径，两者在此分离。
  List<String>? pageUrls;

  Road({
    required this.name,
    required this.data,
    required this.identifier,
    this.pageUrls,
  });
}
