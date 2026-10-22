using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using DOL.Logging;

namespace DOL.GS
{
    /// <summary>
    /// SERVER_LOCK_EVENTS (test runs only, with runtime\server\memory-census.on): which <see cref="Lock"/> fields hold a
    /// Windows Event. On .NET 10 a Lock creates an AutoResetEvent the first time a thread has to wait for it and keeps it
    /// for the Lock's life. Live run of 2026-10-22: with deleted bots now freed, Event handles still grew about 1,700 an
    /// hour; long-lived monsters each carry several Locks, so every first collision adds one for good. This counts the
    /// Locks reachable from the server's NPCs, regions and static fields, by the field that declares them.
    /// </summary>
    public static class ServerLockEventCensus
    {
        private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);

        public const int IntervalMinutes = 30;
        public const int MaxDepth = 4;
        public const int MaxVisits = 20_000_000;
        private const BindingFlags InstanceFields = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly;
        private static readonly FieldInfo WaitEventField = typeof(Lock).GetField("_waitEvent", BindingFlags.Instance | BindingFlags.NonPublic);
        private static readonly Dictionary<Type, FieldInfo[]> FieldCache = new();
        private static long _nextRunTicks;
        private static int _running;

        public sealed record Result(int Locks, int WithEvent, int Visits, bool OutOfBudget, IReadOnlyList<(string Field, int Locks, int WithEvent)> ByField);

        /// <summary>True when the Lock has made its wait event (null when this runtime keeps no such field).</summary>
        public static bool? HasWaitEvent(Lock value) => WaitEventField == null ? null : WaitEventField.GetValue(value) != null;

        public static void MaybeRun(Func<IEnumerable<object>> roots)
        {
            long now = System.Diagnostics.Stopwatch.GetTimestamp();
            if (_nextRunTicks == 0) _nextRunTicks = now + 10L * 60 * System.Diagnostics.Stopwatch.Frequency;
            if (now < _nextRunTicks || Interlocked.Exchange(ref _running, 1) == 1) return;
            _nextRunTicks = now + IntervalMinutes * 60L * System.Diagnostics.Stopwatch.Frequency;
            var thread = new Thread(() =>
            {
                try
                {
                    var watch = System.Diagnostics.Stopwatch.StartNew();
                    Result result = Count(roots());
                    Log.Info($"SERVER_LOCK_EVENTS locks={result.Locks} withEvent={result.WithEvent} visits={result.Visits} " +
                             $"outOfBudget={result.OutOfBudget} seconds={watch.Elapsed.TotalSeconds:F0} " +
                             $"byField=\"{string.Join(",", result.ByField.Take(15).Select(f => $"{f.Field}={f.WithEvent}/{f.Locks}"))}\"");
                }
                catch (Exception exception) { Log.Warn("SERVER_LOCK_EVENTS failed", exception); }
                finally { Volatile.Write(ref _running, 0); }
            }) { IsBackground = true, Priority = ThreadPriority.BelowNormal, Name = "LockEventCensus" };
            thread.Start();
        }

        /// <summary>
        /// Every Lock reachable through object fields (and object arrays) from the roots, at most <see cref="MaxDepth"/>
        /// fields down; a game object other than a root is not entered (it is a root of its own when it matters).
        /// </summary>
        public static Result Count(IEnumerable<object> roots)
        {
            var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);
            var byField = new Dictionary<string, (int Locks, int WithEvent)>();
            int visits = 0;
            bool outOfBudget = false;
            var stack = new Stack<(object Value, string Field, int Depth)>();
            foreach (object root in roots)
            {
                if (root == null || !visited.Add(root)) continue;
                if (root is StaticLock named) stack.Push((named.Value, $"static {named.Name}", 0));
                else stack.Push((root, null, 0));
                while (stack.Count > 0)
                {
                    if (++visits > MaxVisits) { outOfBudget = true; break; }
                    var (value, field, depth) = stack.Pop();
                    if (value is Lock found)
                    {
                        bool withEvent = HasWaitEvent(found) == true;
                        string key = field ?? "(root)";
                        var entry = byField.GetValueOrDefault(key);
                        byField[key] = (entry.Locks + 1, entry.WithEvent + (withEvent ? 1 : 0));
                        continue;
                    }
                    if (depth >= MaxDepth) continue;
                    if (value is object[] array)
                    {
                        foreach (object item in array)
                            if (item != null && item is not GameObject && !item.GetType().IsValueType && visited.Add(item))
                                stack.Push((item, field, depth + 1));
                        continue;
                    }
                    foreach (FieldInfo info in FieldsOf(value.GetType()))
                    {
                        object child;
                        try { child = info.GetValue(value); } catch { continue; }
                        if (child == null || child is GameObject || child is string || child.GetType().IsValueType || child is Type ||
                            child is Delegate || child is MemberInfo || !visited.Add(child)) continue;
                        stack.Push((child, $"{info.DeclaringType?.Name}.{info.Name}", depth + 1));
                    }
                }
                if (outOfBudget) break;
            }
            var rows = byField.Select(p => (p.Key, p.Value.Locks, p.Value.WithEvent)).OrderByDescending(r => r.WithEvent).ThenByDescending(r => r.Locks).ToList();
            return new(rows.Sum(r => r.Locks), rows.Sum(r => r.WithEvent), visits, outOfBudget, rows);
        }

        private static FieldInfo[] FieldsOf(Type type)
        {
            lock (FieldCache)
            {
                if (FieldCache.TryGetValue(type, out FieldInfo[] cached)) return cached;
                var list = new List<FieldInfo>();
                for (Type t = type; t != null && t != typeof(object); t = t.BaseType)
                    foreach (FieldInfo info in t.GetFields(InstanceFields))
                        if (!info.FieldType.IsPrimitive && !info.FieldType.IsEnum && !info.FieldType.IsPointer && info.FieldType != typeof(string))
                            list.Add(info);
                return FieldCache[type] = list.ToArray();
            }
        }

        /// <summary>The roots: every NPC still in memory, every region (its zones and areas) and the server's static fields.</summary>
        public static IEnumerable<object> DefaultRoots(IEnumerable<GameNPC> npcs)
        {
            foreach (GameNPC npc in npcs) yield return npc;
            foreach (Region region in WorldMgr.GetAllRegions()) yield return region;
            foreach (Type type in SafeTypes(typeof(GameServer).Assembly))
            {
                if (type.ContainsGenericParameters) continue;
                FieldInfo[] fields;
                try { fields = type.GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly); }
                catch { continue; }
                foreach (FieldInfo info in fields)
                {
                    if (info.IsLiteral || info.FieldType.IsPrimitive || info.FieldType.IsEnum) continue;
                    object value;
                    try { value = info.GetValue(null); } catch { continue; }
                    if (value is Lock)
                        yield return new StaticLock(value, $"{type.Name}.{info.Name}");
                    else if (value != null && value is not string && !value.GetType().IsValueType)
                        yield return value;
                }
            }
        }

        /// <summary>A static Lock field, named for the census.</summary>
        internal sealed class StaticLock(object value, string name)
        {
            public readonly object Value = value;
            public readonly string Name = name;
        }

        private static IEnumerable<Type> SafeTypes(Assembly assembly)
        {
            try { return assembly.GetTypes(); }
            catch (ReflectionTypeLoadException exception) { return exception.Types.Where(t => t != null); }
        }
    }
}
