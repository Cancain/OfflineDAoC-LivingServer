using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using DOL.Logging;

namespace DOL.GS
{
    /// <summary>
    /// SERVER_HOLDER_CENSUS (test runs only, with runtime\server\memory-census.on): what still references NPCs that have
    /// left the world. Overnight run of 2026-10-20/21: 2,305 deleted bots (and their pets) stayed in memory after full
    /// collections, about 400 more an hour, while the live heap grew about 65 MB an hour; dotnet-gcdump samples too little
    /// of a heap this size to show it (2026-10-13/14).
    ///
    /// A depth-first walk over object fields, from every static field of the server assembly and from every active
    /// autonomous bot, treating each game object as a leaf: a left-the-world NPC reached this way is reported with the
    /// path of fields that holds it (array indices collapsed). Runs on its own background thread, at most once an hour,
    /// within a visit and time budget; it reads fields without locks, so a path seen mid-change can be missed.
    /// </summary>
    public static class ServerHolderCensus
    {
        private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);

        public const int FirstRunMinutes = 20;
        public const int IntervalMinutes = 60;
        // First run on ba3cc93 (2026-10-21 03:59): 3 million visits took one second and reached only 194 of 2,246 held
        // NPCs, with the active bots (walked last) never reached. The visited set is the cost: about 25 bytes an object.
        public const int MaxVisits = 25_000_000;
        public const int MaxVisitsPerRoot = 6_000_000;
        public const int MaxDepth = 24;
        public static readonly TimeSpan TimeBudget = TimeSpan.FromSeconds(150);

        private static long _nextRunTicks;
        private static int _running;

        private const BindingFlags InstanceFields = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly;
        private static readonly Dictionary<Type, FieldInfo[]> FieldCache = new();
        private static readonly Dictionary<Type, bool> StructHoldsReferences = new();

        public static void MaybeRun(Func<List<GameNPC>> detached, Func<List<GameNPC>> activeNpcs = null)
        {
            long now = Stopwatch.GetTimestamp();
            if (_nextRunTicks == 0) _nextRunTicks = now + FirstRunMinutes * 60 * Stopwatch.Frequency;
            if (now < _nextRunTicks || Interlocked.Exchange(ref _running, 1) == 1) return;
            _nextRunTicks = now + IntervalMinutes * 60 * Stopwatch.Frequency;
            var thread = new Thread(() =>
            {
                try { Run(detached(), activeNpcs?.Invoke()); }
                catch (Exception exception) { Log.Warn("SERVER_HOLDER_CENSUS failed", exception); }
                finally { Volatile.Write(ref _running, 0); }
            }) { IsBackground = true, Priority = ThreadPriority.BelowNormal, Name = "HolderCensus" };
            thread.Start();
        }

        private sealed class PathNode(string name, PathNode parent)
        {
            public readonly string Name = name;
            public readonly PathNode Parent = parent;
        }

        public sealed record Result(int Targets, int Reached, int Roots, int Visits, int TruncatedRoots, bool OutOfBudget, double Seconds,
            IReadOnlyList<(string Path, int Count, string Types)> Holders, IReadOnlyList<(string Root, int Visits)> HeaviestRoots = null,
            IReadOnlyList<(string Type, int Count)> Unreached = null);

