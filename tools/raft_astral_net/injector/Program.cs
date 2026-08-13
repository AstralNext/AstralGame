using System;
using System.IO;
using SharpMonoInjector;

namespace AstralRaftInject
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            string processName = "Raft";
            string assemblyPath = Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "plugin", "AstralRaftNet.dll"));
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "-p" && i + 1 < args.Length)
                {
                    processName = args[++i];
                }
                else if (args[i] == "-a" && i + 1 < args.Length)
                {
                    assemblyPath = Path.GetFullPath(args[++i]);
                }
            }

            if (!File.Exists(assemblyPath))
            {
                Console.Error.WriteLine("plugin not found: " + assemblyPath);
                return 1;
            }

            Console.WriteLine("process=" + processName);
            Console.WriteLine("assembly=" + assemblyPath);
            try
            {
                using (Injector injector = new Injector(processName))
                {
                    byte[] raw = File.ReadAllBytes(assemblyPath);
                    IntPtr remote = injector.Inject(raw, "AstralRaftNet", "Loader", "Init");
                    Console.WriteLine("injected: 0x" + remote.ToInt64().ToString("X"));
                    Console.WriteLine("in game press F7");
                    return 0;
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex);
                return 2;
            }
        }
    }
}
