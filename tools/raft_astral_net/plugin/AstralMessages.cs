using HarmonyLib;
using PlayFab.ClientModels;
using PlayFab.Party;
using Unity.Collections;
using Unity.Netcode;

namespace AstralRaftNet
{
    internal static class AstralMessages
    {
        public static byte[] Serialize(Message message)
        {
            using (FastBufferWriter writer = new FastBufferWriter(256, Allocator.Temp, 64 * 1024 * 1024))
            {
                message.SerializeFast(writer);
                return writer.ToArray();
            }
        }

        public static Message Deserialize(byte[] data)
        {
            if (data == null || data.Length == 0)
            {
                return null;
            }

            FastBufferReader reader = new FastBufferReader(data, Allocator.Temp, data.Length, 0);
            try
            {
                if (!reader.TryBeginRead(data.Length))
                {
                    return null;
                }

                return FastMessageDeserializer.DeserializeMessage<Message>(reader);
            }
            finally
            {
                reader.Dispose();
            }
        }

        public static PlayFabPlayer FakePlayer(ulong steamId)
        {
            PlayFabPlayer player = new PlayFabPlayer();
            EntityKey key = new EntityKey
            {
                Id = steamId.ToString("X"),
                Type = "title_player_account"
            };
            AccessTools.Method(typeof(PlayFabPlayer), "_SetEntityKey").Invoke(player, new object[] { key });
            return player;
        }
    }
}
