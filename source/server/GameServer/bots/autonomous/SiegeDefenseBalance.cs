using System;
using System.Collections.Generic;
using System.Linq;

namespace DOL.GS;

/// <summary>
/// Keeps bot sieges contested (owner, 2026-10-19: endgame fights should be won about two times in three, never a
/// sure thing). The last sieges' results nudge the defenders' share: attackers winning nearly every one adds up to
/// 0.25 to rvr_siege_defense_share, attackers losing most of them takes up to 0.25 away. In memory only.
/// </summary>
public static class SiegeDefenseBalance
{
    public const int Window = 6;
    public const int MinimumResults = 3;
    public const double Step = 0.125;
    public const double MaximumShift = 0.25;
    /// <summary>Attacker win share above which defenders get more, and below which they get fewer.</summary>
    public const double HighWinShare = 0.8, LowWinShare = 0.45;

    private static readonly object Sync = new();
    private static readonly Queue<bool> Results = new();
    private static double _shift;

    /// <summary>Records a finished siege and moves the shift one step when the window says so.</summary>
    public static void Record(bool attackerWon)
    {
        lock (Sync)
        {
            Results.Enqueue(attackerWon);
            while (Results.Count > Window) Results.Dequeue();
            _shift = NextShift(_shift, Results.ToArray());
        }
    }

    public static double NextShift(double shift, IReadOnlyCollection<bool> results)
    {
        if (results == null || results.Count < MinimumResults) return shift;
        double share = results.Count(won => won) / (double)results.Count;
        if (share > HighWinShare) shift += Step;
        else if (share < LowWinShare) shift -= Step;
        return Math.Clamp(shift, -MaximumShift, MaximumShift);
    }

    public static double Ratio(double baseRatio)
    {
        lock (Sync) return Math.Clamp(baseRatio + _shift, 0.25, 2.0);
    }

    /// <summary>Tests only.</summary>
    public static void Reset()
    {
        lock (Sync) { Results.Clear(); _shift = 0; }
    }
}
