using System;
using HarmonyLib;
using Steamworks;
using UnityEngine;

namespace AstralValheimNet
{
    internal static class SteamIpListen
    {
        private static HSteamListenSocket _ipListen = HSteamListenSocket.Invalid;
        private static readonly object Sync = new object();

        public static bool IsListening
        {
            get
            {
                lock (Sync)
                {
                    return _ipListen != HSteamListenSocket.Invalid;
                }
            }
        }

        public static void Start()
        {
            lock (Sync)
            {
                if (_ipListen != HSteamListenSocket.Invalid)
                {
                    return;
                }

                try
                {
                    SteamNetworkingIPAddr addr = default(SteamNetworkingIPAddr);
                    addr.Clear();
                    addr.SetIPv4(0, (ushort)AstralValheim.GamePort);
                    _ipListen = SteamNetworkingSockets.CreateListenSocketIP(ref addr, 0, null);
                    if (_ipListen == HSteamListenSocket.Invalid)
                    {
                        AstralLog.Error("CreateListenSocketIP failed on " + AstralValheim.GamePort);
                        return;
                    }

                    AstralLog.Info("Steam IP listen UDP " + AstralValheim.GamePort);
                }
                catch (Exception ex)
                {
                    _ipListen = HSteamListenSocket.Invalid;
                    AstralLog.Error("CreateListenSocketIP: " + ex.Message);
                }
            }
        }

        public static void Close()
        {
            lock (Sync)
            {
                if (_ipListen == HSteamListenSocket.Invalid)
                {
                    return;
                }

                try
                {
                    SteamNetworkingSockets.CloseListenSocket(_ipListen);
                    AstralLog.Info("closed Steam IP listen");
                }
                catch (Exception ex)
                {
                    AstralLog.Error("CloseListenSocket: " + ex.Message);
                }

                _ipListen = HSteamListenSocket.Invalid;
            }
        }
    }

    [HarmonyPatch(typeof(ZSteamSocket), nameof(ZSteamSocket.StartHost))]
    internal static class Patch_StartHost
    {
        private static void Postfix()
        {
            SteamIpListen.Start();
        }
    }

    [HarmonyPatch(typeof(ZSteamSocket), nameof(ZSteamSocket.Close))]
    internal static class Patch_SteamClose
    {
        private static void Prefix(ZSteamSocket __instance)
        {
            try
            {
                object host = AccessTools.Field(typeof(ZSteamSocket), "m_hostSocket").GetValue(null);
                if (host == (object)__instance)
                {
                    SteamIpListen.Close();
                    AstralLanDiscovery.StopBroadcast();
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("host close: " + ex.Message);
            }
        }
    }

    [HarmonyPatch(typeof(ZNet), nameof(ZNet.OpenServer))]
    internal static class Patch_OpenServer
    {
        private static void Postfix()
        {
            if (ZNet.m_onlineBackend != OnlineBackendType.Steamworks)
            {
                AstralLog.Info("skip LAN broadcast, backend=" + ZNet.m_onlineBackend);
                return;
            }

            bool password = false;
            string name = "Valheim";
            try
            {
                object rawPassword = AccessTools.Field(typeof(ZNet), "m_serverPassword").GetValue(null);
                password = rawPassword is string && ((string)rawPassword).Length > 0;
                object rawName = AccessTools.Field(typeof(ZNet), "m_ServerName").GetValue(null);
                if (rawName is string && !string.IsNullOrEmpty((string)rawName))
                {
                    name = (string)rawName;
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("OpenServer fields: " + ex.Message);
            }

            AstralLanDiscovery.StartBroadcast(AstralValheim.GamePort, password, name);
        }
    }

    [HarmonyPatch(typeof(ZNet), "StopAll")]
    internal static class Patch_StopAll
    {
        private static void Prefix()
        {
            AstralLanDiscovery.StopBroadcast();
            SteamIpListen.Close();
        }
    }

    [HarmonyPatch(typeof(FejdStartup), nameof(FejdStartup.OnWorldStart))]
    internal static class Patch_OnWorldStart
    {
        private static void Prefix(FejdStartup __instance)
        {
            if (__instance == null || __instance.m_openServerToggle == null)
            {
                return;
            }

            if (!__instance.m_openServerToggle.isOn)
            {
                return;
            }

            if (__instance.m_crossplayServerToggle != null && __instance.m_crossplayServerToggle.isOn)
            {
                __instance.m_crossplayServerToggle.isOn = false;
                AstralLog.Info("forced crossplay off for Steam IP host");
            }
        }
    }

    [HarmonyPatch(typeof(FejdStartup), "Update")]
    internal static class Patch_FejdUpdate
    {
        private static void Postfix(FejdStartup __instance)
        {
            if (__instance == null || __instance.m_startGamePanel == null || !__instance.m_startGamePanel.activeInHierarchy)
            {
                return;
            }

            if (__instance.m_openServerToggle == null || !__instance.m_openServerToggle.isOn)
            {
                return;
            }

            if (__instance.m_crossplayServerToggle != null && __instance.m_crossplayServerToggle.isOn)
            {
                __instance.m_crossplayServerToggle.isOn = false;
            }
        }
    }
}
