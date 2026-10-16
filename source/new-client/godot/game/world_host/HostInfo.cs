// Bot plan phase 3: the C# side of the game (the bot world's core). A first class so the assembly builds and the
// game can check that C# is loaded (tests/dotnet_probe.gd).
using Godot;

namespace MMOEngine;

[GlobalClass]
public partial class HostInfo : RefCounted
{
	public static string Version => "phase3-0";

	public string Hello() => $"MMOEngine C# core {Version} on .NET {System.Environment.Version}";

	// The C# side calls the game's own GDScript rules (one owner per rule): a bot is made by CharacterFactory.
	public Godot.Collections.Dictionary MakeBot(string realm, int seed)
	{
		var factory = GD.Load<GDScript>("res://game/character_factory.gd");
		return factory.Call("random_character", realm, seed).AsGodotDictionary();
	}
}
