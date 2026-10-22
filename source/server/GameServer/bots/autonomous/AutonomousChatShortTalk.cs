using System;
using System.Collections.Generic;
using System.Linq;

namespace DOL.GS;

/// <summary>
/// Word rules for the short chat and common requests players type (0.36-se.4). They run before the
/// classifier: "ty", "gz", "lol", "brb", "wb", "inc", "rez pls", "wts", "lfg", "ding 20", "is friar good?",
/// "are you a bot?". The audit (2026-10-18) ran 90 realistic messages through the classifier alone: 41%
/// were read right, and 19 of them ("lol", "ty", "gz", "inc", "brb"...) read as real-world talk.
/// Pure and tested (UT_ChatShortTalk).
/// </summary>
public static class AutonomousChatShortTalk
{
    private static HashSet<string> Set(params string[] words) => new(words, StringComparer.OrdinalIgnoreCase);

    private static readonly HashSet<string> ThanksWords = Set("ty", "thx", "thanks", "thank", "tyvm", "tyty", "tx", "thnx", "thanx",
        "thks", "ta", "tyfr", "cheers", "appreciated");
    private static readonly HashSet<string> CongratsWords = Set("gz", "grats", "gratz", "grtz", "congrats", "congratulations",
        "gratss", "gzz", "grats!");
    private static readonly HashSet<string> AwayWords = Set("brb", "afk", "bio", "brt");
    private static readonly HashSet<string> BackWords = Set("back", "re", "bk", "rebuffed");
    private static readonly HashSet<string> FarewellWords = Set("gn", "gnight", "goodnight", "nite", "bye", "byebye", "cya", "cu",
        "laters", "gtg", "g2g", "farewell", "nn");
    private static readonly HashSet<string> GreetingWords = Set("hi", "hello", "hey", "heya", "hiya", "yo", "hail", "sup", "greetings",
        "howdy", "hallo", "hiho", "evening", "morning", "afternoon", "o");
    private static readonly HashSet<string> GreetingObjects = Set("all", "everyone", "everybody", "guys", "folks", "realm", "there",
        "ppl", "people", "friends", "yall", "albion", "midgard", "hibernia", "albs", "mids", "hibs", "guild", "again", "back");
    private static readonly HashSet<string> LaughWords = Set("lol", "lolol", "lololol", "lmao", "rofl", "roflmao", "haha", "hahaha",
        "hehe", "heh", "hah", "ha", "lul", "xd", "hehehe", "ahaha", "lawl", "kek", "gg", "omg", "wow", "nice");
    private static readonly HashSet<string> RezWords = Set("rez", "res", "rezz", "rezzes", "ress", "resurrect", "resurrection");
    private static readonly HashSet<string> AlarmWords = Set("inc", "incs", "incoming");
    private static readonly HashSet<string> TradeWords = Set("wts", "wtb", "wtt", "pc", "selling", "buying", "sell", "buy",
        "price", "trade", "trading", "auction", "plat", "craft", "crafter", "crafting", "crafted", "spellcraft", "spellcrafter",
        "alchemist", "tailor", "armorcrafter", "weaponcrafter", "fletcher", "commission");
    private static readonly HashSet<string> GroupWords = Set("lfg", "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lfmore", "group", "grp",
        "groups", "party", "inv", "invite", "duo", "trio", "fg", "lfguild", "lf", "forming", "puller", "pullers");
    private static readonly HashSet<string> RvrWords = Set("rvr", "frontier", "relic", "relics", "emain", "hadrians",
        "hadrian", "odins", "mg", "amg", "hmg", "mmg", "milegate", "stealther", "stealthers", "rps", "rp", "rr", "thid", "thidranki",
        "abermenai", "murdaigean", "caledonia", "cathal", "bg", "battleground", "siege", "realmpoints", "zerg", "zergs", "zerging",
        "benowyc", "berkstead", "boldiam", "bledmeer", "crauchon", "crimthainn", "nottmoor", "glenlock", "renaris", "erasleigh",
        "sursbrooke", "hurbury", "blendrake", "arvakr", "fensalir", "hlidskialf", "nottmoor", "bolg", "ailline", "behnn", "scathaig");
    private static readonly HashSet<string> DungeonWords = Set("dungeon", "dungeons", "tomb", "cave", "caves", "caverns",
        "barrows", "den", "lair", "spindelhalla", "spindel", "varulvhamn", "varulv", "df", "darkness", "treibh", "coruscating",
        "keltoi", "fogou", "tepok", "tepoks", "mithra", "vendo", "nisse", "nisses", "muire", "spraggon", "koalinth", "catacombs");
    private static readonly HashSet<string> BanterWords = Set("same", "true", "ikr", "agreed", "yep", "yup", "indeed", "word", "truth",
        "exactly", "totally", "right", "ouch", "yikes", "oof", "ugh", "bah", "meh", "nice", "sweet", "cool", "awesome", "wow");
    private static readonly HashSet<string> GankWords = Set("gank", "ganked", "ganking", "ganks", "stealthed", "stealther", "stealthers");
    private static readonly HashSet<string> BotWords = Set("bot", "bots", "npc", "npcs", "ai", "program", "script", "scripted", "robot");
    private static readonly HashSet<string> SpecWords = Set("spec", "specs", "specced", "respec", "build", "nerf", "nerfed", "nerfs",
        "op", "overpowered", "gimped", "gimp", "uber", "underpowered");
    private static readonly HashSet<string> OpinionWords = Set("good", "bad", "better", "best", "worse", "worst", "fun", "worth",
        "op", "strong", "weak", "viable", "think", "recommend", "favorite", "easy", "hard", "squishy", "tanky", "solo",
        "soloing", "soloable", "useful", "useless", "broken");

