using System.Collections.Generic;
using DOL.Database;

namespace DOL.GS
{
    /// <summary>
    /// What the client is shown of an NPC's equipment. Necromancer pets used to show private client weapons here (a
    /// blackened mace and shield on the necroservant, a flaming sword on the abomination); in 1.65 only the abomination
    /// carries a weapon (its template's two-handed sword), the other servants nothing (owner 2026-10-13). Every NPC now
    /// shows its own inventory; the hooks stay so the packet code has one place to ask.
    /// </summary>
    public static class NecromancerPetAppearance
    {
        public static bool HasEquipment(GameLiving actor) => actor.Inventory != null;

        public static ICollection<DbInventoryItem> Equipment(GameLiving actor) => actor.Inventory?.VisibleItems;

        public static byte WeaponSlots(GameLiving actor) => actor.VisibleActiveWeaponSlots;

        public static void CombatModels(GameObject attacker, GameObject defender, byte result,
            ref ushort weapon, ref ushort defenseWeapon)
        {
        }
    }
}
