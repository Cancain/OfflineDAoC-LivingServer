namespace OfflineDaoc.Launcher;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--prepare-portable-account")
        {
            // the new client's launcher keeps its account with the game it plays (server_root.txt)
            PortableCredentials.ReadOrCreate(MainForm.ServerRootFor(AppContext.BaseDirectory));
            return;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}
