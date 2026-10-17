using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading;
using DOL.Database;
using DOL.Database.Attributes;
using DOL.Logging;

namespace DOL.GS;

/// <summary>What an autonomous gamebot remembers about one character it met (Living Server, docs/LIVING-SERVER.md).</summary>
[DataTable(TableName = "offline_bot_memory")]
public sealed class OfflineBotMemoryRecord : DataObject
{
    [DataElement(AllowDbNull = false, Index = true)] public long BotId { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 64)] public string PlayerName { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false, Varchar = 32)] public string PlayerClass { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public int PlayerRealm { get; set; }
    [DataElement(AllowDbNull = false)] public int Grouped { get; set; }
    [DataElement(AllowDbNull = false)] public int Rezzed { get; set; }
    [DataElement(AllowDbNull = false)] public int Abused { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 16)] public string LastTopic { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false, Varchar = 64)] public string LastPlace { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public string FirstMetUtc { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public string LastSeenUtc { get; set; } = string.Empty;
}

/// <summary>An enemy who killed an autonomous gamebot, and how often (Living Server nemesis; the Herald's Most Wanted).</summary>
[DataTable(TableName = "offline_bot_nemesis")]
public sealed class OfflineBotNemesisRecord : DataObject
{
    [DataElement(AllowDbNull = false, Index = true)] public long BotId { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 64)] public string KillerName { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public int KillerRealm { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 32)] public string KillerClass { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false, Varchar = 32)] public string KillerRace { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public bool KillerIsPlayer { get; set; }
    [DataElement(AllowDbNull = false)] public int Kills { get; set; }
    [DataElement(AllowDbNull = false)] public int Revenges { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 64)] public string LastPlace { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public string LastUtc { get; set; } = string.Empty;
}

/// <summary>A server first (first to level 50, first of a class to 50, first to a realm rank).</summary>
[DataTable(TableName = "offline_server_firsts")]
public sealed class OfflineServerFirstRecord : DataObject
{
    [DataElement(AllowDbNull = false, Unique = true, Varchar = 64)] public string Title { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public int Realm { get; set; }
    [DataElement(AllowDbNull = false, Varchar = 64)] public string Name { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false, Varchar = 32)] public string ClassName { get; set; } = string.Empty;
    [DataElement(AllowDbNull = false)] public bool IsPlayer { get; set; }
    /// <summary>Empty for a first that was already reached before records began (seeded at start-up, never announced).</summary>
    [DataElement(AllowDbNull = false)] public string AchievedUtc { get; set; } = string.Empty;
}

/// <summary>
/// Rows of one Living Server table, cached in memory and written in batches off the game loop
/// under the shared database write lock (the pattern of the bot guild memberships). A failed batch
/// stays queued and is tried again; nothing here writes on the game loop.
/// </summary>
public sealed class LivingServerTable<TKey, TRow> where TRow : DataObject
{
    private static readonly Logger Log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);
    private const int WriteBatch = 16;
    private readonly object _sync = new();
    private readonly Dictionary<TKey, TRow> _rows;
    private readonly Dictionary<TKey, TRow> _pending;
    private readonly Func<TRow, TKey> _keyOf;
    private readonly string _name;
    private int _flushing;

    public LivingServerTable(string name, Func<TRow, TKey> keyOf, IEqualityComparer<TKey> comparer = null)
    {
        _name = name;
        _keyOf = keyOf;
        _rows = new Dictionary<TKey, TRow>(comparer);
        _pending = new Dictionary<TKey, TRow>(comparer);
    }

    public int Count
    {
        get { lock (_sync) return _rows.Count; }
    }

    public void Load(IEnumerable<TRow> rows)
    {
        lock (_sync)
        {
            _rows.Clear();
            _pending.Clear();
            foreach (TRow row in rows)
                _rows[_keyOf(row)] = row;
        }
    }

    public bool TryGet(TKey key, out TRow row)
    {
        lock (_sync)
            return _rows.TryGetValue(key, out row);
    }

    public TRow[] Where(Func<TRow, bool> predicate)
    {
        lock (_sync)
            return _rows.Values.Where(predicate).ToArray();
    }

    /// <summary>Changes (or creates) a row under the table lock and queues it for writing. Returns the row.</summary>
    public TRow Change(TKey key, Func<TRow> create, Action<TRow> change)
    {
        lock (_sync)
        {
            if (!_rows.TryGetValue(key, out TRow row))
                _rows[key] = row = create();
            change(row);
            _pending[key] = row;
            return row;
        }
    }

    /// <summary>Adds a row only if the key is free (used to claim a server first exactly once).</summary>
    public bool TryAdd(TKey key, TRow row)
    {
        lock (_sync)
        {
            if (_rows.ContainsKey(key))
                return false;
            _rows[key] = row;
            _pending[key] = row;
            return true;
        }
    }

    public void Flush()
    {
        if (Interlocked.Exchange(ref _flushing, 1) != 0)
            return;
        try
        {
            KeyValuePair<TKey, TRow>[] writes;
            lock (_sync)
            {
                if (_pending.Count == 0)
                    return;
                writes = _pending.ToArray();
                _pending.Clear();
            }
            var failed = new List<KeyValuePair<TKey, TRow>>();
            lock (AutonomousBotStatusPersistence.DatabaseWriteLock)
            {
                foreach (var chunk in writes.Where(pair => !pair.Value.IsPersisted).Chunk(WriteBatch))
                    if (!TryWrite(() => GameServer.Database.AddObject(chunk.Select(pair => (DataObject)pair.Value))))
                        failed.AddRange(chunk.Where(pair => !pair.Value.IsPersisted));
                foreach (var chunk in writes.Where(pair => pair.Value.IsPersisted).Chunk(WriteBatch))
                    if (!TryWrite(() => GameServer.Database.SaveObject(chunk.Select(pair => (DataObject)pair.Value))))
                        failed.AddRange(chunk);
            }
            if (failed.Count > 0)
            {
                lock (_sync)
                    foreach (var pair in failed)
                        _pending.TryAdd(pair.Key, pair.Value);
                Log.Warn($"Living Server: {failed.Count} {_name} write(s) failed; retrying");
            }
        }
        finally
        {
            Volatile.Write(ref _flushing, 0);
        }
    }

    private bool TryWrite(Func<bool> write)
    {
        try
        {
            return write();
        }
        catch (Exception exception)
        {
            Log.Error($"Living Server: {_name} write failed", exception);
            return false;
        }
    }
}
