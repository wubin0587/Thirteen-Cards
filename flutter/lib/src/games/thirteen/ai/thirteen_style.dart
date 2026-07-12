/// 十三水 AI 摆牌策略风格。
enum AiStyle {
  conservative,
  balanced,
  aggressive;

  /// aggression 参数值（传递给 ONNX 温度采样调整）。
  double get aggression => switch (this) {
    AiStyle.conservative => -0.6,
    AiStyle.balanced => 0.0,
    AiStyle.aggressive => 0.6,
  };
}
