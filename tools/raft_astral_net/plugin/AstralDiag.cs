using System.Collections.Generic;
using UnityEngine;

namespace AstralRaftNet
{
    /// <summary>
    /// 诊断计数器：把高频的「静默丢弃」按 key 聚合，满 1 秒才输出一条，
    /// 避免上万条方块消息逐条刷屏。只用于定位，不参与任何同步逻辑。
    /// </summary>
    internal static class AstralDiag
    {
        private const float FlushInterval = 1f;

        private sealed class Bucket
        {
            public int Count;
            public string Context;
        }

        private static readonly Dictionary<string, Bucket> Buckets = new Dictionary<string, Bucket>();
        private static float _lastFlush;

        public static void Note(string key, string context)
        {
            Bucket bucket;
            if (!Buckets.TryGetValue(key, out bucket))
            {
                bucket = new Bucket();
                Buckets.Add(key, bucket);
            }

            bucket.Count++;
            if (!string.IsNullOrEmpty(context))
            {
                bucket.Context = context;
            }

            // 只在下一次计数时惰性检查，平时零开销。
            if (Time.realtimeSinceStartup - _lastFlush >= FlushInterval)
            {
                Flush(false);
            }
        }

        public static void Flush(bool force)
        {
            if (Buckets.Count == 0)
            {
                _lastFlush = Time.realtimeSinceStartup;
                return;
            }

            if (!force && Time.realtimeSinceStartup - _lastFlush < FlushInterval)
            {
                return;
            }

            _lastFlush = Time.realtimeSinceStartup;
            foreach (KeyValuePair<string, Bucket> kv in Buckets)
            {
                AstralLog.Info("diag " + kv.Key + " count=" + kv.Value.Count
                    + (string.IsNullOrEmpty(kv.Value.Context) ? string.Empty : " ctx=" + kv.Value.Context));
            }

            Buckets.Clear();
        }
    }
}
