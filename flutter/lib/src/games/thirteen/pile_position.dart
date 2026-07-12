/// 十三水三墩位置枚举。
///
/// 统一表示"头墩/中墩/尾墩"，消除 'head'/'middle'/'tail' 字符串路由。
/// 替代三个平行 List<int> + string 分发函数的模式。
enum PilePosition {
  head(0, 'head', '头墩'),
  middle(1, 'middle', '中墩'),
  tail(2, 'tail', '尾墩');

  const PilePosition(this.positionIndex, this.key, this.label);

  /// FFI 位置值（0=头墩, 1=中墩, 2=尾墩）。
  final int positionIndex;

  /// JSON map key（'head' / 'middle' / 'tail'）。
  final String key;

  /// UI 中文标签。
  final String label;

  /// 该墩应有的牌数。
  int get cardCount => switch (this) {
    PilePosition.head => 3,
    PilePosition.middle => 5,
    PilePosition.tail => 5,
  };

  static PilePosition fromKey(String key) => switch (key) {
    'head' => head,
    'middle' => middle,
    _ => tail,
  };

  static PilePosition fromIndex(int index) => switch (index) {
    0 => head,
    1 => middle,
    _ => tail,
  };
}
