using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace LivingServerSetup
{
    internal static class Program
    {
        public const string ProjectUrl = "https://github.com/chris4aker/OfflineDAoC-LivingServer";
        public static bool IsWindows => Environment.OSVersion.Platform == PlatformID.Win32NT;
        public static bool Silent;
        public static bool DemoMode;

        [STAThread]
        static int Main(string[] argv)
        {
            var args = new Args(argv);
            Silent = args.Has("--silent");
            if (Silent && IsWindows) AttachConsole(-1);
            try
            {
                Log.FilePath = args.Get("--log") ?? Path.Combine(Path.GetTempPath(), "LivingServer-Setup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log");
                Log.Write("Offline DAoC Living Server Setup " + typeof(Program).Assembly.GetName().Version + " on " + Environment.OSVersion + (Environment.Is64BitOperatingSystem ? " (64-bit)" : ""));
                if (Silent) Log.Written += line => { try { Console.WriteLine(line); } catch { } };
                Payload.Load();
                Log.Write("Living Server package: " + Payload.BuildName + " (" + Payload.DisplayName + ") for Offline DAoC " + Payload.BaseRelease + ", commit " + Payload.Commit);
            }
            catch (Exception e)
            {
                Fail("Setup can't start: " + e.Message);
                return 3;
            }

            if (args.Has("--info")) return 0;
            if (args.Has("--scan"))
            {
                foreach (var p in GameScanner.FindGames(Path.GetDirectoryName(Application.ExecutablePath)).Concat(args.All("--game")))
                {
                    var g = GameScanner.Inspect(p);
                    Log.Write("GAME " + g.Path + " | " + g.Edition + " | LivingServer=" + g.Ls + (g.LsBuild != null ? " (" + g.LsBuild + ")" : "") + " | base=" + g.IsBase + " updatable=" + g.IsUpdatable);
                }
                return 0;
            }

            if (Silent) return RunSilent(args);

            using (var single = new Mutex(true, @"Local\OfflineDAoC-LivingServer-Setup", out bool first))
            {
                if (!first && !args.Has("--screenshots"))
                {
                    MessageBox.Show("Living Server Setup is already open.", "Offline DAoC: Living Server Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.ThreadException += (s, e) => Crash(e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Crash(e.ExceptionObject as Exception);
                using (var probe = new Form())
                using (var gfx = probe.CreateGraphics())
                    Theme.Scale = args.Get("--scale") != null ? float.Parse(args.Get("--scale"), System.Globalization.CultureInfo.InvariantCulture) : Math.Max(1f, gfx.DpiX / 96f);
                Log.Write("Display scale " + Theme.Scale.ToString("0.##"));

                if (args.Get("--screenshots") != null) return Screenshots(args.Get("--screenshots"));

                var form = new SetupForm();
                form.Load += (s, e) => form.Wizard.Welcome();
                Application.Run(form);
            }
            return 0;
        }

        static void Crash(Exception e)
        {
            Log.Write("Unexpected error: " + e);
            try
            {
                MessageBox.Show("Something went wrong in Setup:\n\n" + e?.Message + "\n\nThe log is at " + Log.FilePath, "Offline DAoC: Living Server Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            catch { }
        }

        static void Fail(string message)
        {
            Log.Write(message);
            if (!Silent) { try { MessageBox.Show(message, "Offline DAoC: Living Server Setup", MessageBoxButtons.OK, MessageBoxIcon.Error); } catch { } }
        }

        [DllImport("kernel32.dll")] static extern bool AttachConsole(int pid);

        public static void Open(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
            catch (Exception e) { Log.Write("Couldn't open " + path + ": " + e.Message); }
        }

        public static void OpenUrl(string url) => Open(url);

        // ------------------------------------------------------------------------------------------ silent / tests

        static int RunSilent(Args a)
        {
            var o = new InstallOptions
            {
                Shortcuts = !a.Has("--no-shortcuts"),
                EnableNetFx = a.Has("--netfx"),
                LocalAssets = a.Get("--local-assets"),
                ForceLivingServer = a.Has("--force"),
                FreshCopyIfChanged = a.Has("--fresh-copy"),
            };
            if (a.Has("--new"))
            {
                o.NewInstall = true;
                o.Destination = a.Get("--dest") ?? Wizard.DefaultFolder();
                o.Classic = a.Has("--classic");
                o.NewClient = a.Has("--new-client");
                if (a.Get("--import-from") != null) o.ImportFrom = GameScanner.Inspect(a.Get("--import-from"));
            }
            else if (a.Get("--game") != null)
            {
                if (!GameScanner.IsGame(a.Get("--game"))) { Log.Write("No Offline DAoC game in " + a.Get("--game")); return 3; }
                o.Game = GameScanner.Inspect(a.Get("--game"));
                o.AddClient = a.Has("--add-client");
                o.Remove = a.Has("--remove");
                Log.Write("Game: " + o.Game.Title + ", Living Server " + o.Game.Ls + (o.Game.LsBuild != null ? " (" + o.Game.LsBuild + ")" : ""));
                if (!o.Remove && o.Game.CompareToBase() > 0) { Log.Write("This game is newer than " + Payload.BaseRelease + "."); return 3; }
                if (!o.Remove && !o.Game.IsBase && !o.Game.IsUpdatable) { Log.Write("This game is too old to update; use --new (with --import-from)."); return 3; }
            }
            else
            {
                Log.Write("Usage: LivingServerSetup.exe --silent (--new [--dest DIR] [--classic] [--new-client] [--import-from DIR] | --game DIR [--add-client] [--remove] [--force] [--fresh-copy]) [--no-shortcuts] [--netfx] [--local-assets DIR] [--log FILE]");
                return 3;
            }
            if (!a.Has("--offline")) Manifests.TryRefresh();
            var engine = new Engine(o);
            string lastStatus = null;
            int lastPct = -1;
            engine.Changed += () =>
            {
                var pct = (int)(engine.Overall * 100);
                if (engine.Status != lastStatus || pct / 5 != lastPct / 5)
                {
                    lastStatus = engine.Status; lastPct = pct;
                    Log.Write("[" + pct.ToString().PadLeft(3) + "%] " + engine.Status + (string.IsNullOrEmpty(engine.Detail) ? "" : " | " + engine.Detail));
                }
            };
            Log.Write("Plan: " + string.Join(" > ", engine.Items.Select(i => i.Title)));
            var r = engine.Run();
            foreach (var i in engine.Items) Log.Write("STEP " + i.State + ": " + i.Title + (string.IsNullOrEmpty(i.Detail) ? "" : " (" + i.Detail + ")"));
            Log.Write("RESULT " + r.Outcome + (r.Message != null ? ": " + r.Message : "") + (r.Hint != null ? " | " + r.Hint : "") +
                      (r.CanForce ? " [can --force]" : "") + (r.CanFreshCopy ? " [can --fresh-copy]" : "") + " | game " + r.GamePath);
            return r.Outcome == Outcome.Success ? 0 : r.Outcome == Outcome.Cancelled ? 2 : 1;
        }

        // ------------------------------------------------------------------------------------------ screenshots

        static int Screenshots(string dir)
        {
            DemoMode = true;
            Directory.CreateDirectory(dir);
            var form = new SetupForm { StartPosition = FormStartPosition.Manual, Location = new Point(20, 20), ShowInTaskbar = false };
            var wz = form.Wizard;
            wz.Scanned = true;
            wz.Games = Demo.Games();
            var shots = new List<(string, Action)>
            {
                ("01-welcome", () => wz.Welcome()),
                ("02-choose", () => wz.Choose()),
                ("03-prepare-new", () => { wz.Chosen = null; wz.Options = null; wz.Prepare(); }),
                ("04-prepare-update", () => { wz.Chosen = wz.Games[1]; wz.Prepare(); }),
                ("05-prepare-installed", () => { wz.Chosen = wz.Games[0]; wz.Prepare(); }),
                ("06-install", () => { wz.Install(new InstallOptions { NewInstall = true, Destination = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b", NewClient = true, Shortcuts = true, EnableNetFx = true }); }),
                ("07-done", () => { wz.Options = new InstallOptions { NewInstall = true, Destination = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b" }; wz.Finished(Demo.Success()); }),
                ("08-failed", () => { wz.Finished(Demo.Failure()); }),
            };
            form.Show();
            foreach (var (name, show) in shots)
            {
                show();
                Pump(900);
                Capture(form, Path.Combine(dir, name + ".png"));
            }
            // the themed dialog over the install page
            wz.Install(new InstallOptions { NewInstall = true, Destination = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b", Shortcuts = true });
            Pump(400);
            var dlg = typeof(Dialog);
            var t = new System.Windows.Forms.Timer { Interval = 700 };
            t.Tick += (s, e) =>
            {
                t.Stop();
                var open = Application.OpenForms.OfType<Form>().FirstOrDefault(f => f.GetType() == dlg);
                if (open != null) { Capture(form, Path.Combine(dir, "09-dialog.png"), open); open.Close(); }
            };
            t.Start();
            Dialog.Show(form, "Stop installing?", "Finished downloads are kept. Run Setup again and choose the same options to continue where it stopped.", "Keep going", "Stop");
            form.Hide();
            Log.Write("Screenshots written to " + dir);
            Environment.Exit(0);
            return 0;
        }

        static void Pump(int ms)
        {
            var until = DateTime.UtcNow.AddMilliseconds(ms);
            while (DateTime.UtcNow < until) { Application.DoEvents(); Thread.Sleep(15); }
        }

        static void Capture(Form form, string path, Form over = null)
        {
            Pump(150);
            var bounds = form.Bounds;
            using (var bmp = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb))
            {
                bool ok = false;
                try
                {
                    using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
                    ok = !Blank(bmp);
                }
                catch { }
                if (!ok)
                {
                    form.DrawToBitmap(bmp, new Rectangle(Point.Empty, bounds.Size));
                    if (over != null)
                        using (var b2 = new Bitmap(over.Width, over.Height))
                        using (var g = Graphics.FromImage(bmp))
                        {
                            over.DrawToBitmap(b2, new Rectangle(Point.Empty, over.Size));
                            g.DrawImage(b2, over.Left - bounds.Left, over.Top - bounds.Top);
                        }
                }
                bmp.Save(path, ImageFormat.Png);
            }
            Log.Write("shot " + path);
        }

        static bool Blank(Bitmap b)
        {
            var c0 = b.GetPixel(b.Width / 2, b.Height / 2);
            for (int i = 1; i < 40; i++)
            {
                var c = b.GetPixel(b.Width * i / 41, b.Height * ((i * 7) % 40 + 1) / 41);
                if (c != c0) return false;
            }
            return true;
        }

        sealed class Args
        {
            readonly List<string> a;
            public Args(string[] argv) { a = argv.ToList(); }
            public bool Has(string k) => a.Any(x => string.Equals(x, k, StringComparison.OrdinalIgnoreCase));
            public string Get(string k)
            {
                int i = a.FindIndex(x => string.Equals(x, k, StringComparison.OrdinalIgnoreCase));
                return i >= 0 && i + 1 < a.Count ? a[i + 1] : null;
            }
            public IEnumerable<string> All(string k)
            {
                for (int i = 0; i + 1 < a.Count; i++) if (string.Equals(a[i], k, StringComparison.OrdinalIgnoreCase)) yield return a[i + 1];
            }
        }
    }

    /// <summary>Made-up data for the screenshot mode (no disk or network involved).</summary>
    internal static class Demo
    {
        public static List<GameInfo> Games() => new List<GameInfo>
        {
            new GameInfo { Path = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b", Release = Payload.BaseRelease, NewClient = true, Ls = LsState.ThisBuild, LsBuild = Payload.BuildName },
            new GameInfo { Path = @"D:\OfflineDAoC\playable-v0.36b", Release = "0.36", Ls = LsState.OtherBuild, LsBuild = "0.36-se.4" },
            new GameInfo { Path = @"C:\Users\Player\Downloads\OfflineDAoC-v0.35b", Release = "0.35" },
        };

        public static InstallResult Success() => new InstallResult
        {
            Outcome = Outcome.Success,
            GamePath = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b",
            CacheBytes = Manifests.BaseGame + Manifests.GamePatch,
            CacheDir = @"C:\Games\OfflineDAoC\Offline DAoC setup files\.downloads",
        };

        public static InstallResult Failure() => new InstallResult
        {
            Outcome = Outcome.Failed,
            Message = "A GameServer.dll above is neither the original " + Payload.BaseRelease + " file nor a fork build this script installed.",
            Hint = "Setup can replace them anyway: the files there now are backed up first, and ROLLBACK.cmd in the " + Payload.RootFolder + " folder puts them back.",
            CanForce = true,
            GamePath = @"C:\Games\OfflineDAoC\playable-v" + Payload.BaseRelease + "b",
        };
    }
}
