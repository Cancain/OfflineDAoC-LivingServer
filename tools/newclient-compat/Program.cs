// A stand-in for the game server's network side: it accepts the new (Godot) client's real connection and sends the
// Living Server's messages through the server's own packet code (GameClient + PacketLib1127 + PacketProcessor), with
// lines picked from the real bot-voices corpus. It records the client's dialog answers (packet 0x82) and writes
// cases.json (what was sent) for the comparison. Test harness only; not part of the game.
using System.Net;
using System.Net.Sockets;
using System.Runtime.CompilerServices;
using System.Text.Json;
using DOL.GS;
using DOL.GS.PacketHandler;
using VC = DOL.GS.AutonomousBotVoiceCorpus;

string outDir = args.Length > 0 ? args[0] : ".";
var cases = new List<Dictionary<string, object>>();
var random = new Random(2003);
VC corpus = AutonomousBotVoices.Corpus ?? throw new Exception("corpus did not load");

Dictionary<string, string> Slots(params (string, string)[] extra)
{
    var s = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["me"] = "Brannoc", ["class"] = "druid", ["level"] = "34", ["realm"] = "Hibernia", ["zone"] = "Lough Derg",
        ["monster"] = "bwca", ["item"] = "a Celtic sword", ["count"] = "3", ["q"] = "", ["keep"] = "Dun Crauchon",
        ["frontier"] = "Breifine", ["enemy"] = "Midgard", ["capital"] = "Tir na Nog", ["dungeon"] = "Spraggon Den",
        ["camp"] = "Lough Derg",
    };
    foreach (var (k, v) in extra) s[k] = v;
    return s;
}

string Line(string kind, string topic = null, string mood = null, string intent = null, string[] flags = null, params (string, string)[] extra)
{
    var speaker = new VC.Speaker(4242, "Brannoc", eRealm.Hibernia, "Druid", 34, BotPersonalityType.Socialite,
        new HashSet<string>(flags ?? Array.Empty<string>(), StringComparer.Ordinal));
    if (!corpus.TryPick(kind, speaker, Slots(extra), null, DateTime.UtcNow, random, out string text, out _, intent, topic, mood))
        throw new Exception($"no {kind}/{topic}/{mood} line");
    return text;
}

// ---- connect -------------------------------------------------------------------------------------------------
var listener = new TcpListener(IPAddress.Loopback, 10300);
listener.Start();
Console.WriteLine("[server] listening on 10300");
Socket socket = listener.AcceptSocket();
Console.WriteLine("[server] the new client connected");
var client = new GameClient(socket);
client.Out = AbstractPacketLib.CreatePacketLibForVersion(1127, client, out GameClient.eClientVersion version);
client.PacketProcessor = new PacketProcessor(client);
client.ClientState = GameClient.eClientState.Playing;
Console.WriteLine($"[server] packet library {client.Out.GetType().Name} ({version})");

// The client's packets: [len u16][seq u16][session u16][param u16][code u16] data [checksum u16].
var answers = new List<Dictionary<string, object>>();
var reader = new Thread(() =>
{
    var stream = new NetworkStream(socket);
    var head = new byte[10];
    try
    {
        while (true)
        {
            if (!Read(stream, head, 10)) break;
            int len = (head[0] << 8) | head[1];
            var body = new byte[len + 2];
            if (!Read(stream, body, len + 2)) break;
            int code = head[9];
            if (code == 0x82)
            {
                // DialogResponseHandler's order: data1, data2, data3 (u16), dialog code (byte), response (byte)
                var a = new Dictionary<string, object>
                {
                    ["data1"] = (body[0] << 8) | body[1], ["data2"] = (body[2] << 8) | body[3], ["data3"] = (body[4] << 8) | body[5],
                    ["code"] = (int)body[6], ["response"] = (int)body[7],
                };
                lock (answers) answers.Add(a);
                Console.WriteLine($"[server] dialog answer: {JsonSerializer.Serialize(a)}");
            }
        }
    }
    catch (Exception) { }
}) { IsBackground = true };
reader.Start();

static bool Read(NetworkStream s, byte[] b, int n)
{
    int got = 0;
    while (got < n) { int r = s.Read(b, got, n - got); if (r <= 0) return false; got += r; }
    return true;
}

void Flush() => client.PacketProcessor.SendPendingPackets();