    /// <summary>Every class name of the three realms, lower-cased, with the usual short forms.</summary>
    private static readonly HashSet<string> ClassWords = Set("armsman", "armsmen", "paladin", "paladins", "pally", "mercenary", "merc",
        "mercs", "reaver", "reavers", "scout", "scouts", "infiltrator", "infiltrators", "infil", "infils", "minstrel", "minstrels",
        "minstrels", "cleric", "clerics", "friar", "friars", "wizard", "wizards", "wiz", "theurgist", "theurgists", "theurg", "theu",
        "sorcerer", "sorcerers", "sorc", "sorcs", "cabalist", "cabalists", "cabby", "necromancer", "necromancers", "necro", "necros",
        "warrior", "warriors", "thane", "thanes", "skald", "skalds", "berserker", "berserkers", "zerker", "zerkers", "savage",
        "savages", "hunter", "hunters", "shadowblade", "shadowblades", "sb", "sbs", "healer", "healers", "shaman", "shamans",
        "shammy", "runemaster", "runemasters", "rm", "rms", "spiritmaster", "spiritmasters", "sm", "sms", "bonedancer",
        "bonedancers", "bd", "bds", "hero", "heroes", "champion", "champions", "champ", "champs", "blademaster", "blademasters",
        "bm", "bms", "warden", "wardens", "druid", "druids", "bard", "bards", "ranger", "rangers", "nightshade", "nightshades",
        "ns", "eldritch", "eldritches", "eld", "enchanter", "enchanters", "ench", "mentalist", "mentalists", "menta", "animist",
        "animists", "valewalker", "valewalkers", "vw");

    private static readonly HashSet<string> ResistKinds = Set("heat", "cold", "matter", "body", "spirit", "energy", "crush", "slash", "thrust",
        "magic", "melee", "resist", "resists");
    private static readonly HashSet<string> ResistUses = Set("gear", "cap", "capped", "buff", "buffs", "cloak", "jewel", "jewelry", "item",
        "items", "armor", "piece", "pieces");

    /// <summary>"res" meaning a resist: "heat res gear", "what res should i cap" (review 2026-10-18).</summary>
    private static bool IsResist(string[] words)
    {
        for (int i = 0; i < words.Length; i++)
        {
            if (words[i] is not ("res" or "ress"))
                continue;
            if (i > 0 && ResistKinds.Contains(words[i - 1]) || i + 1 < words.Length && ResistUses.Contains(words[i + 1]) ||
                i + 3 < words.Length && (words[i + 2] is "cap" or "capped" || words[i + 3] is "cap" or "capped"))
                return true;
        }
        return false;
    }

    /// <summary>The class words in a text ("friar", "zerkers", "sm").</summary>
    public static string[] ClassWordsIn(string text) =>
        AutonomousChatIntentModel.Words(text).Where(ClassWords.Contains).Distinct().ToArray();

    /// <summary>True when a text names any class.</summary>
    public static bool NamesAClass(string text) => AutonomousChatIntentModel.Words(text).Any(ClassWords.Contains);

