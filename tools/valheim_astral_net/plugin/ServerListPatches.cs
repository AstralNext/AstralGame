using System;
using System.Collections.Generic;
using HarmonyLib;
using Splatform;

namespace AstralValheimNet
{
    [HarmonyPatch(typeof(ServerListGui), "Initialize")]
    internal static class Patch_ServerListInitialize
    {
        private static void Postfix(ServerListGui __instance)
        {
            AstralLanDiscovery.EnsureReceiver();
            AstralLanServerList.TryInsert(__instance, false);
        }
    }

    [HarmonyPatch(typeof(ServerListGui), "OnEnable")]
    internal static class Patch_ServerListOnEnable
    {
        private static void Prefix(ServerListGui __instance)
        {
            AstralLanDiscovery.EnsureReceiver();
            AstralLanServerList.TryInsert(__instance, false);
        }
    }

    // 不能靠原版社区刷新：它不会去填我们的房间。和 Raft 一样自己按 Snapshot 画。
    [HarmonyPatch(typeof(ServerListGui), "Update")]
    internal static class Patch_ServerListUpdate
    {
        private static void Postfix(ServerListGui __instance)
        {
            AstralLanServerList.PumpGui(__instance);
        }
    }

    [HarmonyPatch(typeof(ServerListGui), nameof(ServerListGui.RequestServerList))]
    internal static class Patch_RequestServerList
    {
        private static bool Prefix(ServerListGui __instance)
        {
            if (!AstralLanServerList.IsCurrent(__instance))
            {
                return true;
            }

            AstralLanDiscovery.EnsureReceiver();
            AstralLanServerList current = AstralLanServerList.Current(__instance);
            if (current != null)
            {
                current.Refresh();
            }

            AstralLanServerList.RedrawNow(__instance);
            return false;
        }
    }

    internal sealed class AstralLanServerList : IServerList
    {
        private const string ListDisplayName = "astral局域网";
        private string _filter = string.Empty;
        private DateTime _lastRefreshUtc = DateTime.MinValue;
        private DateTime _lastPaintUtc = DateTime.MinValue;
        private int _paintedVersion = -1;

        public event ServerListUpdatedHandler ServerListUpdated;

        public string DisplayName
        {
            get { return ListDisplayName; }
        }

        public DateTime LastRefreshTimeUtc
        {
            get { return _lastRefreshUtc; }
        }

        public bool CanRefresh
        {
            get { return true; }
        }

        public uint TotalServers
        {
            get { return (uint)AstralLanDiscovery.Snapshot().Count; }
        }

        public void Refresh()
        {
            _lastRefreshUtc = DateTime.UtcNow;
            AstralLanDiscovery.EnsureReceiver();
            RaiseUpdated();
        }

        public void SetFilter(string filter, bool isTyping = false)
        {
            _filter = filter ?? string.Empty;
            RaiseUpdated();
        }

        public void GetFilteredList(List<ServerListEntryData> resultOutput)
        {
            resultOutput.Clear();
            List<LanRoom> rooms = AstralLanDiscovery.Snapshot();
            string filter = (_filter ?? string.Empty).ToLowerInvariant();
            for (int i = 0; i < rooms.Count; i++)
            {
                LanRoom room = rooms[i];
                if (!string.IsNullOrEmpty(filter) &&
                    room.DisplayName.ToLowerInvariant().IndexOf(filter, StringComparison.Ordinal) < 0)
                {
                    continue;
                }

                resultOutput.Add(ToEntry(room));
            }
        }

        public void OnOpen()
        {
            AstralLanDiscovery.EnsureReceiver();
            _paintedVersion = -1;
            _lastPaintUtc = DateTime.MinValue;
            Refresh();
        }

        public void Tick()
        {
            AstralLanDiscovery.EnsureReceiver();
        }

        public void OnClose()
        {
        }

        public static bool IsCurrent(ServerListGui gui)
        {
            return Current(gui) != null;
        }

        public static AstralLanServerList Current(ServerListGui gui)
        {
            if (gui == null)
            {
                return null;
            }

            try
            {
                object rawLists = AccessTools.Field(typeof(ServerListGui), "m_serverLists").GetValue(gui);
                object rawIndex = AccessTools.Field(typeof(ServerListGui), "m_currentServerList").GetValue(gui);
                List<IServerList> lists = rawLists as List<IServerList>;
                if (lists == null || !(rawIndex is int))
                {
                    return null;
                }

                int index = (int)rawIndex;
                if (index < 0 || index >= lists.Count)
                {
                    return null;
                }

                return lists[index] as AstralLanServerList;
            }
            catch
            {
                return null;
            }
        }

