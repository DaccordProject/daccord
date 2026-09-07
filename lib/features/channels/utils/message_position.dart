/// Compare snowflakes without losing precision on web or ordering "10" before
/// "9". Qualified IDs retain their domain as a tie-breaker.
int compareMessageIds(String a, String b) {
  final left = BigInt.tryParse(a.split('@').first);
  final right = BigInt.tryParse(b.split('@').first);
  if (left != null && right != null) {
    final order = left.compareTo(right);
    if (order != 0) return order;
  }
  return a.compareTo(b);
}
