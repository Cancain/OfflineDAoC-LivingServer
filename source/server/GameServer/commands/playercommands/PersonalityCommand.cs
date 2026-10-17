using DOL.GS.PacketHandler;

namespace DOL.GS.Commands
{
	/// <summary>Shows a targeted autonomous gamebot's personality (docs/BOT-PERSONALITIES.md).</summary>
	[CmdAttribute(
		"&personality",
		ePrivLevel.Player,
		"Shows the personality of the autonomous gamebot you have targeted",
		"/personality (with a gamebot targeted)")]
	public class PersonalityCommandHandler : AbstractCommandHandler, ICommandHandler
	{
		public void OnCommand(GameClient client, string[] args)
		{
			if (client.Player.TargetObject is not GameBot bot || !bot.IsAutonomousWorldBot || bot.DatabaseID <= 0)
			{
				DisplayMessage(client, "Target an autonomous gamebot first.");
				return;
			}
			if (bot.Realm != client.Player.Realm && client.Account.PrivLevel <= 1)
			{
				DisplayMessage(client, "You can only read the personality of your own realm's bots.");
				return;
			}
			string state = AutonomousBotPersonality.Enabled ? string.Empty : " (personalities are switched off, so it doesn't act on it)";
			string voice = AutonomousBotVoices.Corpus?.VoiceFor(bot.DatabaseID).Name;
			string voiceText = voice == null ? string.Empty : $"; writes {voice}{(AutonomousBotVoices.Enabled ? string.Empty : " (voices off)")}";
			client.Out.SendMessage($"{bot.Name}: {AutonomousBotPersonality.Describe(AutonomousBotPersonality.For(bot))}{state}{voiceText}",
				eChatType.CT_System, eChatLoc.CL_SystemWindow);
		}
	}
}
