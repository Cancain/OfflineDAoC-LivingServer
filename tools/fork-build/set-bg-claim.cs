#:package System.Data.SQLite.Core@1.0.119
#nullable disable
// Fork: the SQL part of set-bg-claim.ps1 (run it through that script, which checks the server is stopped and backs up).
//   dotnet run set-bg-claim.cs -- <database> <dry|apply> [key=value ...]
// Keys: the fork_* server properties of ForkKeepClaims (switches on|off, fork_bg_claim_limit a number).
// Exit codes: 0 nothing to change or applied, 10 dry run with changes to make, 1 failed, 2 bad arguments.
// The database is opened read-only unless there is something to write: opening it for writing lets SQLite fold its
// write-ahead log into the main file when the connection closes (same rows, other bytes).
using System.Data.SQLite;

var switches = new Dictionary<string, string>
{
    ["fork_bg_claim"] = "Fork: guilds may claim battleground keeps (never portal or relic keeps); a claimed battleground keep keeps its level.",
    ["fork_claim_counts_group_bots"] = "Fork: the claiming player's group companions and autonomous bots in the keep's area count towards claim_num.",
    ["fork_bot_guilds_claim_bg"] = "Fork: bot guilds may claim battleground keeps (needs fork_bg_claim).",
};
var numbers = new Dictionary<string, (string Description, string Default)>
{
    ["fork_bg_claim_limit"] = ("Fork: how many battleground keeps a guild may claim when fork_bg_claim is on (frontier keeps count against guilds_claim_limit).", "1"),
};

if (args.Length < 2 || args[1] is not ("dry" or "apply"))
{
    Console.Error.WriteLine("usage: set-bg-claim.cs <database> <dry|apply> [key=value ...]");
    return 2;
}
string database = args[0];
bool apply = args[1] == "apply";
var wanted = new List<(string Key, string Value)>();
foreach (string arg in args.Skip(2))
{
    string[] parts = arg.Split('=', 2);
    bool known = parts.Length == 2 &&
        ((switches.ContainsKey(parts[0]) && parts[1] is "on" or "off") ||
         (numbers.ContainsKey(parts[0]) && int.TryParse(parts[1], out int number) && number >= 0));
    if (!known)
    {
        Console.Error.WriteLine($"Unknown setting '{arg}'. Nothing was changed.");
        return 2;
    }
    wanted.Add((parts[0], switches.ContainsKey(parts[0]) ? (parts[1] == "on" ? "True" : "False") : parts[1]));
}

static string Value(SQLiteConnection connection, SQLiteTransaction transaction, string key)
{
    using var command = connection.CreateCommand();
    command.Transaction = transaction;
    command.CommandText = "SELECT Value FROM ServerProperty WHERE `Key`=@key";
    command.Parameters.AddWithValue("@key", key);
    return Convert.ToString(command.ExecuteScalar());
}

string DefaultOf(string key) => numbers.TryGetValue(key, out var number) ? number.Default : "False";

List<(string Key, string Value)> Pending(SQLiteConnection connection, SQLiteTransaction transaction) =>
    wanted.Where(change =>
    {
        string current = Value(connection, transaction, change.Key);
        string effective = string.IsNullOrEmpty(current) ? DefaultOf(change.Key) : current;
        return !string.Equals(effective, change.Value, StringComparison.OrdinalIgnoreCase);
    }).ToList();

List<(string Key, string Value)> pending;
using (var reader = new SQLiteConnection($"Data Source={database};Version=3;Pooling=False;Default Timeout=10;Read Only=True;"))
{
    reader.Open();
    Console.WriteLine("Now:");
    foreach (string key in switches.Keys.Concat(numbers.Keys))
    {
        string value = Value(reader, null, key);
        Console.WriteLine($"  {key,-30} {(string.IsNullOrEmpty(value) ? $"(no row: {DefaultOf(key)})" : value)}");
    }
    pending = Pending(reader, null);
}

foreach (var (key, value) in pending)
    Console.WriteLine($"Change: {key} -> {value}");
if (pending.Count == 0)
{
    Console.WriteLine("Nothing to change.");
    return 0;
}
if (!apply)
{
    Console.WriteLine($"Dry run: {pending.Count} change(s) shown. Nothing was changed.");
    return 10;
}

using var connection = new SQLiteConnection($"Data Source={database};Version=3;Pooling=False;Default Timeout=10;");
connection.Open();
using SQLiteTransaction transaction = connection.BeginTransaction();
foreach (var (key, value) in Pending(connection, transaction))
{
    using var command = connection.CreateCommand();
    command.Transaction = transaction;
    // ServerProperty_ID is unique, so a new row uses the key, as the launcher's Living Server tab does.
    command.CommandText = """
        INSERT INTO ServerProperty (Category, `Key`, Description, DefaultValue, Value, LastTimeRowUpdated, ServerProperty_ID)
        VALUES ('fork', @key, @description, @default, @value, @updated, @key)
        ON CONFLICT(`Key`) DO UPDATE SET Value=excluded.Value, LastTimeRowUpdated=excluded.LastTimeRowUpdated
        """;
    command.Parameters.AddWithValue("@key", key);
    command.Parameters.AddWithValue("@description", switches.TryGetValue(key, out string text) ? text : numbers[key].Description);
    command.Parameters.AddWithValue("@default", DefaultOf(key));
    command.Parameters.AddWithValue("@value", value);
    command.Parameters.AddWithValue("@updated", DateTime.UtcNow.ToString("yyyy-MM-dd HH:mm:ss"));
    command.ExecuteNonQuery();
}
transaction.Commit();
Console.WriteLine($"Applied {pending.Count} change(s). They take effect the next time the server starts.");
return 0;
