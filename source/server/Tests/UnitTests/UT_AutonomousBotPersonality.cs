using System;
using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using P = DOL.GS.AutonomousBotPersonality;

namespace DOL.GS.Tests
{
    [TestFixture]
    public class UT_AutonomousBotPersonality
    {
        [Test]
        public void Shares_SumToOneHundred()
        {
            Assert.That(P.TypeSharePercent.Sum(), Is.EqualTo(100));
            Assert.That(P.TypeSharePercent.Length, Is.EqualTo(Enum.GetValues<BotPersonalityType>().Length));
        }

        [Test]
        public void TypeFor_FollowsTheSharesAcrossManyBots()
        {
            const int bots = 100_000;
            var counts = new int[P.TypeSharePercent.Length];
            for (long id = 1; id <= bots; id++)
                counts[(int)P.TypeFor(id)]++;
            for (int index = 0; index < counts.Length; index++)
                Assert.That(counts[index] * 100.0 / bots, Is.EqualTo(P.TypeSharePercent[index]).Within(0.6),
                    ((BotPersonalityType)index).ToString());
        }

        [Test]
        public void Personality_IsFixedById_AndConsecutiveIdsVary()
        {
            Assert.That(P.For(4242), Is.EqualTo(P.For(4242)));
            Assert.That(Enumerable.Range(1, 40).Select(id => P.TypeFor(id)).Distinct().Count(), Is.GreaterThanOrEqualTo(4),
                "Bots created one after another shouldn't share a type.");
        }

        [Test]
        public void Traits_StayInZeroToNine_AndDifferByType()
        {
            var all = Enumerable.Range(1, 20_000).Select(id => P.For(id)).ToArray();
            foreach (BotPersonality personality in all)
            {
                BotPersonalityTraits t = personality.Traits;
                foreach (int value in new[] { t.Curiosity, t.Risk, t.Sociability, t.Patience, t.Chattiness })
                    Assert.That(value, Is.InRange(0, 9));
            }
            double Average(BotPersonalityType type, Func<BotPersonalityTraits, int> trait) =>
                all.Where(p => p.Type == type).Average(p => trait(p.Traits));
            Assert.That(Average(BotPersonalityType.Daredevil, t => t.Risk), Is.GreaterThan(Average(BotPersonalityType.Crafter, t => t.Risk) + 4));
            Assert.That(Average(BotPersonalityType.Explorer, t => t.Curiosity), Is.GreaterThan(Average(BotPersonalityType.Leveler, t => t.Curiosity) + 4));
            Assert.That(Average(BotPersonalityType.Socialite, t => t.Sociability), Is.GreaterThan(Average(BotPersonalityType.Explorer, t => t.Sociability) + 3));
        }

        [Test]
        public void TownBreaks_SocialitesLinger_LevelersBarelyStop()
        {
            BotPersonality Typical(BotPersonalityType type) => new(type, new BotPersonalityTraits(5, 5, 5, 5, 5));
            Assert.That(P.TownBreakChance(Typical(BotPersonalityType.Socialite)), Is.GreaterThan(P.TownBreakChance(Typical(BotPersonalityType.Leveler)) * 3));
            Assert.That(P.TownBreakLengthFactor(Typical(BotPersonalityType.Socialite)), Is.GreaterThan(1));
            Assert.That(P.TownBreakLengthFactor(Typical(BotPersonalityType.Leveler)), Is.LessThan(1));
            foreach (BotPersonality personality in Enumerable.Range(1, 5_000).Select(id => P.For(id)))
                Assert.That(P.TownBreakChance(personality), Is.InRange(0.03, 0.45));
        }

        [Test]
        public void TownBreakMix_StaysNearTodaysAverage()
        {
            // Today every bot has 15%. The mix of types should land in the same neighborhood, so personalities
            // reshuffle who takes breaks rather than emptying or flooding the towns.
            double average = Enumerable.Range(1, 50_000).Average(id => P.TownBreakChance(P.For(id)));
            Assert.That(average, Is.InRange(0.12, 0.20));
        }

