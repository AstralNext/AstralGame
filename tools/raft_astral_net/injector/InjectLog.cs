using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace AstralRaftInject
{
    internal static class InjectLog
    {
        private static readonly object Sync = new object();
        private static readonly List<string> Paths = new List<string>();

        public static void Init(params string[] extraDirs)
        {
            TryAdd(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AstralRaftInject.log"));
            if (extraDirs != null)
            {
                for (int i = 0; i < extraDirs.Length; i++)
                {
                    if (!string.IsNullOrEmpty(extraDirs[i]) && Directory.Exists(extraDirs[i]))
                    {
                        TryAdd(Path.Combine(extraDirs[i], "AstralRaftInject.log"));
                    }
                }
            }

            string temp = Path.GetTempPath();
            if (!string.IsNullOrEmpty(temp))
            {
                TryAdd(Path.Combine(temp, "AstralRaftInject.log"));
            }

            Info("log -> " + string.Join(" | ", Paths.ToArray()));
        }

        public static void Info(string message)
        {
            Write("INFO", message);
        }

        public static void Error(string message)
        {
            Write("ERROR", message);
        }

        private static void TryAdd(string path)
        {
            if (string.IsNullOrEmpty(path) || Paths.Contains(path))
            {
                return;
            }

            Paths.Add(path);
        }

        private static void Write(string level, string message)
        {
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + " [" + level + "] " + message;
            lock (Sync)
            {
                Console.Out.WriteLine(line);
                Console.Out.Flush();
                Console.Error.WriteLine(line);
                Console.Error.Flush();
                for (int i = 0; i < Paths.Count; i++)
                {
                    try
                    {
                        File.AppendAllText(Paths[i], line + Environment.NewLine, Encoding.UTF8);
                    }
                    catch
                    {
                    }
                }
            }
        }
    }
}
