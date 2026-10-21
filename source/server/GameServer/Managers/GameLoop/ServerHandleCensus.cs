using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using DOL.Logging;

namespace DOL.GS
{
    /// <summary>
    /// SERVER_HANDLE_CENSUS (Windows test runs only, with runtime\server\memory-census.on): the server's own open handles
    /// by kernel object type (File, Event, Thread, Key, Section...). Overnight runs of 2026-10-20/21: handles climbed about
    /// 2,000 an hour while the thread count stayed at 68, and the total alone does not say what leaks.
    /// One NtQuerySystemInformation snapshot every 30 minutes; the type of each handle comes from NtQueryObject.
    /// </summary>
    public static class ServerHandleCensus
    {
        private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);
        public const int IntervalMinutes = 30;
        private static long _nextRunTicks;
        private static readonly Dictionary<ushort, string> TypeNames = new();
        private static Dictionary<string, int> _last = new();

        private const int SystemExtendedHandleInformation = 0x40;
        private const int ObjectTypeInformation = 2;
        private const uint StatusInfoLengthMismatch = 0xC0000004;

        [DllImport("ntdll.dll")]
        private static extern uint NtQuerySystemInformation(int infoClass, IntPtr info, int length, out int returnLength);

        [DllImport("ntdll.dll")]
        private static extern uint NtQueryObject(IntPtr handle, int infoClass, IntPtr info, int length, out int returnLength);

        public static void MaybeRun()
        {
            if (!OperatingSystem.IsWindows()) return;
            long now = Stopwatch.GetTimestamp();
            if (now < _nextRunTicks) return;
            _nextRunTicks = now + IntervalMinutes * 60 * Stopwatch.Frequency;
            Dictionary<string, int> counts = Count();
            if (counts == null) return;
            var rows = counts.OrderByDescending(pair => pair.Value)
                .Select(pair => (pair.Key, pair.Value, Delta: pair.Value - _last.GetValueOrDefault(pair.Key, pair.Value))).ToList();
            _last = counts;
            Log.Info($"SERVER_HANDLE_CENSUS total={counts.Values.Sum()} " +
                     $"byType=\"{string.Join(",", rows.Take(12).Select(r => $"{r.Key}={r.Value}"))}\" " +
                     $"grew=\"{string.Join(",", rows.Where(r => r.Delta > 0).OrderByDescending(r => r.Delta).Take(8).Select(r => $"{r.Key}+{r.Delta}"))}\"");
        }

        /// <summary>This process's handles by object type; null when the snapshot could not be taken.</summary>
        private static Dictionary<string, int> Count()
        {
            int length = 16 << 20;
            IntPtr buffer = IntPtr.Zero;
            try
            {
                for (int attempt = 0; attempt < 6; attempt++)
                {
                    buffer = global::System.Runtime.InteropServices.Marshal.AllocHGlobal(length);
                    uint status = NtQuerySystemInformation(SystemExtendedHandleInformation, buffer, length, out int needed);
                    if (status == 0) break;
                    global::System.Runtime.InteropServices.Marshal.FreeHGlobal(buffer);
                    buffer = IntPtr.Zero;
                    if (status != StatusInfoLengthMismatch) { Log.Warn($"SERVER_HANDLE_CENSUS NtQuerySystemInformation status=0x{status:X8}"); return null; }
                    length = Math.Max(length * 2, needed + (1 << 20));
                }
                if (buffer == IntPtr.Zero) return null;
                long handles = global::System.Runtime.InteropServices.Marshal.ReadIntPtr(buffer).ToInt64();
                int entrySize = IntPtr.Size == 8 ? 40 : 28;
                int header = IntPtr.Size * 2;
                long pid = Environment.ProcessId;
                var byType = new Dictionary<ushort, (int Count, IntPtr Sample)>();
                for (long i = 0; i < handles; i++)
                {
                    IntPtr entry = buffer + header + (int)(i * entrySize);
                    long owner = global::System.Runtime.InteropServices.Marshal.ReadIntPtr(entry, IntPtr.Size).ToInt64();
                    if (owner != pid) continue;
                    IntPtr value = global::System.Runtime.InteropServices.Marshal.ReadIntPtr(entry, IntPtr.Size * 2);
                    ushort type = (ushort)global::System.Runtime.InteropServices.Marshal.ReadInt16(entry, IntPtr.Size * 3 + 6);
                    byType[type] = byType.TryGetValue(type, out var known) ? (known.Count + 1, known.Sample) : (1, value);
                }
                var counts = new Dictionary<string, int>();
                foreach (var (type, (count, sample)) in byType)
                {
                    string name = TypeName(type, sample);
                    counts[name] = counts.GetValueOrDefault(name) + count;
                }
                return counts;
            }
            catch (Exception exception)
            {
                Log.Warn("SERVER_HANDLE_CENSUS failed", exception);
                return null;
            }
            finally
            {
                if (buffer != IntPtr.Zero) global::System.Runtime.InteropServices.Marshal.FreeHGlobal(buffer);
            }
        }

        private static string TypeName(ushort type, IntPtr sample)
        {
            if (TypeNames.TryGetValue(type, out string known)) return known;
            string name = $"type{type}";
            IntPtr info = global::System.Runtime.InteropServices.Marshal.AllocHGlobal(4096);
            try
            {
                // ObjectTypeInformation starts with the type's UNICODE_STRING name (Length, MaximumLength, Buffer).
                if (NtQueryObject(sample, ObjectTypeInformation, info, 4096, out _) == 0)
                {
                    int bytes = (ushort)global::System.Runtime.InteropServices.Marshal.ReadInt16(info);
                    IntPtr text = global::System.Runtime.InteropServices.Marshal.ReadIntPtr(info, IntPtr.Size);
                    if (bytes > 0 && text != IntPtr.Zero) name = global::System.Runtime.InteropServices.Marshal.PtrToStringUni(text, bytes / 2);
                }
            }
            catch { }
            finally { global::System.Runtime.InteropServices.Marshal.FreeHGlobal(info); }
            return TypeNames[type] = name;
        }
    }
}
