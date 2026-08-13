using HarmonyLib;
using Steamworks;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(Raft_Network), "Update")]
    internal static class Patch_RaftUpdate
    {
        private static void Prefix()
        {
            HarmonyBootstrap.EnsureOverlay();
            AstralTransport.PumpMainThread();
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.HostGame))]
    internal static class Patch_HostGame
    {
        private static void Postfix(RequestJoinAuthSetting joinAuthSetting)
        {
            if (!AstralSettings.EnableLan || joinAuthSetting == RequestJoinAuthSetting.ALLOW_NONE)
            {
                return;
            }

            AstralTransport.StartListen(AstralTransport.Port);
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.LeaveGame))]
    internal static class Patch_LeaveGame
    {
        private static void Postfix()
        {
            AstralTransport.StopListen();
            AstralTransport.DisconnectPeers();
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "CanUserJoinFriendCheck")]
    internal static class Patch_CanUserJoinFriendCheck
    {
        private static bool Prefix(CSteamID remoteID, ref InitiateResult __result)
        {
            if (!AstralTransport.IsPeer(remoteID))
            {
                return true;
            }

            __result = InitiateResult.Success;
            return false;
        }
    }
}
