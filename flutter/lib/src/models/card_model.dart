enum CardSuit {
  diamonds(0, '♦', true),
  clubs(1, '♣', false),
  hearts(2, '♥', true),
  spades(3, '♠', false),
  joker(-1, 'JOKER', false);

  const CardSuit(this.code, this.label, this.isRed);

  final int code;
  final String label;
  final bool isRed;
}

class PlayingCard {
  const PlayingCard({
    required this.id,
    required this.rank,
    required this.suit,
    this.face,
    this.isSmallJoker = false,
    this.isBigJoker = false,
  });

  final int id;
  final int rank;
  final CardSuit suit;
  final int? face;
  final bool isSmallJoker;
  final bool isBigJoker;

  bool get isJoker => isSmallJoker || isBigJoker;

  bool get isRedFive => face == 14 || (rank == 3 && suit == CardSuit.hearts);

  String get rankLabel {
    if (isJoker) return 'J';
    return switch (rank) {
      12 => 'A',
      11 => 'K',
      10 => 'Q',
      9 => 'J',
      8 => '10',
      7 => '9',
      6 => '8',
      5 => '7',
      4 => '6',
      3 => '5',
      2 => '4',
      1 => '3',
      0 => '2',
      _ => '?',
    };
  }

  String get suitLabel => isJoker ? 'J' : suit.label;

  static PlayingCard standard(int id) {
    final face = id % 54;
    if (face == 53) {
      return PlayingCard(
        id: id,
        face: face,
        rank: -1,
        suit: CardSuit.joker,
        isBigJoker: true,
      );
    }
    if (face == 52) {
      return PlayingCard(
        id: id,
        face: face,
        rank: -1,
        suit: CardSuit.joker,
        isSmallJoker: true,
      );
    }
    final suitCode = face % 4;
    return PlayingCard(
      id: id,
      face: face,
      rank: face ~/ 4,
      suit: CardSuit.values.firstWhere((suit) => suit.code == suitCode),
    );
  }
}
