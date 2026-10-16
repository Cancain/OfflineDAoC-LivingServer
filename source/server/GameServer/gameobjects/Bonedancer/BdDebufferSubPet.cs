namespace DOL.GS
{
    public class BdDebufferSubPet : BdSubPet
    {
        public BdDebufferSubPet(INpcTemplate npcTemplate) : base(npcTemplate) { }

        public override void InitializeActiveWeaponFromInventory()
        {
            // 1.65 look (owner 2026-10-13): a Norse Short Sword (311). No period record shows the debuffers' weapon;
            // the short sword is the owner's sheet's choice.
            if (Inventory?.GetItem(eInventorySlot.TwoHandWeapon) is DOL.Database.DbInventoryItem twoHand)
                Inventory.RemoveItem(twoHand);
            MinionGetWeapon(CommanderPet.eWeaponType.OneHandSword, 311);
        }
    }
}