        /// <summary>
        /// SERVER_ORPHAN_TIMERS and SERVER_ORPHAN_EFFECTS: game timers still running and effects still ticking for objects
        /// no longer in the world, by callback and by effect (first full holder census, 2026-10-21: 1,181 left-the-world
        /// NPCs were held by TimerService and about 250 by EffectService).
        /// </summary>
        public static void LogOrphans()
        {
            static object PrivateList(object service) =>
                service?.GetType().GetField("_list", BindingFlags.Instance | BindingFlags.NonPublic)?.GetValue(service);
            var timers = new Dictionary<string, int>();
            if (PrivateList(TimerService.Instance) is List<ECSGameTimer> timerList)
                foreach (ECSGameTimer timer in timerList.ToArray())
                {
                    if (timer == null || !timer.IsAlive || timer.Owner == null || timer.Owner.ObjectState == GameObject.eObjectState.Active) continue;
                    MethodInfo method = timer.CallbackInfo;
                    string key = $"{method?.DeclaringType?.Name}.{method?.Name}/{timer.Owner.GetType().Name}:{timer.Owner.ObjectState}";
                    timers[key] = timers.GetValueOrDefault(key) + 1;
                }
            var effects = new Dictionary<string, int>();
            if (PrivateList(EffectService.Instance) is List<ECSGameEffect> effectList)
                foreach (ECSGameEffect effect in effectList.ToArray())
                {
                    if (effect?.Owner == null || effect.Owner.ObjectState == GameObject.eObjectState.Active) continue;
                    string spell = null;
                    try { spell = effect.SpellHandler?.Spell?.Name; } catch { }
                    string key = $"{effect.GetType().Name}/{effect.EffectType}/{spell ?? "-"}/{effect.Owner.GetType().Name}:{effect.Owner.ObjectState}";
                    effects[key] = effects.GetValueOrDefault(key) + 1;
                }
            Log.Info($"SERVER_ORPHAN_TIMERS total={timers.Values.Sum()} byCallback=\"{string.Join(",", timers.OrderByDescending(p => p.Value).Take(12).Select(p => $"{p.Key}={p.Value}"))}\"");
            Log.Info($"SERVER_ORPHAN_EFFECTS total={effects.Values.Sum()} byEffect=\"{string.Join(",", effects.OrderByDescending(p => p.Value).Take(12).Select(p => $"{p.Key}={p.Value}"))}\"");
        }

        private static void Run(List<GameNPC> detachedNpcs, List<GameNPC> activeNpcs)
        {
            Result result = Scan(Roots(activeNpcs), detachedNpcs.Take(200_000));
            if (result.Targets == 0) return;
            Log.Info($"SERVER_HOLDER_CENSUS targets={result.Targets} reached={result.Reached} unreached={result.Targets - result.Reached} " +
                     $"roots={result.Roots} visits={result.Visits} truncatedRoots={result.TruncatedRoots} outOfBudget={result.OutOfBudget} " +
                     $"seconds={result.Seconds:F0} unreachedTypes=\"{string.Join(",", (result.Unreached ?? []).Take(8).Select(u => $"{u.Type}:{u.Count}"))}\" " +
                     $"heaviestRoots=\"{string.Join(",", (result.HeaviestRoots ?? []).Select(r => $"{r.Root}:{r.Visits}"))}\" holders=\"{string.Join(" | ", result.Holders.Take(15).Select(h => $"{h.Path}={h.Count}({h.Types})"))}\"");
        }

