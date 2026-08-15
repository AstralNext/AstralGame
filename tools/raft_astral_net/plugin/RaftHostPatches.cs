using System;
using System.Collections;
using System.Collections.Generic;
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
        private static ulong _cachedRaw;
        private static Network_UserId _cachedId;

        private static bool Prefix(ref Network_UserId __result)
        {
            if (!AstralTransport.IsActive)
            {
                return true;
            }

            if (_cachedRaw == 0UL)
            {
                CSteamID steam = SteamUser.GetSteamID();
                if (!steam.IsValid())
                {
                    return true;
                }

                _cachedRaw = steam.m_SteamID;
                _cachedId = new Network_UserId(_cachedRaw);
            }

            __result = _cachedId;
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
        // 不拦截 LeaveGame：主菜单/返回必须可用。进房超时靠 skip ConnectingBox + 尽快发世界解决。
        private static void Postfix(SceneName sceneName)
        {
            string dest = sceneName.ToString();
            if (dest == Raft_Network.GameSceneName
                || dest.IndexOf("Game", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return;
            }

            AstralLog.Info("LeaveGame teardown scene=" + sceneName);
            AstralTransport.StopListen();
            AstralTransport.DisconnectPeers();
            AstralTransport.ClearJoinState();
        }
    }

    /// <summary>
    /// 原版 SendWorld 的 MoveNext 会一直 yield，直到 remoteUsers 全部 initialized
    ///（通常要等 Network_Player.Start）。第一次进房时客机已 RequestWorld，但房主卡在等待，
    /// 永远不 GetWorld/发 Compound；第二次玩家已 Start 过所以很快。这里整段替换。
    /// </summary>
    [HarmonyPatch(typeof(Raft_Network), "SendWorld")]
    internal static class Patch_SendWorld
    {
        private static bool Prefix(Raft_Network __instance, Network_UserId id, ref IEnumerator __result)
        {
            if (!AstralTransport.IsActive || __instance == null)
            {
                return true;
            }

            __result = AstralSendWorld(__instance, id);
            return false;
        }

        private static IEnumerator AstralSendWorld(Raft_Network network, Network_UserId id)
        {
            int forced = ForceRemoteInitialized(network);
            AstralLog.Info("SendWorld astral to=" + id.Id + " forcedInit=" + forced);
            yield return null;
            ForceRemoteInitialized(network);

            List<Message> messages = null;
            try
            {
                messages = AccessTools.Method(typeof(Raft_Network), "GetWorld")
                    .Invoke(network, null) as List<Message>;
            }
            catch (Exception ex)
            {
                AstralLog.Error("GetWorld failed: " + ex);
                yield break;
            }

            if (messages == null)
            {
                AstralLog.Error("GetWorld returned null");
                yield break;
            }

            Message_Compound compound = new Message_Compound(messages);
            AstralLog.Info(
                "SendWorld astral sending Compound children=" + messages.Count + " to=" + id.Id);
            try
            {
                AccessTools.Method(
                        typeof(Raft_Network),
                        nameof(Raft_Network.SendP2P),
                        new Type[]
                        {
                            typeof(Network_UserId),
                            typeof(Message),
                            typeof(EP2PSend),
                            typeof(NetworkChannel)
                        })
                    .Invoke(
                        network,
                        new object[]
                        {
                            id,
                            compound,
                            (EP2PSend)2,
                            (NetworkChannel)0
                        });
                AstralLog.Info("SendWorld astral SendP2P done to=" + id.Id);
            }
            catch (Exception ex)
            {
                AstralLog.Error("SendWorld SendP2P failed: " + ex);
            }
        }

        private static int ForceRemoteInitialized(Raft_Network network)
        {
            int forced = 0;
            try
            {
                Dictionary<Network_UserId, Network_Player> remoteUsers =
                    AccessTools.Field(typeof(Raft_Network), "remoteUsers")
                        .GetValue(network) as Dictionary<Network_UserId, Network_Player>;
                if (remoteUsers == null)
                {
                    return 0;
                }

                foreach (KeyValuePair<Network_UserId, Network_Player> kv in remoteUsers)
                {
                    if (kv.Value != null && !kv.Value.initialized)
                    {
                        kv.Value.initialized = true;
                        forced++;
                    }
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("ForceRemoteInitialized: " + ex.Message);
            }

            return forced;
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

            if (AstralTransport.IsJoining && AstralTransport.PeerCount > 0)
            {
                AstralLog.Info("ignore ForceLeave during Astral join " + reason);
                return false;
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

    [HarmonyPatch(typeof(ConnectingBox), nameof(ConnectingBox.StartConnectTimeoutTimer))]
    internal static class Patch_ConnectTimeout
    {
        private static bool Prefix()
        {
            if (!AstralTransport.IsJoining && !AstralSettings.EnableLan)
            {
                return true;
            }

            AstralLog.Info("skip ConnectingBox timeout");
            return false;
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
