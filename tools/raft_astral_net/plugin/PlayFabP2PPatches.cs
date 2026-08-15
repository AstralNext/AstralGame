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
        private static bool Prefix(Raft_Network __instance, Network_UserId steamID, Message message, EP2PSend sendType, NetworkChannel channel)
        {
            if (message == null || !AstralTransport.IsActive)
            {
                return true;
            }

            if (steamID == __instance.LocalSteamID)
            {
                return true;
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
            if (AstralTransport.PeerCount == 0 || message == null)
            {
                return true;
            }

            if (target == Target.All)
            {
                if (_parseLocal == null)
                {
                    _parseLocal = MethodInvoker.GetHandler(
                        AccessTools.Method(typeof(Raft_Network), "ParseLocalMessage"));
                }

                _parseLocal(__instance, new object[] { message, __instance.LocalSteamID });
            }

            AstralTransport.BroadcastMessage(message, (int)channel, 0UL, sendType);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.RPCExclude))]
    internal static class Patch_RPCExclude
    {
        private static bool Prefix(Message message, Network_UserId excludeID, EP2PSend sendType, NetworkChannel channel)
        {
            if (AstralTransport.PeerCount == 0 || message == null)
            {
                return true;
            }

            AstralTransport.BroadcastMessage(message, (int)channel, excludeID.Id, sendType);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "Platform_HostGame")]
    internal static class Patch_PlatformHostGame
    {
        private static bool Prefix(Raft_Network __instance)
        {
            if (!AstralSettings.EnableLan)
            {
                return true;
            }

            if (!LoadSceneManager.IsGameSceneLoaded)
            {
                AccessTools.Method(typeof(Raft_Network), "LoadScene")
                    .Invoke(__instance, new object[] { Raft_Network.GameSceneName });
            }

            AccessTools.Field(typeof(Raft_Network), "m_currentSteamHost")
                .SetValue(__instance, SteamUser.GetSteamID());
            AccessTools.Field(typeof(Raft_Network), "m_hostedPlayFab")
                .SetValue(__instance, false);
            AstralLog.Info("host without PlayFab");
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "ReadP2P_Channel_Connecting")]
    internal static class Patch_ReadP2PConnecting
    {
        private static bool Prefix()
        {
            return !AstralTransport.IsActive;
        }
    }
}
