# 福建十三水 — C++ 后端开发文档

> **约束说明**：所有 C++ 实现**仅允许使用 C 标准库**（`<cstdio>`, `<cstdlib>`, `<cstring>`, `<cstdint>`, `<cassert>`, `<ctime>` 等），禁止引入 STL 容器（`std::vector`, `std::string`…）及任何第三方库。

---

## 一、目录结构总览

```
src/cpp/
├── cards/
│   ├── cards.h              # 牌面枚举与无状态工具函数
│   └── cards.cpp            # （暂无实现体，工具函数均为 static inline）
├── pattern/
│   ├── pattern.h            # 牌型识别接口声明
│   ├── pattern.cpp          # 牌型识别算法实现
│   ├── score.h              # 牌型分值查表（纯数据，无逻辑）
│   └── searchPattern.cpp    # 最优拆牌搜索算法实现
├── players/
│   ├── player.h             # 玩家数据结构与接口声明
│   └── player.cpp           # 玩家状态管理实现
└── round/
    ├── round.h              # 局（Round）数据结构与接口声明
    ├── dealer.cpp           # 洗牌、发牌逻辑实现
    ├── evaluate.cpp         # 多玩家结算逻辑实现
    └── closer.cpp           # 本局收尾、积分写入逻辑实现
```

---

## 二、文件职责说明

### 2.1 `cards/cards.h` — 牌面层（只读、无状态）

**职责**：定义全局共享的牌面基础语义，不持有任何运行时状态。

| 内容 | 说明 |
|------|------|
| `enum CardEnum` | 将 0–51（单副）、52–103（第二副）映射到具体花色+点数；`CARD_DECK2_BASE = 52` 作为分界常量 |
| `card_rank(int)` | 取点数索引 `id % 13`（0=2, …, 12=A） |
| `card_suit(int)` | 取花色索引 `id / 13`（0=♦, 1=♣, 2=♥, 3=♠） |
| `rank_str(int)` | 返回点数字符串（静态表，线程安全只读） |
| `suit_char(int)` | 返回花色字符 |

**约束**：
- 所有函数均为 `static inline`，编译器内联，零运行时开销。
- 使用 `extern "C"` 包裹，保证与 Python/Unity FFI 的 ABI 兼容性。
- **禁止**在此文件中引入任何动态内存分配。

---

### 2.2 `pattern/score.h` — 分值查表层（只读数据）

**职责**：以静态常量表的形式存储所有牌型的元数据，供识别层和结算层查询，自身不执行任何计算。

**核心数据结构**：

```c
struct HandTableEntry {
    int         position;   // 0=头墩, 1=中墩, 2=底墩, 3=特殊
    const char* hand_name;  // 英文牌型名，用于日志/调试
    int         rank_order; // 同位置内的大小排名（越大越强）
    int         score;      // 赢得一局该牌型可获得的水数
};
```

**三张表**：

| 表名 | 覆盖范围 | 条目数 |
|------|----------|--------|
| `REGULAR_HANDS[]` | 头/中/底三墩常规牌型（乌龙→同花顺） | 19 |
| `MULTI_DECK_HANDS[]` | 双副牌专属：五同（中墩12水，底墩6水） | 2 |
| `SPECIAL_HANDS[]` | 13张特殊牌型：三顺子→至尊清龙 | 13 |

**约束**：
- 所有表均为 `static const`，只读，编译期确定大小。
- `ALL_HANDS_COUNT` 等宏在编译期计算，禁止在运行时动态注册牌型。
- 此文件**不得**包含任何函数实现（纯数据头文件）。

---

### 2.3 `pattern/pattern.h` & `pattern/pattern.cpp` — 牌型识别层

**职责**：接收一组固定数量的牌 ID，返回其所属牌型的 `rank_order` 与 `score`。

**接口设计（pattern.h）**：