void Send(string id, string feature, string text, eChatType type, eChatLoc loc, string expectKind, bool center = false)
{
    client.Out.SendMessage(text, type, loc);
    Flush();
    cases.Add(new() { ["id"] = id, ["feature"] = feature, ["text"] = text, ["type"] = (int)type, ["loc"] = loc.ToString(),
        ["expect_kind"] = expectKind, ["expect_center"] = center });
    Thread.Sleep(40);
}

// The exact formats the server uses: GamePlayer.SayReceive ("GamePlayer.SayReceive.Says" in language/EN),
// Group.SendMessageToGroupMembers, AutonomousBotChatCoordinator.BroadcastFaction, AutonomousBotGuildSocial.SendGuildLine,
// ChatUtil.SendSendMessage ("Social.ReceiveMessage.Private.Sends").
string Say(string who, string line) => $"{who} says, \"{line}\"";
string Party(string who, string line) => $"[Party] {who}: \"{line}\"";
string Faction(string who, string line) => $"({who}) <Faction> {line}";
string GuildLine(string who, string line) => $"[Guild] {who}: \"{line}\"";
string Tell(string who, string line) => $"{who} sends, \"{line}\"";
var me = ("target", "Chrisplays");
var player = ("player", "Chrisplays");
var playerClass = ("player_class", "druid");
var place = ("place", "Lough Derg");

Thread.Sleep(1500);   // the client's handshake first

