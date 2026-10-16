using System.Numerics;

namespace DOL.GS;

/// <summary>
/// A marching army that has stood in one place too long pushes on. Run 12 (2026-10-15): Midgard's relic army for Dun
/// Dagda fought Hibernian defenders on a ridge in Emain Macha for 40+ minutes without moving (the leader joined every
/// fight of the column, most of the enemies stood 650-1,000 units below and could not be reached, and a fighting leader
/// stays leader). When the leader has moved less than <see cref="StallDistance"/> in <see cref="StallMilliseconds"/>,
/// the column marches on for <see cref="PushMilliseconds"/>: the leader drops its fight and walks, the others only
/// fight enemies attacking them directly.
/// </summary>
public static class AutonomousArmyPush
{
    public const float StallDistance = 2_000f;
    public const long StallMilliseconds = 4 * 60_000;
    public const long PushMilliseconds = 2 * 60_000;

    public struct State
    {
        public Vector2 Anchor;
        public long Since;
        public long PushUntil;
    }

    /// <summary>Updates the leader's progress; true while the column is pushing. <paramref name="started"/> is true on the turn a push begins.</summary>
    public static bool Update(ref State state, Vector2 here, long now, out bool started)
    {
        started = false;
        if (state.Since == 0 || Vector2.Distance(here, state.Anchor) > StallDistance)
        {
            state.Anchor = here;
            state.Since = now;
        }
        else if (now >= state.PushUntil && now - state.Since >= StallMilliseconds)
        {
            state.PushUntil = now + PushMilliseconds;
            state.Anchor = here;
            state.Since = now;
            started = true;
        }
        return now < state.PushUntil;
    }
}
