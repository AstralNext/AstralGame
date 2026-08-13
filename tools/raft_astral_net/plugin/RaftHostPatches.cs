using HarmonyLib;
using PlayFab.Party;
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
        private static void Prefix(ref RequestJoinAuthSetting joinAuthSetting)
        {
            if (!AstralSettings.EnableLan)
            {
                return;
            }

            if (joinAuthSetting == RequestJoinAuthSetting.ALLOW_FRIENDS)
            {
                joinAuthSetting = RequestJoinAuthSetting.ALLOW_ALL;
                AstralLog.Info("Astral LAN host ignore Steam friends");
            }
        }

        private static void Postfix(RequestJoinAuthSetting joinAuthSetting)
        {
            if (!AstralSettings.EnableLan || joinAuthSetting == RequestJoinAuthSetting.ALLOW_NONE)
            {
                return;
            }

            AstralLog.Info("host lan listen auth=" + joinAuthSetting);
            AstralTransport.BindLocalSteamId(null);
            AstralTransport.StartListen(AstralTransport.Port);
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "get_LocalSteamID")]
    internal static class Patch_LocalSteamID
    {
        private static bool Prefix(Raft_Network __instance, ref Network_UserId __result)
        {
            if (!AstralTransport.IsActive)
            {
                return true;
            }

            CSteamID steam = SteamUser.GetSteamID();
            if (!steam.IsValid())
            {
                return true;
            }

            __result = new Network_UserId(steam.m_SteamID);
            return false;
        }
    }

    [HarmonyPatch(typeof(Network_Player), nameof(Network_Player.OnPlayerCreated))]
    internal static class Patch_OnPlayerCreated
    {
        private static void Prefix(Raft_Network network, Network_UserId steamID)
        {
            AstralTransport.BindLocalSteamId(network);
            if (network != null)
            {
                Network_UserId local = new Network_UserId(SteamUser.GetSteamID().m_SteamID);
                AstralLog.Info("OnPlayerCreated id=" + steamID.Id + " local=" + local.Id + " isLocal=" + (steamID.Id == local.Id));
            }
        }

        private static void Postfix(Network_Player __instance)
        {
            if (!AstralTransport.IsActive || __instance == null)
            {
                return;
            }

            __instance.initialized = true;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.LeaveGame))]
    internal static class Patch_LeaveGame
    {
        private static void Postfix(SceneName sceneName)
        {
            if (sceneName != SceneName.Lobby && sceneName != SceneName.Exit)
            {
                return;
            }

            AstralLog.Info("LeaveGame teardown scene=" + sceneName);
            AstralTransport.StopListen();
            AstralTransport.DisconnectPeers();
            AstralTransport.ClearJoinState();
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "ForceLeaveSession")]
    internal static class Patch_ForceLeaveSession
    {
        private static bool Prefix(LeaveSessionReason reason)
        {
            if (!AstralSettings.EnableLan && AstralTransport.PeerCount == 0 && !AstralTransport.IsJoining)
            {
                return true;
            }

            if (reason == LeaveSessionReason.ConnectionLoss
                || reason == LeaveSessionReason.InternetLoss
                || reason == LeaveSessionReason.Blocked
                || reason == LeaveSessionReason.MissmatchVersion)
            {
                AstralLog.Info("ignore PlayFab ForceLeave " + reason);
                return false;
            }

            return true;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "OnError")]
    internal static class Patch_PlayFabOnError
    {
        private static bool Prefix(object sender, PlayFabMultiplayerManagerErrorArgs args)
        {
            if (!AstralSettings.EnableLan && AstralTransport.PeerCount == 0 && !AstralTransport.IsJoining)
            {
                return true;
            }

            int code = args != null ? args.Code : 0;
            AstralLog.Info("ignore PlayFab OnError code=" + code);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "CanUserJoinFriendCheck")]
    internal static class Patch_CanUserJoinFriendCheck
    {
        private static bool Prefix(CSteamID remoteID, ref InitiateResult __result)
        {
            if (!AstralSettings.EnableLan && !AstralTransport.IsPeer(remoteID))
            {
                return true;
            }

            __result = InitiateResult.Success;
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "CanUserJoinMe")]
    internal static class Patch_CanUserJoinMe
    {
        private static bool Prefix(CSteamID remoteID, ref InitiateResult __result)
        {
            if (!AstralSettings.EnableLan && !AstralTransport.IsPeer(remoteID))
            {
                return true;
            }

            __result = InitiateResult.Success;
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "ParseRemoteMessage")]
    internal static class Patch_ParseRemoteUnlocks
    {
        private static void Prefix(Message message, PlayFabPlayer from)
        {
            if (message == null || message.Type != Messages.PlayerJoined || from == null || from.EntityKey == null)
            {
                return;
            }

            Message_PlayerJoined joined = message as Message_PlayerJoined;
            if (joined == null || joined.characterSettings == null || joined.characterSettings.Unlocks == 255)
            {
                return;
            }

            ulong steamId = 0UL;
            try
            {
                steamId = new Network_UserId(from.EntityKey.Id).Id;
            }
            catch
            {
                return;
            }

            if (!AstralTransport.IsPeer(steamId) && !AstralSettings.EnableLan)
            {
                return;
            }

            AstralLog.Info("normalize Unlocks for Astral peer " + steamId);
            joined.characterSettings.Unlocks = 255;
        }
    }
}
