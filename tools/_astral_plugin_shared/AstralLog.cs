// 共享模板：由两个插件项目通过 Link 方式引用
// 在 Raft 项目定义 ASTRAL_RAFT，Valheim 项目定义 ASTRAL_VALHEIM
#if ASTRAL_RAFT
namespace AstralRaftNet
#elif ASTRAL_VALHEIM
namespace AstralValheimNet
#endif
{
    using System;
    using System.Collections.Generic;
    using System.Text;

    internal static class AstralLog
    {
        private const int MaxLines = 300;
        private static readonly List<string> Lines = new List<string>();
        private static int _version;

        public static int Version
        {
            get { return _version; }
        }

        public static int Count
        {
            get
            {
                lock (Lines)
                {
                    return Lines.Count;
                }
            }
        }

        public static string[] Snapshot()
        {
            lock (Lines)
            {
                return Lines.ToArray();
            }
        }

        public static string Dump()
        {
            lock (Lines)
            {
                StringBuilder sb = new StringBuilder(Lines.Count * 64);
                for (int i = 0; i < Lines.Count; i++)
                {
                    if (i > 0)
                    {
                        sb.Append('\n');
                    }

                    sb.Append(Lines[i]);
                }

                return sb.ToString();
            }
        }

        public static void Clear()
        {
            lock (Lines)
            {
                Lines.Clear();
                _version++;
            }
        }

        public static void Info(string message)
        {
            Write("INF", message);
        }

        public static void Error(string message)
        {
            Write("ERR", message);
        }

        private static void Write(string level, string message)
        {
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + " " + level + " " + message;
            lock (Lines)
            {
                Lines.Add(line);
                while (Lines.Count > MaxLines)
                {
                    Lines.RemoveAt(0);
                }

                _version++;
            }
        }
    }
}