        /// <summary>
        /// Every active autonomous bot's own fields first, then the static fields of the server assembly (scripts included),
        /// then every other active NPC's own fields (monsters, guards, pets). Overnight run of 2026-10-22: 2,424 scheduled logouts left
        /// 1,500 deleted bots in memory, and 1,402 of them were reached from neither the bots nor the statics; game objects
        /// are leaves of the walk, so whatever a monster's own fields hold was never looked at.
        /// </summary>
        private static IEnumerable<(string Name, object Root, bool LeafStart)> Roots(List<GameNPC> activeNpcs = null)
        {
            foreach (GameBot bot in AutonomousBotRegistry.Snapshot())
                if (bot != null && bot.ObjectState == GameObject.eObjectState.Active)
                    yield return ("(active bot)", bot, false);
            foreach (Type type in SafeTypes(typeof(GameServer).Assembly))
            {
                if (type.ContainsGenericParameters) continue;
                FieldInfo[] fields;
                try { fields = type.GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly); }
                catch { continue; }
                foreach (FieldInfo field in fields)
                {
                    if (field.IsLiteral || !MayHoldReferences(field.FieldType)) continue;
                    object value;
                    try { value = field.GetValue(null); } catch { continue; }
                    if (value != null && !Skip(value.GetType())) yield return ($"{type.Name}.{field.Name}", value, true);
                }
            }
            // Last, within what is left of the budget: anything held only by a monster's own fields.
            foreach (GameNPC npc in activeNpcs ?? [])
                if (npc is not GameBot && npc.ObjectState == GameObject.eObjectState.Active)
                    yield return (npc is GameSummonedPet ? "(active pet)" : "(active npc)", npc, false);
        }

        /// <summary>
        /// Pure walk: every target reached from a root through object fields, with the field path that holds it. Game objects
        /// are leaves; a root marked LeafStart that is itself a game object is only checked, not walked.
        /// </summary>
        public static Result Scan(IEnumerable<(string Name, object Root, bool LeafStart)> roots, IEnumerable<object> targetObjects)
        {
            var targets = new HashSet<object>(targetObjects, ReferenceEqualityComparer.Instance);
            var watch = Stopwatch.StartNew();
            var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);
            var rootVisitTotals = new Dictionary<string, int>();
            var holders = new Dictionary<string, (HashSet<object> Targets, Dictionary<string, int> Types)>();
            var reached = new HashSet<object>(ReferenceEqualityComparer.Instance);
            int visits = 0, truncatedRoots = 0, rootCount = 0;
            bool outOfBudget = false;
            if (targets.Count == 0) return new(0, 0, 0, 0, 0, false, 0, []);

            void Record(PathNode path, object target)
            {
                reached.Add(target);
                string key = Signature(path);
                if (!holders.TryGetValue(key, out var entry))
                    holders[key] = entry = (new HashSet<object>(ReferenceEqualityComparer.Instance), new Dictionary<string, int>());
                if (entry.Targets.Add(target))
                {
                    string type = target.GetType().Name;
                    entry.Types[type] = entry.Types.GetValueOrDefault(type) + 1;
                }
            }

            void Walk(object start, PathNode root, bool startIsLeaf)
            {
                int rootVisits = 0;
                var stack = new Stack<(object Value, PathNode Path, int Depth)>();
                if (startIsLeaf && start is GameObject)
                {
                    if (targets.Contains(start)) Record(root, start);
                    return;
                }
                if (!start.GetType().IsValueType && !visited.Add(start)) return;
                PushChildren(start, root, 0, stack);
                while (stack.Count > 0)
                {
                    if (visits >= MaxVisits || watch.Elapsed > TimeBudget) { outOfBudget = true; return; }
                    if (rootVisits >= MaxVisitsPerRoot) { truncatedRoots++; return; }
                    var (value, path, depth) = stack.Pop();
                    if (value is GameObject)
                    {
                        if (targets.Contains(value)) Record(path, value);
                        continue;   // every game object is a leaf: its own fields are its business
                    }
                    if (!value.GetType().IsValueType && !visited.Add(value)) continue;
                    visits++; rootVisits++;
                    if (depth < MaxDepth) PushChildren(value, path, depth + 1, stack);
                }
            }

            foreach (var (name, root, leafStart) in roots)
            {
                if (outOfBudget) break;
                rootCount++;
                int before = visits;
                Walk(root, new PathNode(name, null), leafStart);
                rootVisitTotals[name] = rootVisitTotals.GetValueOrDefault(name) + visits - before;
            }
            var top = holders.OrderByDescending(pair => pair.Value.Targets.Count)
                .Select(pair => (pair.Key, pair.Value.Targets.Count,
                    string.Join("/", pair.Value.Types.OrderByDescending(t => t.Value).Take(3).Select(t => $"{t.Key}:{t.Value}"))))
                .ToList();
            var unreached = targets.Where(target => !reached.Contains(target)).GroupBy(target => target.GetType().Name)
                .Select(group => (group.Key, group.Count())).OrderByDescending(group => group.Item2).ToList();
            return new(targets.Count, reached.Count, rootCount, visits, truncatedRoots, outOfBudget, watch.Elapsed.TotalSeconds, top,
                rootVisitTotals.OrderByDescending(pair => pair.Value).Take(6).Select(pair => (pair.Key, pair.Value)).ToList(), unreached);
        }

        private static void PushChildren(object value, PathNode path, int depth, Stack<(object, PathNode, int)> stack)
        {
            Type type = value.GetType();
            if (value is Array array)
            {
                Type element = type.GetElementType();
                if (element == null || !MayHoldReferences(element)) return;
                string name = "[]";
                if (array is object[] objects)
                {
                    PathNode node = null;
                    foreach (object item in objects)
                        if (item != null && !Skip(item.GetType()))
                            stack.Push((item, node ??= new PathNode(name, path), depth));
                }
                else if (array.Rank == 1)
                {
                    PathNode node = null;
                    int length = array.Length;
                    for (int i = 0; i < length; i++)
                    {
                        object item;
                        try { item = array.GetValue(i); } catch { break; }
                        if (item != null) stack.Push((item, node ??= new PathNode(name, path), depth));
                    }
                }
                return;
            }
            foreach (FieldInfo field in FieldsOf(type))
            {
                object child;
                try { child = field.GetValue(value); } catch { continue; }
                if (child == null || Skip(child.GetType())) continue;
                stack.Push((child, new PathNode(field.Name, path), depth));
            }
        }

        private static string Signature(PathNode path)
        {
            var parts = new List<string>();
            for (PathNode node = path; node != null; node = node.Parent)
                if (parts.Count == 0 || node.Name != "[]" || parts[^1] != "[]") parts.Add(node.Name);
            parts.Reverse();
            var text = new StringBuilder();
            foreach (string part in parts)
            {
                if (text.Length > 0 && part != "[]") text.Append('.');
                text.Append(part);
            }
            return text.Length > 240 ? text.ToString(0, 240) + "…" : text.ToString();
        }

        private static IEnumerable<Type> SafeTypes(Assembly assembly)
        {
            try { return assembly.GetTypes(); }
            catch (ReflectionTypeLoadException exception) { return exception.Types.Where(t => t != null); }
        }

        private static bool Skip(Type type) =>
            type.IsPrimitive || type.IsEnum || type.IsPointer || type == typeof(string) ||
            typeof(MemberInfo).IsAssignableFrom(type) || typeof(Assembly).IsAssignableFrom(type) || typeof(Module).IsAssignableFrom(type) ||
            typeof(Thread).IsAssignableFrom(type) || typeof(DOL.Database.DataObject).IsAssignableFrom(type) ||
            type.Namespace?.StartsWith("log4net", StringComparison.Ordinal) == true ||
            type.IsValueType && !HoldsReferences(type);

        private static bool MayHoldReferences(Type type) =>
            !type.IsPrimitive && !type.IsEnum && !type.IsPointer && type != typeof(string) && (!type.IsValueType || HoldsReferences(type));

        private static bool HoldsReferences(Type valueType)
        {
            lock (StructHoldsReferences)
            {
                if (StructHoldsReferences.TryGetValue(valueType, out bool known)) return known;
                StructHoldsReferences[valueType] = false;   // recursion guard
                bool holds = valueType.GetFields(InstanceFields).Any(field =>
                    !field.FieldType.IsPrimitive && !field.FieldType.IsEnum && !field.FieldType.IsPointer &&
                    (!field.FieldType.IsValueType || field.FieldType != valueType && HoldsReferences(field.FieldType)));
                StructHoldsReferences[valueType] = holds;
                return holds;
            }
        }

        private static FieldInfo[] FieldsOf(Type type)
        {
            lock (FieldCache)
            {
                if (FieldCache.TryGetValue(type, out FieldInfo[] cached)) return cached;
                var fields = new List<FieldInfo>();
                for (Type current = type; current != null && current != typeof(object); current = current.BaseType)
                {
                    try { fields.AddRange(current.GetFields(InstanceFields).Where(field => MayHoldReferences(field.FieldType))); }
                    catch { }
                }
                return FieldCache[type] = fields.ToArray();
            }
        }
    }
}
