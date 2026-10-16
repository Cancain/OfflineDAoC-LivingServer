using DOL.Database;
using DOL.GS.Spells;

namespace DOL.GS.RealmAbilities
{
    /// <summary>
    /// Crippling Plague, the Sluaghbinder's class realm ability (owner 2026-10-13): an instant plague on one enemy that
    /// slows it a little at first and more every second, until after 10 seconds it can hardly move; then it bursts and
    /// poisons everyone near it. 1 minute recast. Look and animation are not decided yet: the cast shows the Plague
    /// Spores cloud the Sluaghbinder's Bane spells use, and the burst the Circle of Rage blast.
    /// </summary>
    public class AtlasOF_CripplingPlague : TimedRealmAbility, ISpellCastingAbilityHandler
    {
        public AtlasOF_CripplingPlague(DbAbility dba, int level) : base(dba, level) { }

        public Spell Spell => m_spell;
        public SpellLine SpellLine => m_spellline;
        public Ability Ability => this;

        public const int Range = 1500;
        public const int DurationSeconds = 10;
        public const int ReuseSeconds = 60;
        public const int Icon = 3425;
        public const int CastEffect = 3425;

        private Spell m_spell;
        private SpellLine m_spellline;

        public override int MaxLevel => 1;
        public override int CostForUpgrade(int level) => 10;
        public override int GetReUseDelay(int level) => ReuseSeconds;

        private void CreateSpell(GamePlayer caster)
        {
            DbSpell dbSpell = new()
            {
                Name = "Crippling Plague",
                Icon = Icon,
                ClientEffect = CastEffect,
                Target = eSpellTarget.ENEMY.ToString(),
                Range = Range,
                Type = eSpellType.SluaghbinderCripplingPlague.ToString(),
                Value = CripplingPlagueECSEffect.EndSlowPercent,
                Duration = DurationSeconds,
                Frequency = 1000,
                Damage = 0,
                DamageType = (int) eDamageType.Body,
                CastTime = 0,
                Power = 0,
                RecastDelay = GetReUseDelay(0), // The spell code disables the ability for this long.
                Description = $"An instant plague slows the target by {CripplingPlagueECSEffect.StartSlowPercent}%, rising every second " +
                              $"to {CripplingPlagueECSEffect.EndSlowPercent}% over {DurationSeconds} seconds; then it bursts, dealing " +
                              $"{CripplingPlagueECSEffect.BurstDamage} poison damage to enemies within {CripplingPlagueECSEffect.BurstRadius} " +
                              "units of the target. Curing the plague first stops the burst."
            };
            m_spell = new Spell(dbSpell, caster.Level);
            m_spellline = GlobalSpellsLines.RealmSpellsSpellLine;
        }

        public override void Execute(GameLiving living)
        {
            if (CheckPreconditions(living, DEAD | SITTING | MEZZED | STUNNED))
                return;

            if (living is not GamePlayer caster || caster.castingComponent == null)
                return;

            CreateSpell(caster);
            caster.CastSpell(m_spell, m_spellline, this);
            // The spell code disables this ability when the cast finishes (SpellHandler.FinishSpellcast).
        }
    }
}
