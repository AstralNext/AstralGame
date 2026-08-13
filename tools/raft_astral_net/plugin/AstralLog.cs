using System;
using System.Collections.Generic;
using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralLog
    {
        private const int MaxLines = 40;
        private static readonly List<string> Lines = new List<string>();

        public static IReadOnlyList<string> Snapshot
        {
            get { return Lines; }
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
            string line = DateTime.Now.ToString("HH:mm:ss") + " " + level + " " + message;
            lock (Lines)
            {
                Lines.Add(line);
                while (Lines.Count > MaxLines)
                {
                    Lines.RemoveAt(0);
                }
            }
        }
    }
}
