namespace DOL.GS
{
    public class BdMeleeSubPet : BdSubPet
    {
        public BdMeleeSubPet(INpcTemplate npcTemplate) : base(npcTemplate) { }

        private static readonly (CommanderPet.eWeaponType Type, ushort Model)[] Axes =
        {
            (CommanderPet.eWeaponType.OneHandAxe, 578), (CommanderPet.eWeaponType.OneHandAxe, 319),
            (CommanderPet.eWeaponType.TwoHandAxe, 317), (CommanderPet.eWeaponType.TwoHandAxe, 577)
        };

        public override void InitializeActiveWeaponFromInventory()
        {
            // 1.65: one axe, picked at summon: Norse Hand Axe or War Axe, or the Great Axe or 2h battleaxe.
            var (type, model) = Axes[Util.Random(Axes.Length - 1)];
            MinionGetWeapon(type, model);
        }
    }
}
