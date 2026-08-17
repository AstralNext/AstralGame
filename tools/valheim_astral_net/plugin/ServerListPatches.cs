using System;
using System.Collections.Generic;
using HarmonyLib;
using Splatform;

namespace AstralValheimNet
{
    [HarmonyPatch(typeof(ServerListGui), "OnEnable")]
    internal static class Patch_ServerListOnEnable
    {
        private static void Prefix(ServerListGui __instance)
        {
            AstralLanDiscovery.EnsureReceiver();
            AstralLanServerList.TryInsert(__instance, false);
        }
    }

    internal sealed class AstralLanServerList : IServerList
    {
        private const string ListDisplayName = "Astral局域网";
        private string _filter = string.Empty;
        private DateTime _lastRefreshUtc = DateTime.MinValue;
        private int _emittedVersion = -1;

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
            Refresh();
        }

        public void Tick()
        {
            int version = AstralLanDiscovery.RoomsVersion;
            if (version == _emittedVersion)
            {
                return;
            }

            _emittedVersion = version;
            RaiseUpdated();
        }

        public void OnClose()
        {
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
