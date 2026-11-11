using System;

namespace AstralRaftNet
{
    /// <summary>
    /// 中继帧与世界分片的纯逻辑，便于脱离 Unity 做单元验证。
    /// </summary>
    internal static class AstralWireFormat
    {
        /// <summary>
        /// 可靠帧 channel 字节的最高位：置 1 表示这是一条中继消息。
        /// </summary>
        public const byte ChannelRelayFlag = 0x80;

        public const int OriginSize = 8;

        /// <summary>
        /// 中继帧 = 8 字节原始发送者 SteamID + 原始负载。
        /// </summary>
        public static byte[] FrameRelay(byte[] payload, ulong origin)
        {
            if (payload == null)
            {
                throw new ArgumentNullException("payload");
            }

            byte[] framed = new byte[OriginSize + payload.Length];
            Buffer.BlockCopy(BitConverter.GetBytes(origin), 0, framed, 0, OriginSize);
            Buffer.BlockCopy(payload, 0, framed, OriginSize, payload.Length);
            return framed;
        }

        /// <summary>
        /// 去掉中继头；不是中继帧或长度不足时返回 false 且不改动 payload。
        /// </summary>
        public static bool TryUnframeRelay(ref byte[] payload, out ulong origin)
        {
            origin = 0UL;
            if (payload == null || payload.Length < OriginSize)
            {
                return false;
            }

            origin = BitConverter.ToUInt64(payload, 0);
            if (origin == 0UL)
            {
                return false;
            }

            int length = payload.Length - OriginSize;
            byte[] inner = new byte[length];
            Buffer.BlockCopy(payload, OriginSize, inner, 0, length);
            payload = inner;
            return true;
        }

        public static int ChunkCount(int total, int chunkSize)
        {
            if (total <= 0 || chunkSize <= 0)
            {
                return 0;
            }

            return (total + chunkSize - 1) / chunkSize;
        }

        public static int ChunkLength(int total, int chunkSize, int index)
        {
            if (total <= 0 || chunkSize <= 0 || index < 0)
            {
                return 0;
            }

            int offset = index * chunkSize;
            if (offset >= total)
            {
                return 0;
            }

            return Math.Min(chunkSize, total - offset);
        }
    }
}
