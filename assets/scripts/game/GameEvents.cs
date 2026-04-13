// Scripts/Game/GameEvents.cs
// 静态事件总线，解耦 GameSession 与 UI / VFX 组件。
// 所有事件在 GameSession 中触发，UI 组件订阅，不反向依赖。

using System;

public static class GameEvents
{
    // ── 局面流程事件 ─────────────────────────────────────────────────────────
    /// <summary>发牌完成，所有玩家已收到手牌。</summary>
    public static event Action OnDealDone;

    /// <summary>倒计时开始，参数为秒数。</summary>
    public static event Action<float> OnTimerStart;

    /// <summary>倒计时每 tick 更新，参数为剩余秒数。</summary>
    public static event Action<float> OnTimerTick;

    /// <summary>本机玩家提交三墩成功。</summary>
    public static event Action OnMyHandSubmitted;

    /// <summary>所有玩家提交完毕，开始翻牌。</summary>
    public static event Action OnRevealStart;

    /// <summary>一局结算完成，参数为所有座位净水数。</summary>
    public static event Action<int[]> OnRoundDone;

    // ── 成就特效事件 ─────────────────────────────────────────────────────────
    /// <summary>打枪，参数为赢家座位索引。</summary>
    public static event Action<int> OnShoot;

    /// <summary>全垒打，参数为赢家座位索引。</summary>
    public static event Action<int> OnHomerun;

    // ── 本机交互状态事件 ─────────────────────────────────────────────────────
    /// <summary>本机某张手牌选中状态变化，参数为牌索引和新状态。</summary>
    public static event Action<int, bool> OnCardSelectionChanged;

    /// <summary>某墩位内容变化，参数为墩位索引（0=头 1=中 2=尾）。</summary>
    public static event Action<int> OnPileChanged;

    /// <summary>AI 一键理牌推荐就绪，参数为推荐的 combo 索引。</summary>
    public static event Action<int> OnAIRecommendReady;

    // ── 内部触发方法（只有 GameSession 调用，外部只 += / -=）──────────────
    internal static void FireDealDone()                   => OnDealDone?.Invoke();
    internal static void FireTimerStart(float secs)       => OnTimerStart?.Invoke(secs);
    internal static void FireTimerTick(float remaining)   => OnTimerTick?.Invoke(remaining);
    internal static void FireMyHandSubmitted()            => OnMyHandSubmitted?.Invoke();
    internal static void FireRevealStart()                => OnRevealStart?.Invoke();
    internal static void FireRoundDone(int[] scores)      => OnRoundDone?.Invoke(scores);
    internal static void FireShoot(int seat)              => OnShoot?.Invoke(seat);
    internal static void FireHomerun(int seat)            => OnHomerun?.Invoke(seat);
    internal static void FireCardSelectionChanged(int i, bool sel) => OnCardSelectionChanged?.Invoke(i, sel);
    internal static void FirePileChanged(int pos)         => OnPileChanged?.Invoke(pos);
    internal static void FireAIRecommendReady(int idx)    => OnAIRecommendReady?.Invoke(idx);
}
