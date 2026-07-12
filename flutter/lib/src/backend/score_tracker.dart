/// 游戏记录存储系统
///
/// 职责分层：
///   GameRecord           — 一条游戏记录的数据模型
///   GameScoreStore<T>    — 记录存储器抽象接口（可插入）
///   ThirteenRoundRecord  — 十三水回合记录（带 JSON 序列化，兼容旧格式）
///   ThirteenStats        — 十三水统计汇总（类型安全，非 raw Map）
///   ThirteenScoreStore   — 十三水记录持久化实现
///
/// 设计原则：
/// - 接口化可插入：每种游戏有自己的 Store，互不干扰
/// - 存算分离：Store 只管增删查，Stats 只管聚合计算
/// - 原子写入：临时文件 + rename，防止写崩溃数据损坏
/// - 宽容读取：fromJson 失败跳过单条记录而非整体崩溃
/// - 兼容旧格式：自动识别 all_nets / my_net 旧字段做迁移
library;

import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

// ============================================================
// 抽象接口
// ============================================================

/// 一条游戏记录必须能序列化自身。
abstract class GameRecord {
  DateTime get time;
  Map<String, dynamic> toJson();
}

/// 游戏记录存储器抽象。
///
/// 每种游戏有自己的实现，互不干扰。
/// 实现类负责：记录的增删查、持久化、记录上限裁剪。
abstract class GameScoreStore<T extends GameRecord> {
  /// 最多保留多少条记录。
  int get maxRecords;

  /// 追加一条记录，超限时自动裁剪旧数据。
  Future<void> record(T record);

  /// 读取所有记录。
  Future<List<T>> getAll();

  /// 清空所有记录。
  Future<void> clear();
}

// ============================================================
// 十三水记录模型
// ============================================================

/// 十三水一局的完整记录。
class ThirteenRoundRecord implements GameRecord {
  const ThirteenRoundRecord({
    required this.time,
    required this.playerCount,
    required this.mySeat,
    required this.nets,
    this.shootCount = 0,
    this.fouled = false,
    this.homerun = false,
    this.specialName = '',
    this.headHand,
    this.middleHand,
    this.tailHand,
    this.headScore,
    this.middleScore,
    this.tailScore,
    this.headCards,
    this.middleCards,
    this.tailCards,
  });

  @override
  final DateTime time;

  /// 玩家人数（通常 4）。
  final int playerCount;

  /// 我的座位索引（对应 [nets] 中的位置）。
  final int mySeat;

  /// 所有玩家在该局的净得分。
  final List<int> nets;

  /// 打枪次数。
  final int shootCount;

  /// 是否倒水。
  final bool fouled;

  /// 是否全垒打。
  final bool homerun;

  /// 特殊牌型名称（如「十三水」、「一条龙」）。
  final String specialName;

  /// 头墩牌型中文名（如"对子"、"三条"）。
  final String? headHand;
  /// 中墩牌型中文名。
  final String? middleHand;
  /// 尾墩牌型中文名。
  final String? tailHand;

  /// 头墩基础分（水数）。
  final int? headScore;
  /// 中墩基础分。
  final int? middleScore;
  /// 尾墩基础分。
  final int? tailScore;

  /// 头墩3张牌ID。
  final List<int>? headCards;
  /// 中墩5张牌ID。
  final List<int>? middleCards;
  /// 尾墩5张牌ID。
  final List<int>? tailCards;

  /// 我的净得分 — 基于 [mySeat] 从 [nets] 中取出。
  int get myNet =>
      (mySeat >= 0 && mySeat < nets.length) ? nets[mySeat] : 0;

  // ----------------------------------------------------------
  // 序列化
  // ----------------------------------------------------------

