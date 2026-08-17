using System;
using HarmonyLib;
using Splatform;

namespace AstralValheimNet
{
    internal static class AstralJoin
    {
        public static bool ForceDedicatedIp;

        public static bool TryJoinDedicated(FejdStartup startup, string host, int port)
        {
            if (startup == null || string.IsNullOrEmpty(host) || port <= 0 || port > 65535)
            {
                return false;
            }

            ServerJoinDataDedicated dedicated = new ServerJoinDataDedicated(host.Trim(), (ushort)port);
            startup.SetServerToJoin(new ServerJoinData(dedicated));
            ForceDedicatedIp = true;
            startup.JoinServer();
            return true;
        }
    }

    [HarmonyPatch(typeof(FejdStartup), nameof(FejdStartup.JoinServer))]
    internal static class Patch_JoinServer
    {
        private static bool Prefix(FejdStartup __instance)
        {
            try
            {
                object raw = AccessTools.Field(typeof(FejdStartup), "m_joinServer").GetValue(__instance);
                if (!(raw is ServerJoinData))
                {
                    return true;
                }

                ServerJoinData data = (ServerJoinData)raw;
                if (data.m_type != ServerJoinDataType.Dedicated)
                {
                    return true;
                }

                ServerJoinDataDedicated dedicated = data.Dedicated;
                string host = dedicated.m_host;
                int port = dedicated.m_port == 0 ? AstralValheim.GamePort : dedicated.m_port;
                bool ours = AstralJoin.ForceDedicatedIp || AstralLanDiscovery.IsKnown(host, port);
                AstralJoin.ForceDedicatedIp = false;
                if (!ours)
                {
                    return true;
                }

                if (PlatformManager.DistributionPlatform != null &&
                    PlatformManager.DistributionPlatform.PrivilegeProvider != null &&
                    PlatformManager.DistributionPlatform.PrivilegeProvider.CheckPrivilege(Privilege.OnlineMultiplayer) != PrivilegeResult.Granted)
                {
                    return true;
                }

                AstralLog.Info("join dedicated Steam IP " + host + ":" + port);
                ZNet.SetServer(false, false, false, "", "", null);
                ZNet.SetServerHost(host, port, OnlineBackendType.Steamworks);
                ServerListGui.AddToRecentServersList(data);
                AccessTools.Method(typeof(FejdStartup), "TransitionToMainScene").Invoke(__instance, null);
                return false;
            }
            catch (Exception ex)
            {
                AstralLog.Error("JoinServer prefix: " + ex);
                return true;
            }
        }
    }
}