    /// <summary>"friar" and "friars", "zerker" and "zerkers": the same class word, singular or plural.</summary>
    public static bool SameClassWord(string a, string b) =>
        string.Equals(a.TrimEnd('s'), b.TrimEnd('s'), StringComparison.OrdinalIgnoreCase);

    /// <summary>"how are you?", "hows everyone", "sup": a greeting that asks back, answered "not bad, you?" rather than "hi"
    /// (live test 2026-10-18: "hi all" drew "not bad, and you?").</summary>
    public static bool AsksHowAreYou(string text) =>
        HasPhrase(AutonomousChatIntentModel.Words(text).Select(word => word.Replace("'", string.Empty)).ToArray(),
            "how are you", "how are u", "how r u", "how r you", "how are ya", "how are yall", "how is everyone", "how is everybody",
            "hows everyone", "hows everybody", "hows it going", "how is it going", "how are things", "hows things", "how you doing",
            "how u doing", "how ya doing", "how goes it", "whats up", "wassup", "sup");

    /// <summary>"anyone on?", "anybody here?", "whos on": asks who is around, answered "here" or "im on" (live test
    /// 2026-10-18: /gu "anyone on?" drew "good question, someone else might know").</summary>
    public static bool AsksWhoIsOn(string text)
    {
        string[] words = AutonomousChatIntentModel.Words(text).Select(word => word.Replace("'", string.Empty)).ToArray();
        return words.Length <= 5 && HasPhrase(words, "anyone on", "anybody on", "any1 on", "anyone here", "anybody here", "anyone around",
            "anybody around", "anyone awake", "anyone online", "anybody online", "who is on", "whos on", "whos around", "who is around",
            "anyone still on", "anyone still up", "anyone up");
    }

