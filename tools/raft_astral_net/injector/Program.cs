using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using SharpMonoInjector;

namespace AstralRaftInject
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            string processName = "Raft";
            int? pid = null;
            bool watch = false;
            string assemblyPath = null;
            for (int i = 0; i < args.Length; i++)
            {
                string arg = args[i];
                if ((arg == "-p" || arg == "--process") && i + 1 < args.Length)
                {
                    processName = args[++i];
                }
                else if ((arg == "-a" || arg == "--dll") && i + 1 < args.Length)
                {
                    assemblyPath = Path.GetFullPath(args[++i]);
                }
                else if ((arg == "--pid") && i + 1 < args.Length)
                {
                    int parsed;
                    if (int.TryParse(args[++i], out parsed) && parsed > 0)
                    {
                        pid = parsed;
                    }
                }
                else if (arg == "--watch")
                {
                    watch = true;
                    if (i + 1 < args.Length && !args[i + 1].StartsWith("-", StringComparison.Ordinal))
                    {
                        processName = args[++i];
                    }
                }
                else if (arg == "-h" || arg == "--help")
                {
                    Console.WriteLine("AstralRaftInject [--dll AstralRaftNet.dll] [--pid N | -p Raft | --watch Raft]");
                    return 2;
                }
            }

            assemblyPath = ResolveDll(assemblyPath);
            string dllDir = assemblyPath != null ? Path.GetDirectoryName(assemblyPath) : null;
            InjectLog.Init(dllDir);

            if (string.IsNullOrEmpty(assemblyPath) || !File.Exists(assemblyPath))
            {
                InjectLog.Error("plugin not found: " + assemblyPath);
                return 1;
            }

            byte[] raw;
            try
            {
                raw = File.ReadAllBytes(assemblyPath);
                InjectLog.Info("read dll ok bytes=" + raw.Length + " path=" + assemblyPath);
            }
            catch (Exception ex)
            {
                InjectLog.Error("read dll failed: " + ex.Message);
                return 1;
            }

            Injector.Log = InjectLog.Info;
            if (watch)
            {
                return WatchLoop(processName, raw);
            }

            int targetPid;
            if (pid.HasValue)
            {
                targetPid = pid.Value;
                InjectLog.Info("use --pid " + targetPid);
            }
            else
            {
                InjectLog.Info("wait process=" + processName);
                targetPid = WaitForProcess(processName, 120000);
                InjectLog.Info("resolved process=" + processName + " pid=" + targetPid);
            }

            return InjectOnce(targetPid, raw, true) ? 0 : 3;
        }

        private static int WatchLoop(string processName, byte[] raw)
        {
            HashSet<int> seen = new HashSet<int>();
            int idleTicks = 0;
            InjectLog.Info("watch process=" + processName);
            while (true)
            {
                Process[] procs = Process.GetProcessesByName(StripExe(processName));
                HashSet<int> alive = new HashSet<int>();
                if (procs == null || procs.Length == 0)
                {
                    idleTicks++;
                    if (idleTicks == 1 || idleTicks % 15 == 0)
                    {
                        InjectLog.Info("watch: no process named " + processName);
                    }
                }
                else
                {
                    idleTicks = 0;
                    for (int i = 0; i < procs.Length; i++)
                    {
                        int id = procs[i].Id;
                        alive.Add(id);
                        if (!seen.Add(id))
                        {
                            continue;
                        }

                        InjectLog.Info("watch: try pid=" + id);
                        if (!InjectOnce(id, raw, false))
                        {
                            seen.Remove(id);
                        }
                    }
                }

                List<int> dead = new List<int>();
                foreach (int id in seen)
                {
                    if (!alive.Contains(id))
                    {
                        dead.Add(id);
                    }
                }

                for (int i = 0; i < dead.Count; i++)
                {
                    seen.Remove(dead[i]);
                }

                Thread.Sleep(2000);
            }
        }

        private static bool InjectOnce(int pid, byte[] raw, bool waitMono)
        {
            try
            {
                using (Injector injector = waitMono ? OpenWhenMonoReady(pid, 45000) : new Injector(pid))
                {
                    InjectLog.Info("inject pid=" + pid + " invoke=AstralRaftNet.Loader.Init");
                    IntPtr remote = injector.Inject(raw, "AstralRaftNet", "Loader", "Init");
                    InjectLog.Info("injected pid=" + pid + " assembly=0x" + remote.ToInt64().ToString("X"));
                    return true;
                }
            }
            catch (Exception ex)
            {
                InjectLog.Error("inject pid=" + pid + " failed: " + ex.Message);
                return false;
            }
        }

        private static Injector OpenWhenMonoReady(int pid, int timeoutMs)
        {
            Stopwatch sw = Stopwatch.StartNew();
            Exception last = null;
            while (true)
            {
                try
                {
                    InjectLog.Info("OpenProcess pid=" + pid);
                    return new Injector(pid);
                }
                catch (InjectorException ex)
                {
                    last = ex;
                    if (!IsMonoWaitError(ex))
                    {
                        throw;
                    }

                    int left = Math.Max(0, (timeoutMs - (int)sw.ElapsedMilliseconds) / 1000);
                    InjectLog.Info("waiting mono.dll (" + ex.Message + ") left=" + left + "s");
                    if (sw.ElapsedMilliseconds >= timeoutMs)
                    {
                        throw new InjectorException("mono.dll not found (is the game still loading?)", last);
                    }

                    Thread.Sleep(800);
                }
            }
        }

        private static bool IsMonoWaitError(Exception ex)
        {
            string text = ex.Message ?? string.Empty;
            return text.IndexOf("mono", StringComparison.OrdinalIgnoreCase) >= 0
                || text.IndexOf("enumerate process modules", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static int WaitForProcess(string processName, int timeoutMs)
        {
            string name = StripExe(processName);
            Stopwatch sw = Stopwatch.StartNew();
            while (true)
            {
                Process[] procs = Process.GetProcessesByName(name);
                if (procs != null && procs.Length > 0)
                {
                    return procs[0].Id;
                }

                if (timeoutMs >= 0 && sw.ElapsedMilliseconds >= timeoutMs)
                {
                    throw new InjectorException("process not found: " + processName);
                }

                InjectLog.Info("waiting process " + name);
                Thread.Sleep(1000);
            }
        }

        private static string StripExe(string name)
        {
            if (string.IsNullOrEmpty(name))
            {
                return "Raft";
            }

            return name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                ? name.Substring(0, name.Length - 4)
                : name;
        }

        private static string ResolveDll(string assemblyPath)
        {
            if (!string.IsNullOrEmpty(assemblyPath) && File.Exists(assemblyPath))
            {
                return Path.GetFullPath(assemblyPath);
            }

            string root = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates =
            {
                assemblyPath,
                Path.Combine(root, "AstralRaftNet.dll"),
                Path.Combine(root, "..", "plugin", "AstralRaftNet.dll"),
                Path.Combine(root, "..", "dist", "AstralRaftNet.dll"),
                Path.Combine(root, "..", "..", "dist", "AstralRaftNet.dll")
            };
            for (int i = 0; i < candidates.Length; i++)
            {
                if (string.IsNullOrEmpty(candidates[i]))
                {
                    continue;
                }

                try
                {
                    string full = Path.GetFullPath(candidates[i]);
                    if (File.Exists(full))
                    {
                        return full;
                    }
                }
                catch
                {
                }
            }

            return assemblyPath;
        }
    }
}