```c
// 识别结果
typedef struct {
    int position;    // 墩位
    int rank_order;  // 牌型大小序号
    int score;       // 该牌型水数
    char name[32];   // 牌型名称（用于 UI 展示/日志）
} PatternResult;

// 识别头墩（3张牌）
PatternResult identify_head(const int cards[3]);

// 识别中/底墩（5张牌）
PatternResult identify_five(const int cards[5], int position);

// 识别特殊牌型（13张牌）；返回 rank_order=0 表示无特殊牌型
PatternResult identify_special(const int cards[13]);
```

**实现要点（pattern.cpp）**：

1. **排序**：在栈上用插入排序（C 标准库 `qsort` 亦可）对 `card_rank` 降序排列，避免堆内存分配。
2. **点数频次统计**：用固定长度数组 `int freq[13] = {0}` 统计各点数出现次数。
3. **识别顺序**（从高到低优先判断，首次命中即返回）：
   - 五同 → 同花顺 → 铁支 → 葫芦 → 同花 → 顺子 → 三条 → 两对 → 对子 → 乌龙
4. **特殊牌型识别**：按 `SPECIAL_HANDS` 的 `rank_order` 从大到小逐一检测，命中即返回最高特殊牌型。

**约束**：
- 禁止动态分配内存，所有中间结果使用栈变量或固定大小数组。
- 函数必须是**纯函数**（同输入同输出，无副作用），以便 AI 训练端直接调用。

---

### 2.4 `pattern/searchPattern.cpp` — 最优拆牌搜索层

**职责**：在给定 13 张手牌中，枚举合法的头/中/底分配方案，调用识别层评分，输出最优若干套方案。

**核心算法**：

```
输入：int hand[13]
输出：ArrangementResult best[MAX_SUGGESTIONS]（MAX_SUGGESTIONS = 3）

流程：
  1. 枚举所有 C(13,3) × C(10,5) = 1287 × 252 ≈ 324,324 种分法
  2. 对每种分法：
     a. identify_head(head_cards)
     b. identify_five(mid_cards, POS_MIDDLE)
     c. identify_five(tail_cards, POS_TAIL)
     d. 合法性校验：rank_order(head) <= rank_order(mid) <= rank_order(tail)（禁止"倒水"）
     e. 计算综合得分 = head.score + mid.score + tail.score
  3. 维护得分前 MAX_SUGGESTIONS 名，使用固定大小数组+简单选择
```

**数据结构**：

```c
typedef struct {
    int head[3];
    int middle[5];
    int tail[5];
    int total_score;
    char label[32]; // "综合最优" / "冲锋打枪" / "保底防守"
} ArrangementResult;
```

**约束**：
- 枚举使用三重嵌套循环（下标组合），禁止递归以避免栈溢出风险。
- 最坏 32 万次评估全部在栈上完成，无需动态内存。
- 对外只暴露一个函数：`int search_best(const int hand[13], ArrangementResult* out, int max_out)`，返回实际找到的方案数。

---

### 2.5 `players/player.h` & `players/player.cpp` — 玩家层

**职责**：管理单个玩家在一局内的状态（手牌、当前摆放、累计积分）。

**数据结构（player.h）**：

```c
#define MAX_HAND_SIZE 13
#define MAX_PLAYERS   8

typedef struct {
    int  id;                          // 玩家 ID（0-indexed）
    int  hand[MAX_HAND_SIZE];         // 发到的手牌
    int  hand_count;                  // 实际手牌数量（通常=13）
    int  arrangement[MAX_HAND_SIZE];  // 已摆好的牌序（前3=头，3-7=中，8-12=底）
    int  is_arranged;                 // 是否完成摆牌（0/1）
    int  cumulative_score;            // 本局累计得分（水数，可为负）
    int  is_special;                  // 是否触发特殊牌型（0/1）
} Player;
```

**接口（player.h）**：

```c
void player_init(Player* p, int id);
void player_deal(Player* p, const int cards[], int count);
int  player_set_arrangement(Player* p, const int arrangement[13]);
void player_reset_round(Player* p); // 保留 id 和累计分，清空手牌/摆牌
```

**约束**：
- `Player` 用值传递或指针，禁止堆上 `malloc`。
- `player_set_arrangement` 需调用 `identify_head` / `identify_five` 做合法性验证，非法摆法返回非零错误码。