        [Test]
        public void GoalTilt_OnlyRedraws_NeverForces()
        {
            foreach (BotPersonalityType type in Enum.GetValues<BotPersonalityType>())
            foreach (eAutonomousObjectiveKind kind in Enum.GetValues<eAutonomousObjectiveKind>())
                Assert.That(P.RedrawChance(new BotPersonality(type, default), kind), Is.InRange(0.0, 0.6));
            Assert.That(P.RedrawChance(new BotPersonality(BotPersonalityType.Socialite, default), eAutonomousObjectiveKind.SoloPve), Is.GreaterThan(0));
            Assert.That(P.RedrawChance(new BotPersonality(BotPersonalityType.Socialite, default), eAutonomousObjectiveKind.GroupPve), Is.Zero);
        }

        [Test]
        public void ChooseGoal_WithoutAPersonalityBot_IsTheFirstDraw()
        {
            int draws = 0;
            eAutonomousObjectiveKind result = P.ChooseGoal(null, () => { draws++; return eAutonomousObjectiveKind.SoloPve; });
            Assert.That(result, Is.EqualTo(eAutonomousObjectiveKind.SoloPve));
            Assert.That(draws, Is.EqualTo(1), "Off (or not a gamebot): exactly today's single draw.");
        }

        [Test]
        public void CampWeights_DaredevilsLikeHardCons_ExplorersLikeFreshZones_NeverZero()
        {
            var daredevil = new BotPersonality(BotPersonalityType.Daredevil, new BotPersonalityTraits(5, 8, 5, 3, 5));
            var crafter = new BotPersonality(BotPersonalityType.Crafter, new BotPersonalityTraits(3, 1, 5, 7, 5));
            var explorer = new BotPersonality(BotPersonalityType.Explorer, new BotPersonalityTraits(9, 5, 4, 5, 5));
            Assert.That(P.CampWeightPercent(daredevil, ConColor.ORANGE, false, 3), Is.GreaterThan(P.CampWeightPercent(daredevil, ConColor.BLUE, false, 3) * 2));
            Assert.That(P.CampWeightPercent(crafter, ConColor.ORANGE, false, 3), Is.LessThan(P.CampWeightPercent(crafter, ConColor.BLUE, false, 3)));
            Assert.That(P.CampWeightPercent(explorer, ConColor.BLUE, true, 3), Is.GreaterThan(P.CampWeightPercent(explorer, ConColor.BLUE, false, 3) * 4));
            foreach (BotPersonality personality in Enumerable.Range(1, 2_000).Select(id => P.For(id)))
            foreach (ConColor con in new[] { ConColor.GREEN, ConColor.BLUE, ConColor.YELLOW, ConColor.ORANGE })
                Assert.That(P.CampWeightPercent(personality, con, false, 1), Is.GreaterThanOrEqualTo(10), "Every legal camp stays possible.");
        }

        [Test]
        public void OutdoorDrawWeight_WithoutTaste_IsTodaysSpawnWeight()
        {
            var camp = new AutonomousBotDecisionEngine.Camp("c", "Zone", "monster", eRealm.Albion, 1, ConColor.BLUE, ConColor.BLUE,
                true, false, false, 4, 10, 5.0);
            Assert.That(AutonomousBotDecisionEngine.OutdoorDrawWeight(camp, null), Is.EqualTo(AutonomousBotDecisionEngine.OutdoorSpawnWeight(camp)));
            Assert.That(AutonomousBotDecisionEngine.OutdoorDrawWeight(camp, _ => 250), Is.EqualTo(AutonomousBotDecisionEngine.OutdoorSpawnWeight(camp) * 250));
        }

        [Test]
        public void DungeonPreference_UnchangedAtOneHundred()
        {
            Assert.That(P.DungeonPreferencePercent(new BotPersonality(BotPersonalityType.Socialite, default)), Is.EqualTo(100));
            Assert.That(P.DungeonPreferencePercent(new BotPersonality(BotPersonalityType.Daredevil, default)), Is.GreaterThan(100));
            Assert.That(P.DungeonPreferencePercent(new BotPersonality(BotPersonalityType.Crafter, default)), Is.LessThan(100));
        }

        [Test]
        public void ChatRate_ScalesWithChattiness()
        {
            Assert.That(P.ChatRateFactor(new BotPersonality(BotPersonalityType.Socialite, new BotPersonalityTraits(0, 0, 0, 0, 9))),
                Is.GreaterThan(P.ChatRateFactor(new BotPersonality(BotPersonalityType.Leveler, new BotPersonalityTraits(0, 0, 0, 0, 1))) * 3));
            double average = Enumerable.Range(1, 20_000).Average(id => P.ChatRateFactor(P.For(id)));
            Assert.That(average, Is.InRange(0.85, 1.25), "On average the realm talks about as much as today.");
        }

