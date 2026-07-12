/// i18n 字符串字典基类
///
/// 所有用户可见文本通过此接口访问，自动跟随 AppSettings.locale。
class AppStrings {
  AppStrings();

  /// 从当前 locale 获取字典实例
  factory AppStrings.of() => _current;
  static AppStrings _current = AppStringsZh();

  /// 切换语言 (传入 'zh' 或 'en')
  static void setLocale(String code) {
    _current = switch (code) {
      'en' => AppStringsEn(),
      _ => AppStringsZh(),
    };
  }

  // ======== 通用 ========
  String get appTitle => 'Local Cards';
  String get newRound => '新局';
  String get submit => '提交';
  String get undo => '回退';
  String get skip => '跳过';
  String get back => '返回';
  String get ok => '确定';
  String get cancel => '取消';
  String get retry => '重试';

  // ======== 大厅 ========
  String get lobbyDifficulty => '游戏难度';
  String get lobbyEasy => '简单';
  String get lobbyMedium => '中等';
  String get lobbyHard => '困难';
  String get lobbyEnter => '进入牌桌';
  String get lobbyHistory => '历史';
  String get lobbyTotalGames => '总局数';
  String get lobbyWinRate => '胜率';
  String get lobbyThirteenAvg => '十三水均分';
  String get lobbyLocalGames => '本地牌局';
  String get lobbySelectPlayers => '选择人数';
  String get lobbyPlayers => '人';

  // ======== 十三水 ========
  String get tcTitle => '十三水';
  String get tcSettled => '已结算';
  String get tcPlacing => '摆墩中';
  String get tcMyHand => '我的手牌';
  String get tcDealId => '局号';
  String get tcPlayers => '人数';
  String get tcTotal => '累计';
  String get tcShootPairs => '打枪';
  String get tcHead => '头墩';
  String get tcMiddle => '中墩';
  String get tcTail => '尾墩';
  String get tcAuto => '自动';
  String get tcPending => '待填充';
  String get tcSpecialHand => '特殊牌型';
  String get tcRecommend => '推荐';
  String get tcFillFromRec => '填入';
  String get tcConservative => '保守';
  String get tcDefault => '默认';
  String get tcAggressive => '激进';
  String get tcVs => '对手';
  String get tcDealer => '庄';
  String get tcMyTurn => '摆墩中';
  String get tcNewGameHint => '点击「新局」开始游戏';
  String get tcFailedPrefix => '失败';
  String get tcErrorPrefix => '错误';
  String get tcWaterPrefix => '水';
  String get tcFouledBuyout => '倒水买单';
  String get tcAiThinking => 'AI 思考中…';
  String tcNet(int n) => n >= 0 ? '+$n' : '$n';
  String tcHandStatus(int h, int m, int t) => '头墩${h}张/中墩${m}张/尾墩${t}张';
  String tcDealt(int score) => '检测到特殊牌型（${score}水），直接结算';

  // ======== 牌型名称 (DLL 已提供，此处留空) ========
  // 牌型名称由 C++ DLL 的 tc_get_hand_name_zh() 提供
}

class AppStringsZh extends AppStrings {
  @override
  String get appTitle => '本地牌局';

  @override
  String get newRound => '新局';
  @override
  String get submit => '提交';
  @override
  String get undo => '回退';
  @override
  String get skip => '跳过';
  @override
  String get back => '返回';
  @override
  String get ok => '确定';
  @override
  String get cancel => '取消';
  @override
  String get retry => '重试';

  @override
  String get lobbyDifficulty => '游戏难度';
  @override
  String get lobbyEasy => '简单';
  @override
  String get lobbyMedium => '中等';
  @override
  String get lobbyHard => '困难';
  @override
  String get lobbyEnter => '进入牌桌';
  @override
  String get lobbyHistory => '历史';
  @override
  String get lobbyTotalGames => '总局数';
  @override
  String get lobbyWinRate => '胜率';
  @override
  String get lobbyThirteenAvg => '十三水均分';
  @override
  String get lobbyLocalGames => '本地牌局';
  @override
  String get lobbySelectPlayers => '选择人数';
  @override
  String get lobbyPlayers => '人';

