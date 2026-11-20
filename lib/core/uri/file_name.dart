String uriFileName(String uri, {bool fileExt = true}) {
  final query = uri.indexOf('?');
  final end = query < 0 ? uri.length : query;
  final path = uri.substring(0, end);
  final slash = path.lastIndexOf('/');
  RangeError.checkNotNegative(slash, '/');
  final dot = fileExt ? -1 : path.lastIndexOf('.');
  return path.substring(slash + 1, dot > slash ? dot : end);
}