        [Test]
        public void ZoneMemory_FreshUntilVisited_FreshAgainAfterSixHours()
        {
            const long botId = -777;
            DateTime now = new(2026, 10, 12, 12, 0, 0, DateTimeKind.Utc);
            Assert.That(P.IsZoneFresh(botId, "Camelot Hills", now), Is.True);
            P.RememberZoneAt(botId, "Camelot Hills", now);
            Assert.That(P.IsZoneFresh(botId, "camelot hills", now.AddHours(1)), Is.False);
            Assert.That(P.IsZoneFresh(botId, "Camelot Hills", now.AddHours(7)), Is.True);
            for (int zone = 0; zone < P.ZoneMemoryCapacity + 5; zone++)
                P.RememberZoneAt(botId, $"Zone {zone}", now.AddMinutes(zone + 1));
            Assert.That(P.IsZoneFresh(botId, "Camelot Hills", now.AddMinutes(30)), Is.True, "The oldest zone is forgotten past capacity.");
        }
        [Test]
        public void GoalAffinities_AreAllPositive_SoEverySlotCanStillBeFilled()
        {
            foreach (BotPersonalityType type in Enum.GetValues<BotPersonalityType>())
            foreach (eAutonomousObjectiveKind kind in Enum.GetValues<eAutonomousObjectiveKind>())
                Assert.That(P.GoalAffinity(type, kind), Is.GreaterThan(0), $"{type} {kind}");
        }

        private static BotPersonalityType?[] Population(int size)
        {
            var types = new BotPersonalityType?[size];
            int index = 0;
            for (int t = 0; t < P.TypeSharePercent.Length; t++)
                for (int n = 0; n < P.TypeSharePercent[t] * size / 100; n++)
                    types[index++] = (BotPersonalityType)t;
            return types;
        }