// Grats
Send("grats-group", "Grats", Party("Brannoc", Line("grats", "general", extra: me)), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
Send("grats-say", "Grats", Say("Aoife", Line("grats", "general", extra: me)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("grats-50-faction", "Grats", Faction("Ciaran", Line("grats", "fifty", extra: me)), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
// Server firsts (AutonomousLivingServer.TryClaimFirst)
Send("first-own-realm", "Server firsts", "Server first: Chrisplays is the first on the server to reach level 50.",
    eChatType.CT_ScreenCenterSmaller_And_CT_System, eChatLoc.CL_SystemWindow, "system", center: true);
Send("first-other-realm", "Server firsts", "Server first: a Hibernian druid is the first on the server to reach 50 as a druid.",
    eChatType.CT_ScreenCenterSmaller_And_CT_System, eChatLoc.CL_SystemWindow, "system", center: true);
Send("first-cheer", "Server firsts", Faction("Brannoc", Line("first", extra: new[] { me, ("what", "level 50") })), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
// Rezzes and corpse runs
Send("rez-ask-group", "Rezzes", Party("Brannoc", Line("rez_ask", "player", flags: new[] { "just_died", "player_nearby" }, extra: new[] { player, playerClass })), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
Send("rez-ask-say", "Rezzes", Say("Brannoc", Line("rez_ask", "player", flags: new[] { "just_died", "player_nearby" }, extra: new[] { player, playerClass })), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("rez-ask-send", "Rezzes", Tell("Brannoc", Line("rez_ask", "player", flags: new[] { "just_died", "player_nearby" }, extra: new[] { player, playerClass })), eChatType.CT_Send, eChatLoc.CL_ChatWindow, "send");
Send("rez-thanks", "Rezzes", Say("Brannoc", Line("rez_thanks", extra: me)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("corpse", "Rezzes", Party("Brannoc", Line("corpse", flags: new[] { "just_died" })), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
Send("sickness", "Rezzes", Party("Brannoc", Line("sickness")), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
Send("rez-offer", "Rezzes", Say("Aoife", Line("rez_offer", extra: me)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
// Frontier alarms and nemeses
Send("alarm", "Frontier alarms", Faction("Brannoc", Line("alarm", flags: new[] { "in_rvr" }, extra: new[] { ("size", "8"), ("enemy", "mids"), ("place", "Dun Crauchon"), ("classes", "healer, warrior, skald") })), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
var killer = new[] { ("killer", "troll"), ("killer_class", "berserker"), ("place", "Dun Crauchon") };
Send("nemesis", "Nemeses", Faction("Brannoc", Line("nemesis", extra: killer)), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
Send("revenge", "Nemeses", Faction("Brannoc", Line("revenge", extra: killer)), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
// Bots remember you
var known = new[] { player, playerClass, place };
Send("greet", "Bots remember you", Say("Brannoc", Line("greet", mood: "friendly", flags: new[] { "knows_player", "player_nearby" }, extra: known)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("old-rez-thanks", "Bots remember you", Say("Brannoc", Line("thanks", "rez", flags: new[] { "knows_player", "player_nearby" }, extra: known)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("known-reply", "Bots remember you", Say("Brannoc", Line("reply", intent: "greeting", flags: new[] { "knows_player" }, extra: known)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("grudge", "Bots remember you", Say("Brannoc", Line("grudge", mood: "cool", flags: new[] { "knows_player" }, extra: known)), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("gossip", "Bots remember you", Faction("Ciaran", Line("gossip", mood: "friendly", flags: new[] { "knows_player" }, extra: known)), eChatType.CT_Broadcast, eChatLoc.CL_ChatWindow, "broadcast");
// Schedules, breaks and linkdeads
Send("logon-guild", "Schedules", GuildLine("Brannoc", Line("session", "logon")), eChatType.CT_Guild, eChatLoc.CL_ChatWindow, "guild");
Send("logoff-say", "Schedules", Say("Brannoc", Line("session", "logoff")), eChatType.CT_Say, eChatLoc.CL_ChatWindow, "say");
Send("brb-guild", "Breaks", GuildLine("Aoife", Line("session", "brb")), eChatType.CT_Guild, eChatLoc.CL_ChatWindow, "guild");
Send("back-guild", "Breaks", GuildLine("Aoife", Line("session", "back")), eChatType.CT_Guild, eChatLoc.CL_ChatWindow, "guild");
Send("ld-gone", "Linkdeads", Party("Brannoc", Line("linkdead", "gone", extra: ("target", "Aoife"))), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
Send("ld-back", "Linkdeads", Party("Aoife", Line("linkdead", "back")), eChatType.CT_Group, eChatLoc.CL_ChatWindow, "group");
// Existing Living Server paths the new features build on (bot guild join notice: Guild.SendMessageToGuildMembers)
Send("guild-joined", "Bot guilds", "Brannoc has joined the guild!", eChatType.CT_Group, eChatLoc.CL_SystemWindow, "group");

// Yes / no boxes: the exact bytes SendCustomDialog writes (PacketLib168: code CustomDialog, data1 the session,
// data2 1, type yes/no, autowrap unless the text has a line break), sent through SendDialogBox because
// SendCustomDialog also needs a loaded GamePlayer for its callback slot.
// A session id, as the server's connection code gives every client (BaseClient.OnConnect).
var session = new DOL.Network.SessionId(new DOL.Network.SessionIdAllocator());
typeof(DOL.Network.BaseClient).GetProperty("SessionId")!.GetSetMethod(true)!.Invoke(client, new object[] { session });
void Dialog(string id, string feature, string text)
{
    int before;
    lock (answers) before = answers.Count;
    client.Out.SendDialogBox(eDialogCode.CustomDialog, client.SessionID, 0x01, 0x00, 0x00, eDialogType.YesNo, !text.Contains('\n'), text);
    Flush();
    cases.Add(new() { ["id"] = id, ["feature"] = feature, ["text"] = text, ["dialog"] = true });
    for (int i = 0; i < 100; i++) { lock (answers) if (answers.Count > before) break; Thread.Sleep(100); }
}
Dialog("rez-box", "Rezzes", "Do you allow Aoife to resurrected you\n with 10 percent hits/power?");
Dialog("guild-invite-box", "Bot guilds", "Brannoc invites you to join Fianna of the Ford. Do you accept?");

Send("end", "-", "LIVING-SERVER-PROBE-END", eChatType.CT_System, eChatLoc.CL_SystemWindow, "system");
Thread.Sleep(500);
int answered = -1;
// DialogResponseHandler hands a CustomDialog answer with data2 == 1 to the player's callback.
lock (answers)
    answered = answers.Count(a => (int)a["code"] == (int)eDialogCode.CustomDialog && (int)a["data2"] == 1 &&
                                  (int)a["data1"] == client.SessionID && (int)a["response"] == 1);

File.WriteAllText(Path.Combine(outDir, "cases.json"), JsonSerializer.Serialize(new { cases, answers, acceptedCustomDialogAnswers = answered },
    new JsonSerializerOptions { WriteIndented = true }));
Console.WriteLine($"[server] sent {cases.Count} cases; dialog answers {answers.Count}; accepted CustomDialog answers {answered}");
Thread.Sleep(1500);
socket.Close();