---

### 2.6 `round/round.h` — 局结构声明

**职责**：定义一局游戏的全局状态，作为 dealer / evaluate / closer 三个模块的共享数据上下文。

```c
#define MAX_DECK_SIZE 104 // 双副牌最大

typedef struct {
    int      player_count;              // 本局玩家数（3~8）
    Player   players[MAX_PLAYERS];      // 玩家数组
    int      deck[MAX_DECK_SIZE];       // 洗好的牌堆
    int      deck_size;                 // 实际牌堆大小（52 或 104）
    int      deck_top;                  // 当前发牌指针
    int      round_index;               // 局编号（用于日志）
    int      is_finished;               // 本局是否结算完毕
} Round;
```

---

### 2.7 `round/dealer.cpp` — 洗牌发牌层

**职责**：初始化牌堆、执行 Fisher-Yates 洗牌、为每位玩家发 13 张牌。

**关键函数**：

```c
// 根据玩家数决定单/双副牌，初始化 Round.deck
void dealer_init_deck(Round* r);

// Fisher-Yates 原地洗牌（使用 C 标准库 rand/srand）
void dealer_shuffle(Round* r, unsigned int seed);

// 依次为每位玩家发 13 张牌（更新 deck_top）
void dealer_deal_all(Round* r);
```

**实现要点**：
- 单副（≤4 人）：填充 0–51；双副（5–8 人）：填充 0–51 再填充 52–103。
- 洗牌：`for (int i = deck_size-1; i > 0; i--) { int j = rand() % (i+1); swap(deck[i], deck[j]); }`。
- 使用 `<cstdlib>` 的 `rand()` / `srand()`；若需要更高随机质量，可用 `<ctime>` 取时间戳作种子。

---

### 2.8 `round/evaluate.cpp` — 多玩家结算层

**职责**：在所有玩家完成摆牌后，执行头/中/底三墩的两两比较，统计打枪/全垒打，计算并写入每位玩家的本局得分。

**核心逻辑**：

```
对每对玩家 (i, j)（i < j）：
  head_win   = compare_head(players[i], players[j])    // +1 / -1 / 0
  middle_win = compare_five(players[i], players[j], POS_MIDDLE)
  tail_win   = compare_five(players[i], players[j], POS_TAIL)

  净胜墩 = sum(head_win, middle_win, tail_win)
  若 |净胜墩| == 3 → 打枪（BiuBiu）：分数翻倍
  计算水数差并更新 players[i].cumulative_score / players[j].cumulative_score
```

**关键函数**：

```c
// 比较两名玩家同一墩；返回 1(i赢), -1(j赢), 0(平)
int compare_position(const Player* a, const Player* b, int position);

// 执行全局结算，更新所有玩家的 cumulative_score
void evaluate_round(Round* r);

// 检测全垒打：某玩家赢所有其他玩家的所有三墩
int detect_grand_slam(const Round* r, int player_index);
```

**约束**：
- 特殊牌型玩家直接赢过所有未触发特殊牌型的玩家（不逐墩比较）。
- 两位玩家均触发特殊牌型时，按 `rank_order` 高者胜，分数取两者中较大的 `score`。

---

### 2.9 `round/closer.cpp` — 本局收尾层

**职责**：在 `evaluate_round` 完成后，执行收尾工作：记录战绩日志、重置本局临时状态、为下一局做好准备。

**关键函数**：

```c
// 将本局结果格式化输出到 FILE*（可传入 stdout 或文件句柄）
void closer_log_result(const Round* r, FILE* out);

// 清空每位玩家的本局手牌/摆牌，保留累计积分
void closer_reset_players(Round* r);

// 将 Round 恢复到可重新洗牌的初始态
void closer_reset_round(Round* r);
```

**约束**：
- 所有输出使用 `fprintf`（C 标准库），禁止 `std::cout`。
- `closer_log_result` 为纯输出函数，不修改任何状态。

---

## 三、模块依赖关系

