using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using PlayFab.Party;
using Steamworks;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(Raft_Network), "Update", new Type[0])]
    internal static class Patch_RaftUpdate
    {
        private static void Prefix()
        {
            AstralTransport.PumpMainThread();
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.HostGame), new[]
    {
        typeof(RequestJoinAuthSetting), typeof(string)
    })]
    internal static class Patch_HostGame
    {
        private static void Prefix(ref RequestJoinAuthSetting joinAuthSetting)
        {
            if (joinAuthSetting == RequestJoinAuthSetting.ALLOW_FRIENDS)
            {
                joinAuthSetting = RequestJoinAuthSetting.ALLOW_ALL;
                AstralLog.Info("Astral LAN host ignore Steam friends");
            }
        }

        private static void Postfix(RequestJoinAuthSetting joinAuthSetting)
        {
            // ALLOW_NONE 是单机/离线模式（OnPlayFabSignedIn 也用它），不是已删除的
            // EnableLan 开关：单机不应开监听广播，这里保留这一层语义判断。
            if (joinAuthSetting == RequestJoinAuthSetting.ALLOW_NONE)
            {
                return;
            }

            AstralLog.Info("host lan listen auth=" + joinAuthSetting);
            // StartListen 内部会先校验真实 SteamID，拿不到就报错不监听。
            AstralTransport.StartListen(AstralTransport.Port);
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "get_LocalSteamID", new Type[0])]
    internal static class Patch_LocalSteamID
    {
        private static bool Prefix(ref Network_UserId __result)
        {
            // 联机身份 = 真实 SteamID；只有完全拿不到 SteamID 的单机/离线场景
            // 才退回持久化的 LocalId（仅用于存档归属）。
            ulong steam = AstralTransport.SteamId;
            __result = new Network_UserId(steam != 0UL ? steam : AstralTransport.LocalId);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.OnPlayFabSignedIn), new Type[0])]
    internal static class Patch_OnPlayFabSignedIn
    {
        private static void Postfix(Raft_Network __instance)
        {
            if (__instance == null)
            {
                return;
            }

            try
            {
                ulong steam = AstralTransport.SteamId;
                if (steam == 0UL)
                {
                    AstralLog.Info("PlayFab signed in without SteamID, keep offline identity");
                    return;
                }

                // 原版这里把 localSteamID 和 hostID 写成 PlayFab TitleAccountId；
                // 而方块归属判定是 playerNetwork.steamID == network.HostID，
                // 因此两个字段都必须拉回真实 SteamID，否则木筏方块不会进世界快照。
                FieldInfo localField = AstralReflection.Field(typeof(Raft_Network), "localSteamID");
                if (localField != null)
                {
                    Network_UserId current = (Network_UserId)localField.GetValue(__instance);
                    if (current.Id != steam)
                    {
                        localField.SetValue(__instance, new Network_UserId(steam));
                        AstralLog.Info("align localSteamID id=" + steam + " was=" + current.Id + " (PlayFab sign-in)");
                    }
                }

                if (!Raft_Network.IsHost)
                {
                    return;
                }

                FieldInfo hostField = AstralReflection.Field(typeof(Raft_Network), "hostID");
                if (hostField == null)
                {
                    return;
                }

                Network_UserId host = (Network_UserId)hostField.GetValue(__instance);
                if (host.Id != steam)
                {
                    hostField.SetValue(__instance, new Network_UserId(steam));
                    AstralLog.Info("align hostID id=" + steam + " was=" + host.Id + " (PlayFab sign-in)");
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("align identity after PlayFab sign-in: " + ex.Message);
            }
        }
    }

    [HarmonyPatch(typeof(Network_Player), nameof(Network_Player.OnPlayerCreated), new[]
    {
        typeof(Raft_Network), typeof(Network_UserId), typeof(RGD_Settings_Character)
    })]
    internal static class Patch_OnPlayerCreated
    {
        private static void Prefix(Raft_Network network, Network_UserId steamID)
        {
            if (network != null)
            {
                Network_UserId local = network.LocalSteamID;
                AstralLog.Info("OnPlayerCreated id=" + steamID.Id + " local=" + local.Id + " isLocal=" + (steamID.Id == local.Id));
            }
        }

        private static void Postfix(Network_Player __instance)
        {
            if (__instance == null)
            {
                return;
            }

            __instance.initialized = true;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), nameof(Raft_Network.LeaveGame), new[]
    {
        typeof(DisconnectReason), typeof(SceneName), typeof(bool), typeof(bool)
    })]
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
    [HarmonyPatch(typeof(Raft_Network), "SendWorld", new[] { typeof(Network_UserId) })]
    internal static class Patch_SendWorld
    {
        private static bool Prefix(Raft_Network __instance, Network_UserId id, ref IEnumerator __result)
        {
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
                messages = AstralReflection.Method(typeof(Raft_Network), "GetWorld")
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

            Message_Compound compound = null;
            MethodInfo sendP2P = AstralReflection.Method(
                typeof(Raft_Network),
                nameof(Raft_Network.SendP2P),
                typeof(Network_UserId),
                typeof(Message),
                typeof(EP2PSend),
                typeof(NetworkChannel));
            int total = messages.Count;
            const int chunkSize = 200;
            int chunks = AstralWireFormat.ChunkCount(total, chunkSize);
            AstralLog.Info(
                "SendWorld astral total=" + total + " chunks=" + chunks + " to=" + id.Id);

            // 分片下发：之前一次性发一个巨型 Compound，客机单帧应用上万条会卡死。
            int sent = 0;
            for (int offset = 0; offset < total; offset += chunkSize)
            {
                int count = AstralWireFormat.ChunkLength(total, chunkSize, offset / chunkSize);
                compound = new Message_Compound(messages.GetRange(offset, count));
                try
                {
                    sendP2P.Invoke(
                        network,
                        new object[]
                        {
                            id,
                            compound,
                            (EP2PSend)2,
                            (NetworkChannel)0
                        });
                    sent += count;
                }
                catch (Exception ex)
                {
                    AstralLog.Error("SendWorld chunk failed at " + offset + ": " + ex);
                    yield break;
                }

                // 每两片让出一帧，避免房主自己在下发时整帧卡住。
                if ((offset / chunkSize + 1) % 2 == 0)
                {
                    yield return null;
                }
            }

            AstralLog.Info("SendWorld astral done messages=" + sent + "/" + total + " to=" + id.Id);
        }

        private static int ForceRemoteInitialized(Raft_Network network)
        {
            int forced = 0;
            try
            {
                Dictionary<Network_UserId, Network_Player> remoteUsers =
                    AstralReflection.Field(typeof(Raft_Network), "remoteUsers")
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

    [HarmonyPatch(typeof(Raft_Network), "ForceLeaveSession", new[]
    {
        typeof(LeaveSessionReason), typeof(int)
    })]
    internal static class Patch_ForceLeaveSession
    {
        private static bool Prefix(LeaveSessionReason reason)
        {
            // 原版会话错误/邀请不再能强制离开：退出只走 LeaveGame 自己的清理路径。
            AstralLog.Info("ignore ForceLeaveSession " + reason);
            return false;
        }
    }

    [HarmonyPatch(typeof(ConnectingBox), nameof(ConnectingBox.StartConnectTimeoutTimer),
        new[] { typeof(CSteamID) })]
    internal static class Patch_ConnectTimeout
    {
        private static bool Prefix()
        {
            AstralLog.Info("skip ConnectingBox timeout");
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "OnError", new[]
    {
        typeof(object), typeof(PlayFabMultiplayerManagerErrorArgs)
    })]
    internal static class Patch_PlayFabOnError
    {
        private static bool Prefix(object sender, PlayFabMultiplayerManagerErrorArgs args)
        {
            int code = args != null ? args.Code : 0;
            AstralLog.Info("ignore PlayFab OnError code=" + code);
            return false;
        }
    }

    [HarmonyPatch(typeof(Raft_Network), "ParseRemoteMessage", new[]
    {
        typeof(Message), typeof(PlayFabPlayer)
    })]
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

            AstralLog.Info("normalize Unlocks for Astral peer");
            joined.characterSettings.Unlocks = 255;
        }
    }
}