  @override
  String get tcTitle => '十三水';
  @override
  String get tcSettled => '已结算';
  @override
  String get tcPlacing => '摆墩中';
  @override
  String get tcMyHand => '我的手牌';
  @override
  String get tcDealId => '局号';
  @override
  String get tcPlayers => '人数';
  @override
  String get tcTotal => '累计';
  @override
  String get tcShootPairs => '打枪';
  @override
  String get tcHead => '头墩';
  @override
  String get tcMiddle => '中墩';
  @override
  String get tcTail => '尾墩';
  @override
  String get tcAuto => '自动';
  @override
  String get tcPending => '待填充';
  @override
  String get tcSpecialHand => '特殊牌型';
  @override
  String get tcRecommend => '推荐';
  @override
  String get tcFillFromRec => '填入';
  @override
  String get tcConservative => '保守';
  @override
  String get tcDefault => '默认';
  @override
  String get tcAggressive => '激进';
  @override
  String get tcVs => '对手';
  @override
  String get tcDealer => '庄';
  @override
  String get tcMyTurn => '摆墩中';
  @override
  String get tcNewGameHint => '点击「新局」开始游戏';
  @override
  String get tcFailedPrefix => '失败';
  @override
  String get tcErrorPrefix => '错误';
  @override
  String get tcWaterPrefix => '水';
  @override
  String get tcFouledBuyout => '倒水买单';
  @override
  String get tcAiThinking => 'AI 思考中…';
}

class AppStringsEn extends AppStrings {
  @override
  String get appTitle => 'Local Cards';

  @override
  String get newRound => 'New Game';
  @override
  String get submit => 'Submit';
  @override
  String get undo => 'Undo';
  @override
  String get skip => 'Skip';
  @override
  String get back => 'Back';
  @override
  String get ok => 'OK';
  @override
  String get cancel => 'Cancel';
  @override
  String get retry => 'Retry';

  @override
  String get lobbyDifficulty => 'Difficulty';
  @override
  String get lobbyEasy => 'Easy';
  @override
  String get lobbyMedium => 'Medium';
  @override
  String get lobbyHard => 'Hard';
  @override
  String get lobbyEnter => 'Enter Table';
  @override
  String get lobbyHistory => 'History';
  @override
  String get lobbyTotalGames => 'Total Games';
  @override
  String get lobbyWinRate => 'Win Rate';
  @override
  String get lobbyThirteenAvg => '13W Avg';
  @override
  String get lobbyLocalGames => 'Local Games';
  @override
  String get lobbySelectPlayers => 'Select Players';
  @override
  String get lobbyPlayers => ' Players';

  @override
  String get tcTitle => '13 Waters';
  @override
  String get tcSettled => 'Settled';
  @override
  String get tcPlacing => 'Placing';
  @override
  String get tcMyHand => 'My Hand';
  @override
  String get tcDealId => 'Deal #';
  @override
  String get tcPlayers => 'Players';
  @override
  String get tcTotal => 'Total';
  @override
  String get tcShootPairs => 'Shoots';
  @override
  String get tcHead => 'Head';
  @override
  String get tcMiddle => 'Middle';
  @override
  String get tcTail => 'Tail';
  @override
  String get tcAuto => 'Auto';
  @override
  String get tcPending => 'Empty';
  @override
  String get tcSpecialHand => 'Special Hand';
  @override
  String get tcRecommend => 'Recommend';
  @override
  String get tcFillFromRec => 'Fill';
  @override
  String get tcConservative => 'Safe';
  @override
  String get tcDefault => 'Normal';
  @override
  String get tcAggressive => 'Aggressive';
  @override
  String get tcVs => 'Opponent';
  @override
  String get tcDealer => 'D';
  @override
  String get tcMyTurn => 'Placing';
  @override
  String get tcNewGameHint => 'Click "New Game" to start';
  @override
  String get tcFailedPrefix => 'Failed';
  @override
  String get tcErrorPrefix => 'Error';
  @override
  String get tcWaterPrefix => 'Water';
  @override
  String get tcFouledBuyout => 'Foul';
  @override
  String get tcAiThinking => 'AI Thinking…';
}