```
cards.h  ──────────────────────────────────────────────────────┐
   │                                                            │
   ▼                                                            ▼
score.h ──► pattern.h / pattern.cpp ──► searchPattern.cpp    player.h / player.cpp
                                                  │                    │
                                                  └────────┬───────────┘
                                                           ▼
                                                        round.h
                                                      ┌────┴────┐
                                              dealer.cpp   evaluate.cpp
                                                      └────┬────┘
                                                      closer.cpp
```

**原则**：
- 下层模块（`cards.h`, `score.h`）对上层**零感知**。
- `pattern` 层只依赖 `cards.h` 和 `score.h`。
- `round` 层统一依赖 `player.h` 和 `pattern.h`，不直接操作牌面枚举。

---

## 四、编码规范

### 4.1 内存管理
- **禁止** `new` / `delete` / `malloc` / `free`。
- 所有数组以固定大小在**栈上**声明，使用宏常量（`MAX_PLAYERS`, `MAX_HAND_SIZE`…）控制上界。
- 若未来需要动态结构，统一使用固定大小的对象池（预分配全局数组 + 空闲链表）。

### 4.2 命名规范
| 类型 | 命名风格 | 示例 |
|------|----------|------|
| 结构体 | `PascalCase` + `typedef` | `typedef struct { … } Player;` |
| 函数 | `模块_动词_名词` | `dealer_shuffle`, `player_init` |
| 宏/枚举 | `UPPER_SNAKE_CASE` | `MAX_PLAYERS`, `POS_HEAD` |
| 局部变量 | `lower_snake_case` | `int deck_top;` |

### 4.3 错误处理
- 函数返回 `int`：`0` 为成功，非零为错误码（统一在各模块头文件中定义错误码枚举）。
- 断言使用 `<cassert>` 的 `assert()`，用于开发期不变量检查，Release 构建通过 `-DNDEBUG` 关闭。
- 禁止使用 C++ 异常。

### 4.4 线程安全
- 当前设计为**单线程**执行模型（一局一线程或协程调度）。
- 所有全局状态（查表数组）均为 `const`，天然线程安全只读。
- `rand()` 非线程安全；若未来多线程洗牌，改用 `rand_r()` 传入各线程独立 `seed`。

---

## 五、关键算法伪代码

### 5.1 Fisher-Yates 洗牌

```c
void dealer_shuffle(Round* r, unsigned int seed) {
    srand(seed);
    for (int i = r->deck_size - 1; i > 0; i--) {
        int j = rand() % (i + 1);
        int tmp = r->deck[i];
        r->deck[i] = r->deck[j];
        r->deck[j] = tmp;
    }
}
```

### 5.2 五张牌型识别（核心片段）

```c
PatternResult identify_five(const int cards[5], int position) {
    int ranks[5], suits[5];
    int freq[13] = {0};
    for (int i = 0; i < 5; i++) {
        ranks[i] = card_rank(cards[i]);
        suits[i] = card_suit(cards[i]);
        freq[ranks[i]]++;
    }
    // 排序 ranks 降序（插入排序）
    // 判断同花、顺子、各组合频次 → 返回对应 PatternResult
    ...
}
```

### 5.3 打枪检测

```c
// 若 i 赢得与 j 对局的全部三墩，返回 1
int is_shoot(int head_win, int mid_win, int tail_win) {
    return (head_win == 1 && mid_win == 1 && tail_win == 1) ? 1 : 0;
}
```

---

## 六、测试策略

| 测试级别 | 内容 | 工具 |
|----------|------|------|
| 单元测试 | 每个 `identify_*` 函数使用固定牌组验证输出 | 手写断言 + `assert()` |
| 集成测试 | 完整一局 4 人流程：发牌→摆牌→结算→收尾 | `src/python/test.py` 调用 FFI |
| 边界测试 | 最大 8 人双副牌、至尊清龙、所有人打枪 | 构造极端手牌用例 |
| 性能测试 | `search_best` 在低端 Android 设备上的响应时间 ≤ 50ms | `<ctime>` 计时 |

---

*文档版本：v1.0 · 最后更新：2026-04*