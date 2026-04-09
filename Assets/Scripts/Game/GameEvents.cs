using System;

public static class GameEvents
{
    public static Action? OnDealDone;
    public static Action<int>? OnShoot;
    public static Action<int>? OnHomerun;
    public static Action<int[]>? OnRoundDone;
}
