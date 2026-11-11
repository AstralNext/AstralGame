using System;
using HarmonyLib;
using Steamworks;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.SendP2P), new[]
    {
        typeof(Network_UserId), typeof(Message), typeof(EP2PSend), typeof(NetworkChannel)
    })]
    internal static class Patch_SendP2P
    {
        private static FastInvokeHandler _parseLocal;

        private static bool Prefix(Raft_Network __instance, Network_UserId steamID, Message message, EP2PSend sendType, NetworkChannel channel)
        {
            if (message == null)
            {
                return false;
            }

            if (steamID == __instance.LocalSteamID)
            {
                // 本地回环：单机/房主给自己发消息，直接本地应用，不属于联机通道。
                if (_parseLocal == null)
                {
                    _parseLocal = MethodInvoker.GetHandler(
                        AstralReflection.Method(typeof(Raft_Network), "ParseLocalMessage",
                            typeof(Message), typeof(Network_UserId)));
                }

                _parseLocal(__instance, new object[] { message, steamID });
                return false;
            }

            if (!AstralTransport.TrySendMessageOrHost(steamID.Id, message, (int)channel, sendType))
            {
                AstralLog.Error("send drop not peer type=" + message.Type + " to=" + steamID.Id + " peers=" + AstralTransport.PeerCount);
            }

            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.RPC), new[]
    {
        typeof(Message), typeof(Target), typeof(EP2PSend), typeof(NetworkChannel)
    })]
    internal static class Patch_RPC
    {
        private static FastInvokeHandler _parseLocal;

        private static bool Prefix(Raft_Network __instance, Message message, Target target, EP2PSend sendType, NetworkChannel channel)
        {
            if (message == null)
            {
                return false;
            }

            if (target == Target.All)
            {
                if (_parseLocal == null)
                {
                    _parseLocal = MethodInvoker.GetHandler(
                        AstralReflection.Method(typeof(Raft_Network), "ParseLocalMessage",
                            typeof(Message), typeof(Network_UserId)));
                }

                _parseLocal(__instance, new object[] { message, __instance.LocalSteamID });
            }

            AstralTransport.BroadcastMessage(message, (int)channel, 0UL, sendType);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.RPCExclude), new[]
    {
        typeof(Message), typeof(Target), typeof(Network_UserId), typeof(EP2PSend), typeof(NetworkChannel)
    })]
    internal static class Patch_RPCExclude
    {
        private static bool Prefix(Message message, Network_UserId excludeID, EP2PSend sendType, NetworkChannel channel)
        {
            if (message == null)
            {
                return false;
            }

            AstralTransport.BroadcastMessage(message, (int)channel, excludeID.Id, sendType);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "Platform_HostGame", new Type[0])]
    internal static class Patch_PlatformHostGame
    {
        private static bool Prefix(Raft_Network __instance)
        {
            // 原版 PlayFab 官方房/跨平台房在这里被彻底切断：不再调用 CreateAndJoinNetwork。
            if (!LoadSceneManager.IsGameSceneLoaded)
            {
                AstralReflection.Method(typeof(Raft_Network), "LoadScene", typeof(string))
                    .Invoke(__instance, new object[] { Raft_Network.GameSceneName });
            }

            AstralReflection.Field(typeof(Raft_Network), "m_currentSteamHost")
                .SetValue(__instance, new CSteamID(AstralTransport.SteamId));
            AstralReflection.Field(typeof(Raft_Network), "m_hostedPlayFab")
                .SetValue(__instance, false);
            AstralLog.Info("host without PlayFab");
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "ReadP2P_Channel_Connecting", new Type[0])]
    internal static class Patch_ReadP2PConnecting
    {
        private static bool Prefix()
        {
            // 原版 Steam 好友加入握手整条废弃：永不处理，避免它重新创建 PlayFab 房。
            return false;
        }
    }
}