        public static void PumpGui(ServerListGui gui)
        {
            AstralLanServerList list = Current(gui);
            if (list == null)
            {
                return;
            }

            AstralLanDiscovery.EnsureReceiver();
            int version = AstralLanDiscovery.RoomsVersion;
            bool stale = (DateTime.UtcNow - list._lastPaintUtc).TotalSeconds >= 0.5;
            if (version == list._paintedVersion && !stale)
            {
                return;
            }

            list._paintedVersion = version;
            list._lastPaintUtc = DateTime.UtcNow;
            RedrawNow(gui);
        }

        public static void RedrawNow(ServerListGui gui)
        {
            if (gui == null)
            {
                return;
            }

            try
            {
                AccessTools.Field(typeof(ServerListGui), "m_filteredListOutdated").SetValue(gui, true);
                AccessTools.Method(typeof(ServerListGui), "UpdateServerListGuiInternal").Invoke(
                    gui,
                    new object[] { false });
                AccessTools.Method(typeof(ServerListGui), "UpdateServerCount").Invoke(gui, null);
            }
            catch (Exception ex)
            {
                AstralLog.Error("RedrawNow: " + ex.Message);
            }
        }

        public static void TryInsert(ServerListGui gui, bool recreateIfAlreadyEnabled)
        {
            if (gui == null)
            {
                return;
            }

            try
            {
                object raw = AccessTools.Field(typeof(ServerListGui), "m_serverLists").GetValue(gui);
                List<IServerList> lists = raw as List<IServerList>;
                if (lists == null)
                {
                    return;
                }

                for (int i = 0; i < lists.Count; i++)
                {
                    if (lists[i] is AstralLanServerList)
                    {
                        return;
                    }
                }

                AstralLanServerList list = new AstralLanServerList();
                lists.Insert(0, list);
                AstralLog.Info("server list tab inserted");

                if (!recreateIfAlreadyEnabled)
                {
                    return;
                }

                MethodInfoOnCurrent(gui, list);
                AccessTools.Method(typeof(ServerListGui), "RecreateTabs").Invoke(gui, null);
            }
            catch (Exception ex)
            {
                AstralLog.Error("TryInsert: " + ex);
            }
        }

        public static void TryAttachExisting()
        {
            try
            {
                ServerListGui gui = UnityEngine.Object.FindFirstObjectByType<ServerListGui>();
                if (gui == null || !gui.isActiveAndEnabled)
                {
                    return;
                }

                TryInsert(gui, true);
            }
            catch (Exception ex)
            {
                AstralLog.Error("TryAttachExisting: " + ex.Message);
            }
        }

        private static void MethodInfoOnCurrent(ServerListGui gui, AstralLanServerList list)
        {
            try
            {
                System.Reflection.MethodInfo method = AccessTools.Method(typeof(ServerListGui), "OnCurrentServerListUpdated");
                if (method != null)
                {
                    list.ServerListUpdated += (ServerListUpdatedHandler)Delegate.CreateDelegate(
                        typeof(ServerListUpdatedHandler),
                        gui,
                        method);
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("subscribe list: " + ex.Message);
            }
        }

        private void RaiseUpdated()
        {
            ServerListUpdatedHandler handler = ServerListUpdated;
            if (handler != null)
            {
                handler();
            }
        }

        private static ServerListEntryData ToEntry(LanRoom room)
        {
            ServerJoinDataDedicated dedicated = new ServerJoinDataDedicated(room.Ip, (ushort)room.GamePort);
            ServerJoinData join = new ServerJoinData(dedicated);
            Platform restriction = default(Platform);
            try
            {
                if (PlatformManager.DistributionPlatform != null)
                {
                    restriction = PlatformManager.DistributionPlatform.Platform;
                }
            }
            catch
            {
            }

            ServerMatchmakingData matchmaking = new ServerMatchmakingData(
                DateTime.UtcNow,
                room.DisplayName,
                0U,
                10U,
                default(PlatformUserID),
                new GameVersion(0, 221, 12),
                AstralValheim.NetworkVersion,
                string.Empty,
                room.Password,
                restriction,
                new string[0]);
            return new ServerListEntryData(new ServerData(join, matchmaking), room.DisplayName);
        }
    }
}
