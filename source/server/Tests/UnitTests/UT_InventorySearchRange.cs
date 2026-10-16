using DOL.Database;
using DOL.GS;
using NUnit.Framework;

namespace DOL.UnitTests
{
    /// <summary>
    /// Quest probe 2026-10-15: a Min_Inv..Max_Inv search of a player's inventory found nothing, because Max_Inv (249, the
    /// last housing slot) is not a valid player slot and the bound was validated to Invalid. Tainted Magic's "have the ale"
    /// step could never complete.
    /// </summary>
    [TestFixture]
    public class UT_InventorySearchRange
    {
        /// <summary>Player-like slot rules: only the backpack is a valid slot.</summary>
        private sealed class BackpackOnlyInventory : GameLivingInventory
        {
            public void Put(eInventorySlot slot, DbInventoryItem item) => m_items[slot] = item;

            protected override eInventorySlot GetValidInventorySlot(eInventorySlot slot) =>
                slot is >= eInventorySlot.FirstBackpack and <= eInventorySlot.LastBackpack ? slot : eInventorySlot.Invalid;
        }

        [Test]
        public void WholeInventorySearchFindsABackpackItem()
        {
            var inventory = new BackpackOnlyInventory();
            var ale = new DbInventoryItem { Id_nb = "cq_ale", Name = "Ale" };
            inventory.Put(eInventorySlot.FirstBackpack, ale);

            Assert.That(inventory.GetFirstItemByID("cq_ale", eInventorySlot.Min_Inv, eInventorySlot.Max_Inv), Is.SameAs(ale));
            Assert.That(inventory.GetFirstItemByName("Ale", eInventorySlot.Min_Inv, eInventorySlot.Max_Inv), Is.SameAs(ale));
            Assert.That(inventory.GetItemRange(eInventorySlot.Min_Inv, eInventorySlot.Max_Inv), Has.Count.EqualTo(1));
            Assert.That(inventory.GetFirstItemByID("cq_ale", eInventorySlot.FirstBackpack, eInventorySlot.LastBackpack), Is.SameAs(ale));
            Assert.That(inventory.GetFirstItemByID("other", eInventorySlot.Min_Inv, eInventorySlot.Max_Inv), Is.Null);
        }
    }
}