    /// <summary>The question type a player's line asks, answered from that reply set before replies by topic: "ask_howareyou",
    /// "ask_on", or null.</summary>
    public static string QuestionShape(string text)
    {
        // "ok", "sure", "nice", "me too": an acknowledgement, which nobody answers (chat audit 2026-10-21: "yes" drew
        // "interesting", "sure" drew "lol what", "nice" drew "ouch been there").
        if (IsAcknowledgement(text))
            return "ack";
        if (AsksHowAreYou(text))
            return "ask_howareyou";
        if (AsksWhoIsOn(text))
            return "ask_on";
        // "where is everyone?" in /gu asks where the guild is, not for directions (played 2026-10-18: it read as travel).
        string[] where = AutonomousChatIntentModel.Words(text).Select(word => word.Replace("'", string.Empty)).ToArray();
        if (HasPhrase(where, "where is everyone", "wheres everyone", "where is everybody", "wheres everybody", "where did everyone go",
                "where is the guild", "where are you all", "where are you guys", "where r u all", "where is everyone at",
                "where yall at", "where are yall", "where all you at"))
            return "ask_whereall";
        string[] words = AutonomousChatIntentModel.Words(text).Select(word => word.Replace("'", string.Empty)).ToArray();
        // "what level are you?" in /group drew "sure Wrenfield, what do you need?" (live test 2026-10-18).
        if (HasPhrase(words, "what level are you", "what lvl are you", "what level r u", "what lvl r u", "whats your level", "whats ur level",
                "what level is everyone", "what lvl is everyone", "what level are you all", "how high are you"))
            return "ask_level";
        if (HasPhrase(words, "how close are you to", "how close r u to", "how close is everyone to", "how far to your next level"))
            return "ask_xp";
        // "where to next?" in a group: the next hunt, not directions (live test 2026-10-18).
        if (HasPhrase(words, "where to next", "where now", "where next", "where are we heading", "where are we going", "where should we go",
                "where should we head", "where we going", "where we heading"))
            return "ask_next";
        // "what are you up to?" in /gu drew "lol what" (live test of 0.37-se.1, 2026-10-18): what the bot is doing now, or,
        // with "tonight" or "later", its plans.
        if (HasPhrase(words, "what are we doing", "what are we up to", "what r we doing", "what r we up to"))
            return "ask_plans";
        if (HasPhrase(words, "what are you up to", "what r u up to", "what are u up to", "what you up to", "what u up to",
                "what are you doing", "what r u doing", "what are u doing", "what you doing", "whatcha doing", "wyd",
                "what is everyone up to", "whats everyone up to", "what is everyone doing", "whats everyone doing",
                "what are you all up to", "what are you guys up to", "what are you all doing", "what are you guys doing",
                "what is everybody up to", "whats everybody up to", "whats everybody doing", "what are yall up to"))
            return HasPhrase(words, "tonight", "later", "tomorrow", "this weekend") ? "ask_plans" : "ask_doing";
        // "lf guild" that no bot guild took up (already in a guild, bot guilds off) drew "i could use a group too".
        if (AutonomousBotGuildChatLines.AsksForGuild(text, false))
            return "ask_guild";
        // "mind if i hunt near cotswold?" drew "what?" and "yeah?" (live test 2026-10-18).
        if (HasPhrase(words, "mind if i", "ok if i", "okay if i", "is it ok if", "alright if i", "anyone mind if"))
            return "ask_permission";
        // "should i roll a cleric or a friar?"
        if (IsEitherOr(text))
            return "ask_choice";
        // Chat audit 2026-10-21: these fell to replies by topic that did not answer them ("where is a good place to level at 24?"
        // drew "take the horse from Camelot", "anyone in camelot?" "maybe maybe not", "how much is a bloodied sword worth?"
        // "not my class sorry", "anyone want to do a dungeon?" "take it slow, one pull at a time", "i died again" "what?").
        if (AutonomousBotChatCoordinator.AsksWhereYouAre(text))
            return "ask_whereyou";
        if (PlaceAsked(text) != null)
            return "ask_inplace";
        if (HasPhrase(words, "good place to level", "good place to hunt", "good spot to level", "good spot for", "good camp for",
                "good place for", "good xp for", "where is good xp", "wheres good xp", "where to level", "where to hunt", "where should i level",
                "where should i hunt", "where can i level", "where can i hunt", "where do i level", "where do i hunt", "where is a good camp",
                "wheres a good camp", "where is a good spot", "wheres a good spot", "where is a good place", "wheres a good place",
                "where do people level", "where do people hunt", "where is everyone leveling", "where are people leveling"))
            return "ask_hunt";
        if (HasPhrase(words, "where are the mids", "where are the hibs", "where are the albs", "where are the enemies", "where is the enemy",
                "wheres the enemy", "where is the zerg", "wheres the zerg", "where did the zerg go", "any mids out", "any hibs out", "any albs out",
                "seen any mids", "seen any hibs", "seen any albs", "any enemies out", "where is the fight", "wheres the fight", "where is the action",
                "wheres the action"))
            return "ask_enemy";
        if (HasPhrase(words, "how much", "price check", "pc on", "what do they go for", "what does it go for", "what do these go for",
                "what are they worth", "what is it worth") || words.Contains("worth") && HasPhrase(words, "what is", "whats", "what are"))
            return "ask_price";
        if (!words.Any(GroupWords.Contains) && HasPhrase(words, "anyone want to", "anyone wanna", "anyone going", "anyone up for",
                "anyone feel like", "anybody want to", "anybody wanna", "anybody going", "anybody up for", "any1 want to", "any1 wanna",
                "who wants to", "who wants", "who is up for", "whos up for", "anyone doing", "anyone running", "anyone heading", "anyone coming",
                "anybody coming", "anyone interested in", "anyone keen"))
            return "ask_anyone";
        if (HasPhrase(words, "best spec", "what spec", "which spec", "how should i spec", "how do i spec", "how to spec", "any tips",
                "any advice", "tips for", "advice for", "how do i make money", "how do i get money", "how to make money", "how do i get gold",
                "how do i make gold", "how do i get coin", "how do i make coin", "how do i get plat", "how do i make plat", "how do i level",
                "how do i solo", "how to level", "how to solo", "how do i get better", "how do i get good"))
            return "ask_advice";
        if (HasPhrase(words, "what should i do", "what do i do now", "what do i do next", "what should i do next", "what now"))
            return "ask_advice";
        if (HasPhrase(words, "can you help", "can someone help", "can anyone help", "can somebody help", "help me", "i need help", "need help",
                "anyone help", "could use some help", "could use help") && words.Length <= 6)
            return "ask_help";
        if (text.Contains('?') && (words.Contains("worth") || HasPhrase(words, "do you think", "would you", "is it smart", "is it a good idea",
                "good idea to") || HasPhrase(words, "should i") && !words.Any(word => word is "what" or "where" or "how" or "which" or "when" or "who")))
            return "ask_opinion";
        if (!text.Contains('?') && (HasPhrase(words, "i died", "died again", "keep dying", "we wiped", "i give up", "so slow", "hate this",
                "this is hard", "fml", "lost my", "no drops", "nothing drops", "so tired of", "cant win", "can't win", "got ganked", "ganked again") ||
                words.Any(word => word is "sucks" or "ugh" or "annoying" or "wiped" or "argh" or "sigh")))
            return "complaint";
        return null;
    }

