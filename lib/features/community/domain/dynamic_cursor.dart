class DynamicCursor {
  const DynamicCursor(this.offset, this.seen);
  final String? offset;
  final Set<String> seen;
}
