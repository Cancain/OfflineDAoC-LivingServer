using System;
using DOL.Database;

namespace DOL.GS.Spells
{
    /// <summary>
    /// The Sluaghbinder's Crippling Plague (realm ability AtlasOF_CripplingPlague): a snare that starts weak and
    /// tightens every second, then bursts with poison. It is a snare in every rule that matters (snare and CC
    /// immunity, Speed of Sound, snare immunity afterwards, cures), through <see cref="SpeedDecreaseSpellHandler"/>.
    /// </summary>
    [SpellHandler(eSpellType.SluaghbinderCripplingPlague)]
    public class CripplingPlagueSpellHandler : SpeedDecreaseSpellHandler
    {
        public override string ShortDescription =>
            $"The target is slowed by {CripplingPlagueECSEffect.StartSlowPercent}%, rising to {CripplingPlagueECSEffect.EndSlowPercent}% " +
            $"over {Spell.Duration / 1000} seconds, then the plague bursts for {CripplingPlagueECSEffect.BurstDamage} poison damage around it.";

        public CripplingPlagueSpellHandler(GameLiving caster, Spell spell, SpellLine line) : base(caster, spell, line) { }

        public override ECSGameSpellEffect CreateECSEffect(in ECSGameEffectInitParams initParams)
        {
            return ECSGameEffectFactory.Create(initParams, static (in i) => new CripplingPlagueECSEffect(i));
        }

        // The ramp is the plague: a critical or a duration reduction would change its shape, so it always runs whole.
        protected override int CalculateEffectDuration(GameLiving target) => Spell.Duration;

        protected override double GetDebuffEffectivenessCriticalModifier() => 1.0;
    }

    public class CripplingPlagueECSEffect : ECSGameSpellEffect
    {
        public const int StartSlowPercent = 10;
        public const int EndSlowPercent = 95;
        public const int BurstDamage = 150;
        public const int BurstRadius = 250;
        public const int BurstEffect = 11115;

        private bool _expired;

        public CripplingPlagueECSEffect(in ECSGameEffectInitParams initParams) : base(initParams)
        {
            // Not a decaying snare (Spell.IsSnare): it ticks once a second and tightens instead.
            TriggersImmunity = true;
        }

        /// <summary>The slow at this moment: from StartSlowPercent at the start to EndSlowPercent at the end.</summary>
        public static double SlowAt(double elapsedFraction) =>
            StartSlowPercent + (EndSlowPercent - StartSlowPercent) * Math.Clamp(elapsedFraction, 0, 1);

        private void ApplySlow()
        {
            double elapsed = Duration > 0 ? (double) (Duration - GetRemainingTimeForClient()) / Duration : 1;
            Owner.BuffBonusMultCategory1.Set((int) eProperty.MaxSpeed, this, 1.0 - SlowAt(elapsed) * 0.01);
            Owner.OnMaxSpeedChange();
        }

        public override void OnStartEffect()
        {
            base.OnStartEffect();
            ApplySlow();
            OnEffectStartsMsg(true, true, true);
        }

        public override void OnEffectPulse()
        {
            ApplySlow();
            if (GetRemainingTimeForClient() <= 0)
                _expired = true;
        }

        public override void OnStopEffect()
        {
            Owner.BuffBonusMultCategory1.Remove((int) eProperty.MaxSpeed, this);
            Owner.OnMaxSpeedChange();
            OnEffectExpiresMsg(true, false, true);
            // It bursts when it runs its course on a living target; a cure (or the target's death) ends it quietly.
            if ((_expired || GameLoop.GameLoopTime >= ExpireTick) && Owner.IsAlive)
                Burst();
        }

        private void Burst()
        {
            GameLiving caster = SpellHandler.Caster;
            if (caster == null || !caster.IsAlive || caster.ObjectState != GameObject.eObjectState.Active ||
                caster.CurrentRegionID != Owner.CurrentRegionID)
                return;
            DbSpell dbSpell = new()
            {
                Name = "Crippling Plague Burst",
                Icon = SpellHandler.Spell.Icon,
                ClientEffect = BurstEffect,
                Target = eSpellTarget.ENEMY.ToString(),
                Type = eSpellType.DirectDamage.ToString(),
                Damage = BurstDamage,
                DamageType = (int) eDamageType.Body,
                Radius = BurstRadius,
                Range = 0,
                Duration = 0,
                CastTime = 0,
                Power = 0
            };
            // Level 0 keeps the damage as written (no spec scaling), as the other realm ability blasts do.
            Spell burst = new(dbSpell, 0);
            ISpellHandler handler = ScriptMgr.CreateSpellHandler(caster, burst, SpellHandler.SpellLine);
            handler?.StartSpell(Owner);
        }
    }
}
