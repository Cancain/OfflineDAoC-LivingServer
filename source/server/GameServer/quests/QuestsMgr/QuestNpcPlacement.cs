using System;

namespace DOL.GS.Quests
{
    /// <summary>
    /// How scripted quests find their NPCs in the world. The scripts used to accept only an NPC at one
    /// exact X/Y. The classic quest world (0.35) placed several of the same NPCs a few units away
    /// (Brigit in Tir na Nog, Danica and Elizabeth in Mularn), and some scripts look at a spot other than
    /// where they create the NPC; the script then spawned a twin beside the world NPC. Only the twin
    /// answered the epic quest's whispers and gave its rewards, so players talking to the other one found
    /// the epic dead. A same-named NPC of the realm in the region within SearchRadius is the quest's NPC.
    /// </summary>
    public static class QuestNpcPlacement
    {
        public const int SearchRadius = 3000;

        public static bool IsAt(GameNPC npc, ushort region, int x, int y) =>
            npc != null && npc.CurrentRegionID == region &&
            Math.Abs(npc.X - x) <= SearchRadius && Math.Abs(npc.Y - y) <= SearchRadius;
    }
}