    /// <summary>"cleric or friar?", "polearm or two handed?": a question between two things. Not "is it just me or...",
    /// "or am i doing it wrong", "or what" (chat audit 2026-10-21: "is the enchanter pet worth it or just a buffbot?" drew
    /// "second one imo").</summary>
    public static bool IsEitherOr(string text)
    {
        if (string.IsNullOrEmpty(text) || !text.Contains('?'))
            return false;
        string[] words = AutonomousChatIntentModel.Words(text).Select(word => word.Replace("'", string.Empty)).ToArray();
        return words.Contains("or") && !HasPhrase(words, "or something", "or anything", "or what", "or so", "or not", "or is it just me",
            "or is that just me", "or just me", "or is it me", "or am i", "or is that a myth", "or is that true", "or just a", "or no",
            "or nah", "or is it", "or is that");
    }

    /// <summary>"really?", "what?", "why?", "srsly": a two-word follow-up to something else that was said, which only the
    /// one it was said to can answer.</summary>
    public static bool IsFollowUp(string text)
    {
        string[] words = AutonomousChatIntentModel.Words(text);
        return words.Length is > 0 and <= 2 && words.All(word => word is "really" or "what" or "why" or "how" or "huh" or "srsly" or
            "seriously" or "for" or "real" or "wait" or "who" or "when" or "where" or "which" or "rly" or "wut" or "wat" or "eh" or "sorry");
    }

    private static readonly HashSet<string> AckWords = Set("yes", "yeah", "yea", "ya", "yep", "yup", "no", "nope", "nah", "ok", "okay",
        "k", "kk", "sure", "cool", "nice", "same", "true", "right", "agreed", "agree", "maybe", "alright", "aight", "fair", "indeed",
        "exactly", "word", "mhm", "hm", "hmm", "oh", "ah", "ahh", "see", "me", "too", "got", "gotcha", "understood", "noted", "makes",
        "sense", "sounds", "good", "fine", "neat", "great", "perfect", "def", "definitely", "probably", "prolly", "guess", "suppose",
        "same", "here", "true", "ikr", "totally", "either", "neither", "thats", "that's", "is", "was", "really", "yeh", "ye");