  @override
  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'player_count': playerCount,
        'my_seat': mySeat,
        'nets': nets,
        if (shootCount > 0) 'shoot': shootCount,
        if (fouled) 'fouled': true,
        if (homerun) 'homerun': true,
        if (specialName.isNotEmpty) 'special': specialName,
        if (headHand != null) 'head_hand': headHand,
        if (middleHand != null) 'middle_hand': middleHand,
        if (tailHand != null) 'tail_hand': tailHand,
        if (headScore != null) 'head_score': headScore,
        if (middleScore != null) 'middle_score': middleScore,
        if (tailScore != null) 'tail_score': tailScore,
        if (headCards != null) 'head_cards': headCards,
        if (middleCards != null) 'middle_cards': middleCards,
        if (tailCards != null) 'tail_cards': tailCards,
      };

  /// 从 JSON 反序列化。
  ///
  /// 兼容旧版本字段：
  /// - `all_nets` → 转换为新格式 `nets`
  /// - 无 `my_seat` 但有 `my_net` → 按值匹配定位
  static ThirteenRoundRecord? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);

    // 新格式：nets
    List<int>? nets;
    final netsRaw = json['nets'];
    if (netsRaw is List) {
      nets = netsRaw.whereType<num>().map((e) => e.toInt()).toList();
    }
    // 旧格式兼容：all_nets → nets
    if ((nets == null || nets.isEmpty) && json['all_nets'] is List) {
      nets =
          (json['all_nets'] as List).whereType<num>().map((e) => e.toInt()).toList();
    }

    final playerCount = _toInt(json['player_count']);
    int mySeat = _toInt(json['my_seat']) ?? 0;

    // 旧格式兼容：无 my_seat，但有 my_net → 按值匹配
    if (json['my_seat'] == null && json['my_net'] != null && nets != null) {
      final myNet = _toInt(json['my_net']) ?? 0;
      final idx = nets.indexOf(myNet);
      if (idx >= 0) mySeat = idx;
    }

    if (playerCount == null || nets == null || nets.isEmpty) return null;
    if (mySeat < 0 || mySeat >= nets.length) mySeat = 0;

    return ThirteenRoundRecord(
      time: DateTime.tryParse('${json['time']}') ?? DateTime.now(),
      playerCount: playerCount,
      mySeat: mySeat,
      nets: nets,
      shootCount: _toInt(json['shoot']) ?? 0,
      fouled: json['fouled'] == true,
      homerun: json['homerun'] == true,
      specialName: '${json['special'] ?? ''}',
      headHand: _str(json['head_hand']),
      middleHand: _str(json['middle_hand']),
      tailHand: _str(json['tail_hand']),
      headScore: _toInt(json['head_score']),
      middleScore: _toInt(json['middle_score']),
      tailScore: _toInt(json['tail_score']),
      headCards: _ints(json['head_cards']),
      middleCards: _ints(json['middle_cards']),
      tailCards: _ints(json['tail_cards']),
    );
  }

  static int? _toInt(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _str(Object? v) {
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  static List<int>? _ints(Object? v) {
    if (v is List) return v.whereType<num>().map((e) => e.toInt()).toList();
    return null;
  }
}

// ============================================================
// 十三水统计
// ============================================================

/// 十三水统计汇总 — 类型安全，不含红五或其他游戏数据。
class ThirteenStats {
  const ThirteenStats({
    required this.games,
    required this.wins,
    required this.totalNet,
    required this.avgNet,
    required this.winRate,
  });

  /// 总局数。
  final int games;

  /// 胜局数（myNet > 0）。
  final int wins;

  /// 累计净得分。
  final int totalNet;

  /// 平均每局净得分。
  final double avgNet;

  /// 胜率（0.0 ~ 1.0），无记录时为 0.0。
  final double winRate;

  static const ThirteenStats empty = ThirteenStats(
    games: 0,
    wins: 0,
    totalNet: 0,
    avgNet: 0.0,
    winRate: 0.0,
  );
}

// ============================================================
// 十三水记分存储器
// ============================================================

/// 十三水本地 JSON 记分板。
///
/// 特性：
/// - 最多保留 200 条记录（自动裁剪）
/// - 原子写入防崩溃（tmp + rename）
/// - pretty-print JSON 方便人工调试
/// - 兼容旧版 JSON 格式（all_nets / my_net）
/// - 非单例：测试时可注入自定义目录
///
/// 使用示例：
/// ```dart
/// final store = ThirteenScoreStore.instance;
/// await store.record(ThirteenRoundRecord(...));
/// final stats = await store.getStats();
/// ```
class ThirteenScoreStore implements GameScoreStore<ThirteenRoundRecord> {
  // ----------------------------------------------------------
  // 构造
  // ----------------------------------------------------------

  ThirteenScoreStore({String? directory})
      : filePath = _buildPath(directory);

  /// 默认单例（便利用途，非强制）。
  static final ThirteenScoreStore instance = ThirteenScoreStore();

  /// JSON 文件绝对路径。
  final String filePath;

  @override
  int get maxRecords => _kMaxRecords;
  static const int _kMaxRecords = 200;

  // ----------------------------------------------------------
  // 内部状态
  // ----------------------------------------------------------

  List<ThirteenRoundRecord> _records = [];
  bool _loaded = false;

  /// 增量统计缓存（避免每局遍历全部 200 条记录）。
  int _cachedWins = 0;
  int _cachedTotalNet = 0;
  int _cachedHomeruns = 0;
  int _cachedShoots = 0;

  /// 累计胜局数（缓存）。
  int get cachedWins => _cachedWins;
  /// 累计净得分（缓存）。
  int get cachedTotalNet => _cachedTotalNet;
  /// 累计全垒打次数（缓存）。
  int get cachedHomeruns => _cachedHomeruns;
  /// 累计打枪次数（缓存）。
  int get cachedShoots => _cachedShoots;

  /// 当前连胜数（从最新记录开始扫描，遇到输局或耗尽为止）。
  int get currentStreak {
    var streak = 0;
    for (final r in _records) {
      if (r.myNet > 0) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  void _addToCache(ThirteenRoundRecord r) {
    if (r.myNet > 0) _cachedWins++;
    _cachedTotalNet += r.myNet;
    if (r.homerun) _cachedHomeruns++;
    _cachedShoots += r.shootCount;
  }

  void _removeFromCache(ThirteenRoundRecord r) {
    if (r.myNet > 0) _cachedWins--;
    _cachedTotalNet -= r.myNet;
    if (r.homerun) _cachedHomeruns--;
    _cachedShoots -= r.shootCount;
  }

  void _recomputeCache() {
    _cachedWins = 0;
    _cachedTotalNet = 0;
    _cachedHomeruns = 0;
    _cachedShoots = 0;
    for (final r in _records) {
      _addToCache(r);
    }
  }

  void _resetCache() {
    _cachedWins = 0;
    _cachedTotalNet = 0;
    _cachedHomeruns = 0;
    _cachedShoots = 0;
  }

  // ----------------------------------------------------------
  // 路径解析
  // ----------------------------------------------------------

  static String _buildPath(String? directory) {
    final dir = directory ?? AppPaths.dataDir();
    final sep = Platform.pathSeparator;
    return '$dir${sep}thirteen_scores.json';
  }

  // ----------------------------------------------------------
  // 存储操作
  // ----------------------------------------------------------

  @override
  Future<void> record(ThirteenRoundRecord record) async {
    await _ensure();
    _records.add(record);
    _addToCache(record);
    _trim();
    await _save();
  }

  @override
  Future<List<ThirteenRoundRecord>> getAll() async {
    await _ensure();
    return List.unmodifiable(_records);
  }

  @override
  Future<void> clear() async {
    _records = [];
    _resetCache();
    _loaded = true;
    await _save();
  }

  /// 计算十三水统计数据（基于缓存，无需遍历）。
  Future<ThirteenStats> getStats() async {
    await _ensure();
    if (_records.isEmpty) return ThirteenStats.empty;

    return ThirteenStats(
      games: _records.length,
      wins: _cachedWins,
      totalNet: _cachedTotalNet,
      avgNet: _cachedTotalNet / _records.length,
      winRate: _cachedWins / _records.length,
    );
  }

  // ----------------------------------------------------------
  // 内部 IO
  // ----------------------------------------------------------

  Future<void> _ensure() async {
    if (_loaded) return;
    final file = File(filePath);
    if (await file.exists()) {
      await _load(file);
    }
    _loaded = true;
  }

  Future<void> _load(File file) async {
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return;
      final list = raw['records'] as List? ?? raw['thirteen'] as List?;
      if (list == null) return;

      _records = list
          .map(ThirteenRoundRecord.fromJson)
          .whereType<ThirteenRoundRecord>()
          .toList();

      _records.sort((a, b) => b.time.compareTo(a.time));
      _trim();
      _recomputeCache();
    } catch (_) {
      _records = [];
    }
  }

  Future<void> _save() async {
    final file = File(filePath);
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 原子写入：先写临时文件，再 rename
    final tmp = File('${filePath}.tmp');
    try {
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 2,
          'game': 'thirteen',
          'records': _records.map((r) => r.toJson()).toList(),
        }),
      );
      await tmp.rename(filePath);
    } catch (e) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  /// 超出上限时裁剪旧记录，同步更新缓存。
  void _trim() {
    if (_records.length > _kMaxRecords) {
      for (var i = _kMaxRecords; i < _records.length; i++) {
        _removeFromCache(_records[i]);
      }
      _records = _records.sublist(0, _kMaxRecords);
    }
  }
}
