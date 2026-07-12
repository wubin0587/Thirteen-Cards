enum AiDecisionSource { onnx, nativeFallback }

class AiDecision<T> {
  const AiDecision({
    required this.value,
    required this.source,
    this.model,
    this.error,
  });

  final T value;
  final AiDecisionSource source;
  final String? model;
  final Object? error;

  bool get usedFallback => source == AiDecisionSource.nativeFallback;
}