    /// <summary>"ok", "sure", "nice", "me too", "makes sense": a line that only acknowledges what was said.</summary>
    public static bool IsAcknowledgement(string text)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Contains('?'))
            return false;
        string[] words = AutonomousChatIntentModel.Words(text);
        return words.Length is > 0 and <= 5 && Only(words, AckWords) && !words.All(word => word is "i" or "me" or "is" or "was" or "here" or "see");
    }

    private static readonly System.Text.RegularExpressions.Regex PlacePattern = new(
        @"^(?:is |are )?(?:there )?(?:anyone|anybody|any1|someone|somebody|any (?:albs?|mids?|hibs?|players?|people|one|body))(?: still)? (?:in|at|near|around|by|over in) (?:the )?([a-z' ]{3,40}?)\s*\??$",
        System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    /// <summary>The place in "anyone in camelot?", "any albs near cotswold?", or null.</summary>
    public static string PlaceAsked(string text)
    {
        string t = string.Join(' ', AutonomousChatIntentModel.Words(text));
        var match = PlacePattern.Match(t + (text?.TrimEnd().EndsWith('?') == true ? "?" : ""));
        if (!match.Success)
            return null;
        string place = match.Groups[1].Value.Trim();
        return place is "a group" or "group" or "a guild" or "guild" or "game" or "the game" or "here" or "town" || place.Length < 3 ? null : place;
    }

    /// <summary>
    /// False for a reply that asks what the line already said: "what lvl?" to "paladin 6 here" (live test 2026-10-18).
    /// </summary>
    public static bool ReplyFits(string incoming, string reply)
    {
        if (string.IsNullOrEmpty(incoming) || string.IsNullOrEmpty(reply))
            return true;
        string[] words = AutonomousChatIntentModel.Words(reply);
        bool asksLevel = HasPhrase(words, "what lvl", "what level", "level range", "what level are you", "what lvl are you", "how high are you");
        if (asksLevel && incoming.Any(char.IsDigit))
            return false;
        // "lfg 50 reaver will travel" drew "what class are u?".
        bool asksClass = HasPhrase(words, "what class", "which class", "what are you playing", "what r u playing");
        if (asksClass && NamesAClass(incoming))
            return false;
        // "lfg" is a player looking for a group, not one with a group (in-game check 2026-10-18: "lfg 50 cleric, in camelot"
        // drew "how many do u have?"). Lines that assume the asker leads a group fit "lfm", not "lfg".
        string[] said = AutonomousChatIntentModel.Words(incoming);
        bool seeksGroup = (HasPhrase(said, "lfg", "looking for group", "looking for a group") || said.Contains("lf")) &&
                          !HasPhrase(said, "lfm", "looking for more", "lf1m", "lf2m", "lf3m");
        bool assumesGroup = HasPhrase(words, "how many do you have", "how many do u have", "need a healer still",
            "still need someone", "if you still need someone", "how many u got", "how many are u", "how many are you", "fill a spot",
            "if u inv", "if you inv", "pst me when u form", "pst me when you form", "when u form up", "when you form up");
        if (seeksGroup && assumesGroup)
            return false;
        // Chat audit 2026-10-21: "two handed or sword and board?" drew "imo yes"; "anyone selling a staff?" drew "i would just
        // vendor it"; "how much is it worth?" drew "how much?".
        string replyText = string.Join(' ', words);
        bool eitherOr = IsEitherOr(incoming);
        if (eitherOr && words.Length <= 4 && HasPhrase(words, "imo yes", "imo no", "yes do it", "i would", "i wouldnt", "go for it",
                "worth it imo", "not worth it", "yes", "no", "do it"))
            return false;
        bool buying = HasPhrase(said, "wtb", "anyone selling", "anybody selling", "want to buy", "looking to buy", "looking for a", "need a",
            "where can i buy", "where do i buy", "anyone have a", "anyone got a");
        if (buying && HasPhrase(words, "vendor it", "worth something", "what its worth", "pst me the stats", "gl selling", "gl with the sale",
                "is it still up", "what are you asking", "no idea what its worth", "someone will want it", "hold onto it", "post it on",
                "upgrade for an alt", "list it", "sell it", "who is buying", "whos buying", "merchants pay half"))
            return false;
        if (HasPhrase(words, "wts or wtb") && (said.Any(word => word is "wts" or "wtb" or "selling" or "buying" or "sell" or "buy")))
            return false;
        bool asksPrice = HasPhrase(said, "how much", "price check", "pc on") || said.Contains("worth");
        if (asksPrice && (HasPhrase(words, "how much", "whats the price", "what are you asking", "what price") || replyText == "price"))
            return false;
        return true;
    }

    public static bool HasPhrase(string[] words, params string[] phrases)
    {
        string text = " " + string.Join(' ', words) + " ";
        return phrases.Any(phrase => text.Contains(" " + phrase + " ", StringComparison.Ordinal));
    }

    private static bool Any(string[] words, HashSet<string> set) => words.Any(set.Contains);

    private static bool Only(string[] words, params HashSet<string>[] sets) =>
        words.Any(word => sets.Any(set => set.Contains(word))) && words.All(word => sets.Any(set => set.Contains(word)) || IsNoise(word));

    /// <summary>Filler a short message can carry without changing what it is ("ty all", "lol ok", "back now").</summary>
    private static bool IsNoise(string word) => word is "all" or "u" or "you" or "ya" or "guys" or "man" or "dude" or "much" or
        "so" or "very" or "again" or "now" or "ok" or "k" or "kk" or "np" or "and" or "everyone" or "for" or "the" or "a" or
        "that" or "it" or "im" or "i'm" or "i" or "am" or "all" or "m8" or "mate" or "bud" or "buddy" or "friend" or "sir" or
        "bro" or "too" or "lol" or "heh" or "haha" or ":)" or "x" or "xx" or "o";

    /// <summary>
    /// What a short or common chat line is, or false to let the classifier decide. <paramref name="words"/>
    /// are the message's lower-case words (single letters and digits kept).
    /// </summary>
    public static bool TryRead(string text, string[] words, out eAutonomousChatIntent intent)
    {
        intent = eAutonomousChatIntent.Unknown;
        if (words == null || words.Length == 0)
        {
            // ":)" ";p" "o/" and the like
            string raw = (text ?? string.Empty).Trim();
            if (raw is "o/" or "\\o" or "o7")
            {
                intent = eAutonomousChatIntent.Greeting;
                return true;
            }
            if (raw.Length > 0 && raw.Length <= 4 && !raw.All(c => c == '?') &&
                raw.All(c => !char.IsLetterOrDigit(c) || c is 'p' or 'P' or 'D' or 'o' or 'O'))
            {
                intent = eAutonomousChatIntent.Laugh;
                return true;
            }
            return false;
        }
        bool question = (text ?? string.Empty).Contains('?');
        int n = words.Length;

        // "are you a bot?", "r u real?", "is this an npc"
        if (Any(words, BotWords) && (HasPhrase(words, "are you", "r u", "are u", "you a", "u a", "is this", "you an", "u an", "you're a",
                "youre a", "ur a", "is he", "is she", "are they", "are all", "are these", "like a", "type like") || n <= 3 && question) ||
            HasPhrase(words, "are you real", "r u real", "are u real", "are you human", "r u human", "are u human", "real person",
                "you even real", "u even real", "you a real", "u a real", "even human", "all bots", "you bots", "u bots", "ur bots",
                "real player", "real people"))
            return Is(eAutonomousChatIntent.BotCheck, out intent);

        bool thanks = Any(words, ThanksWords) || HasPhrase(words, "thank you", "much appreciated", "appreciate it");
        // "ty for the rez" is thanks; "rez pls", "need a rez", "anyone rez?", "rez pls ty" ask for one. "heat res gear" is a resist.
        bool sickness = words.Contains("sick") || words.Contains("sickness");
        bool rezWord = Any(words, RezWords) && !IsResist(words);
        bool asking = question || HasPhrase(words, "need a", "need rez", "can someone", "can anyone", "anyone", "pls", "please", "plz",
            "rez me", "res me", "rez pls", "rezz me");
        if (rezWord && !sickness && (asking || !thanks && n <= 6))
            return Is(eAutonomousChatIntent.Rez, out intent);
        if (thanks)
            return Is(eAutonomousChatIntent.Thanks, out intent);

        // "gz on the ding" and "nice ding" congratulate someone; "ding!", "ding 20", "finally 35" announce one's own.
        bool praise = Any(words, CongratsWords) || words[0] is "nice" or "gj" or "wtg" or "woot";
        if (praise && (Any(words, CongratsWords) || words.Contains("ding")))
            return Is(eAutonomousChatIntent.Congrats, out intent);
        if (words.Contains("ding") || words.Contains("dinged") || HasPhrase(words, "just dinged", "hit level", "made level") ||
            words.Contains("finally") && words.Any(word => int.TryParse(word, out int level) && level is >= 2 and <= 50) &&
            (n <= 3 || words.Contains("level") || words.Contains("lvl")))
            return Is(eAutonomousChatIntent.Ding, out intent);

        if (n <= 6 && (Any(words, AwayWords) || HasPhrase(words, "be right back", "be back in", "one sec", "1 sec", "afk for")) &&
            !HasPhrase(words, "im back", "i'm back", "back now"))
            return Is(eAutonomousChatIntent.Away, out intent);
        if (n <= 3 && Only(words, BackWords) || n <= 6 && (HasPhrase(words, "im back", "i'm back", "back now", "back again") ||
                words[0] == "back" && n <= 2 || n > 1 && words[0] is "ok" or "k" or "and" or "aaand" && words[1] == "back"))
            return Is(eAutonomousChatIntent.Back, out intent);
        if (words[0] == "wb" && n <= 3)
            return Is(eAutonomousChatIntent.Greeting, out intent);

        // "hi", "hey all", "hail Haralhelm", "evening folks" (a greeting with a question after it is a question)
        if (GreetingWords.Contains(words[0]) && !question &&
            (n == 1 || n == 2 && !Any(words, GroupWords) && !Any(words, TradeWords) && !Any(words, AlarmWords) ||
             n <= 4 && words.Skip(1).All(word => GreetingObjects.Contains(word) || IsNoise(word))))
            return Is(eAutonomousChatIntent.Greeting, out intent);
        if (HasPhrase(words, "good morning", "good evening", "good afternoon", "how is everyone", "hows everyone", "how's everyone",
                "whats up", "what's up", "how goes it"))
            return Is(eAutonomousChatIntent.Greeting, out intent);

        // "inc", "inc 10 mids at amg", "zerg at the mile gate"
        if (Any(words, AlarmWords) || HasPhrase(words, "under attack", "under siege", "albs at", "mids at", "hibs at",
                "enemies at", "enemy at", "stealthers at", "zerg at"))
            return Is(eAutonomousChatIntent.Alarm, out intent);

        if (Any(words, TradeWords) || HasPhrase(words, "how much", "price check", "anyone selling", "anyone buying", "what's it worth",
                "whats it worth"))
            return Is(eAutonomousChatIntent.Trading, out intent);
        if (Any(words, GroupWords) || HasPhrase(words, "looking for", "need a healer", "need a tank", "need healer", "need tank",
                "room for", "want to team", "team up"))
            return Is(eAutonomousChatIntent.Grouping, out intent);

        if (n <= 6 && Any(words, FarewellWords) || HasPhrase(words, "logging off", "log off", "heading to bed", "off to bed",
                "going to bed", "good night", "night all", "night everyone", "gotta go", "got to go", "calling it", "im out", "i'm out",
                "see you later", "see ya later", "later all", "later guys", "later everyone"))
            return Is(eAutonomousChatIntent.Farewell, out intent);

        if (HasPhrase(words, "need puller", "need a puller", "up for", "1 more", "one more", "anyone forming", "group up"))
            return Is(eAutonomousChatIntent.Grouping, out intent);
        if (HasPhrase(words, "how do i get", "how do you get", "how far", "which way", "where is", "wheres", "where's", "where are the",
                "where can i", "where do i", "how to get", "stable master", "stablemaster", "horse to", "ticket to", "im lost", "i'm lost",
                "lost again", "i am lost"))
            return Is(eAutonomousChatIntent.Travel, out intent);
        if (Any(words, GankWords) && !Any(words, DungeonWords))
            return Is(eAutonomousChatIntent.RvR, out intent);

        // Class and spec talk: "is friar good?", "best spec for a cleric", "scouts op", "zerkers got nerfed", "bard or druid?"
        bool classWord = Any(words, ClassWords) || words.Contains("class") || words.Contains("classes");
        if (classWord && n <= 10 || Any(words, SpecWords) && (question || Any(words, OpinionWords)))
            return Is(eAutonomousChatIntent.ClassTalk, out intent);

        if (Any(words, DungeonWords))
            return Is(eAutonomousChatIntent.Dungeon, out intent);
        if (Any(words, RvrWords) || HasPhrase(words, "the keep", "our keep", "their keep", "keep raid", "keep take", "the lord",
                "the frontier", "relic raid", "realm war"))
            return Is(eAutonomousChatIntent.RvR, out intent);
        if (HasPhrase(words, "good xp", "good exp", "where to level", "where to lvl", "good spot", "good camp", "xp spot", "level at",
                "lvl at", "camp at", "hunting at", "where should i hunt", "where to hunt", "should i hunt", "how long to", "camping",
                "where do people level", "xp at"))
            return Is(eAutonomousChatIntent.Grinding, out intent);
        if (HasPhrase(words, "how do i", "how does", "what do i", "what should i", "can someone help", "can anyone help", "need help",
                "help me", "any tips", "any advice", "what level", "what lvl", "when do i", "trainer", "how do you", "what does",
                "what is a", "whats a", "buff me", "buffs", "can i get") ||
            words.Contains("mean") && (words.Contains("what") || words.Contains("whats") || words.Contains("does")))
            return Is(eAutonomousChatIntent.Help, out intent);

        // "lol", "haha ok", "gg" with nothing else; "same", "true", "ouch" are a nod
        if (Only(words, LaughWords) && !Only(words, BanterWords))
            return Is(eAutonomousChatIntent.Laugh, out intent);
        if (n <= 3 && Only(words, BanterWords, LaughWords))
            return Is(eAutonomousChatIntent.Banter, out intent);
        if (n <= 2 && words.All(word => word is "noob" or "n00b" or "newb" or "nub" or "pff" or "pfft" or "meh"))
            return Is(eAutonomousChatIntent.Banter, out intent);
        return false;
    }

    private static bool Is(eAutonomousChatIntent value, out eAutonomousChatIntent intent)
    {
        intent = value;
        return true;
    }
}