        /// <summary>
        /// The allocator with personalities (review of goals, 2026-10-17): the owner's mix still sets exactly how many
        /// bots get each goal; personality decides who. RvR goes mostly to No-lifers and Daredevils, groups to
        /// Socialites, and Crafters rarely see RvR.
        /// </summary>
        [Test]
        public void PlanGoals_KeepsTheMixExactly_ButPersonalityDecidesWho()
        {
            var random = new Random(2026);
            BotPersonalityType?[] types = Population(1000);
            var plan = P.PlanGoals(types, new bool[1000], 400, 400, 200, 0, random);
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.SoloPve), Is.EqualTo(400));
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.GroupPve), Is.EqualTo(400));
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.RvR), Is.EqualTo(200));
            double Rate(BotPersonalityType type, eAutonomousObjectiveKind kind) =>
                (double)Enumerable.Range(0, 1000).Count(i => types[i] == type && plan[i] == kind) / types.Count(t => t == type);
            TestContext.Out.WriteLine(string.Join("; ", Enum.GetValues<BotPersonalityType>().Select(type =>
                $"{type}: solo {Rate(type, eAutonomousObjectiveKind.SoloPve):P0} group {Rate(type, eAutonomousObjectiveKind.GroupPve):P0} rvr {Rate(type, eAutonomousObjectiveKind.RvR):P0}")));
            Assert.That(Rate(BotPersonalityType.NoLifer, eAutonomousObjectiveKind.RvR), Is.GreaterThan(0.45));
            Assert.That(Rate(BotPersonalityType.Daredevil, eAutonomousObjectiveKind.RvR), Is.GreaterThan(0.45));
            Assert.That(Rate(BotPersonalityType.Crafter, eAutonomousObjectiveKind.RvR), Is.LessThan(0.08));
            Assert.That(Rate(BotPersonalityType.Socialite, eAutonomousObjectiveKind.GroupPve),
                Is.GreaterThan(Rate(BotPersonalityType.Socialite, eAutonomousObjectiveKind.SoloPve) * 3));
            Assert.That(Rate(BotPersonalityType.Leveler, eAutonomousObjectiveKind.SoloPve),
                Is.GreaterThan(Rate(BotPersonalityType.Leveler, eAutonomousObjectiveKind.GroupPve)));
        }

        [Test]
        public void PlanGoals_SharesASmallPoolInProportion_AndLeavesExtraBotsToTheUsualRule()
        {
            var random = new Random(7);
            var small = P.PlanGoals(Population(100), new bool[100], 400, 400, 200, 0, random);
            Assert.That(small.Count(k => k == eAutonomousObjectiveKind.SoloPve), Is.EqualTo(40));
            Assert.That(small.Count(k => k == eAutonomousObjectiveKind.GroupPve), Is.EqualTo(40));
            Assert.That(small.Count(k => k == eAutonomousObjectiveKind.RvR), Is.EqualTo(20));
            var large = P.PlanGoals(Population(100), new bool[100], 10, 5, 5, 0, random);
            Assert.That(large.Count(k => k == null), Is.EqualTo(80), "bots beyond the open slots keep the allocator's own rule");
        }

        [Test]
        public void PlanGoals_GivesBattlegroundsOnlyToBotsThatCanGo_AndTreatsNoPersonalityAsNeutral()
        {
            var random = new Random(9);
            var types = new BotPersonalityType?[50];
            bool[] can = Enumerable.Range(0, 50).Select(i => i < 10).ToArray();
            var plan = P.PlanGoals(types, can, 30, 10, 0, 25, random);
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.Battleground), Is.EqualTo(10), "only 10 bots fit a bracket");
            Assert.That(Enumerable.Range(10, 40).All(i => plan[i] != eAutonomousObjectiveKind.Battleground), Is.True);
        }
        /// <summary>
        /// The allocator's RvR pass (review 2026-10-17): planned bots first, then the rest with the old over-quota draw on
        /// live counters. 100 bots, 20 open RvR slots and nothing else open: exactly 20 RvR. This test copies the loop of
        /// AutonomousObjectiveAssignments (its RvR-pass fallback draw included); keep the two in step.
        /// </summary>
        [Test]
        public void ThePass_NeverRunsAGoalOverItsNumber()
        {
            for (int seed = 0; seed < 50; seed++)
            {
                var random = new Random(seed);
                var plan = P.PlanGoals(Population(100), new bool[100], 0, 0, 20, 0, random);
                // Solo and group are already full (locked bots): only the 20 RvR slots are open.
                var target = new AutonomousObjectiveAssignments.Allocation(40, 40, 20);
                int solo = 40, group = 40, rvr = 0;
                foreach (int i in P.PlannedFirst(plan))
                {
                    int rvrNeeded = Math.Max(0, target.RvR - rvr);
                    int soloNeeded = Math.Max(0, target.SoloPve - solo);
                    int groupNeeded = Math.Max(0, target.GroupPve - group);
                    eAutonomousObjectiveKind kind = plan[i] ?? (rvrNeeded > 0 && random.Next(rvrNeeded + soloNeeded + groupNeeded) < rvrNeeded
                        ? eAutonomousObjectiveKind.RvR
                        : AutonomousObjectiveAssignments.ChoosePveObjective(target, solo, group, random));
                    if (kind == eAutonomousObjectiveKind.RvR) rvr++;
                    else if (kind == eAutonomousObjectiveKind.SoloPve) solo++;
                    else group++;
                }
                Assert.That(rvr, Is.EqualTo(20), $"seed {seed}");
            }
        }

        [Test]
        public void PlannedFirst_PutsPlannedBotsFirstAndKeepsPoolOrder()
        {
            var plan = new eAutonomousObjectiveKind?[] { null, eAutonomousObjectiveKind.RvR, null, eAutonomousObjectiveKind.SoloPve };
            Assert.That(P.PlannedFirst(plan), Is.EqualTo(new[] { 1, 3, 0, 2 }));
            Assert.That(P.PlannedFirst(new eAutonomousObjectiveKind?[4]), Is.EqualTo(new[] { 0, 1, 2, 3 }), "personalities off: pool order");
        }

        [Test]
        public void PlanGoals_DrawsBattlegroundsBeforeRvR_SoBracketBotsArentUsedUp()
        {
            var random = new Random(11);
            var types = Enumerable.Repeat<BotPersonalityType?>(BotPersonalityType.NoLifer, 20).ToArray();
            bool[] can = Enumerable.Range(0, 20).Select(i => i < 5).ToArray();
            var plan = P.PlanGoals(types, can, 0, 0, 15, 5, random);
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.Battleground), Is.EqualTo(5));
            Assert.That(plan.Count(k => k == eAutonomousObjectiveKind.RvR), Is.EqualTo(15));
        }
    }
}
