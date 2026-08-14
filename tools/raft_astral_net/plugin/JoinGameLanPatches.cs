using System.Collections.Generic;
using HarmonyLib;
using Steamworks;
using UnityEngine;
using UnityEngine.UI;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(JoinGameBoxConsole), nameof(JoinGameBoxConsole.Open))]
    internal static class Patch_JoinConsoleOpen
    {
        private static void Postfix(JoinGameBoxConsole __instance)
        {
            AstralLanDiscovery.EnsureReceiver();
            AstralJoinConsole.Unlock(__instance);
            AstralJoinConsole.Retitle(__instance);
            AstralJoinConsole.Populate(__instance);
        }
    }

    [HarmonyPatch(typeof(JoinGameBoxConsole), "Update")]
    internal static class Patch_JoinConsoleUpdate
    {
        private static void Postfix(JoinGameBoxConsole __instance)
        {
            AstralJoinConsole.Unlock(__instance);
        }
    }

    [HarmonyPatch(typeof(JoinGameBoxConsole), "RefreshGames")]
    internal static class Patch_JoinConsoleRefresh
    {
        private static bool Prefix(JoinGameBoxConsole __instance)
        {
            AstralJoinConsole.Unlock(__instance);
            AstralJoinConsole.Retitle(__instance);
            AstralJoinConsole.Populate(__instance);
            return false;
        }
    }

    [HarmonyPatch(typeof(JoinGameBoxConsole), nameof(JoinGameBoxConsole.Join))]
    internal static class Patch_JoinConsoleJoin
    {
        private static bool Prefix(JoinGameBoxConsole __instance)
        {
            return !AstralJoinConsole.TryJoin(__instance);
        }
    }

    [HarmonyPatch(typeof(JoinGameBox), nameof(JoinGameBox.Open))]
    internal static class Patch_JoinOpenLan
    {
        private static void Postfix(JoinGameBox __instance)
        {
            AstralLanDiscovery.EnsureReceiver();
            AstralLanUi.Retitle(__instance);
        }
    }

    [HarmonyPatch(typeof(JoinGameBox), "RefreshGames")]
    internal static class Patch_RefreshGames
    {
        private static bool Prefix(JoinGameBox __instance)
        {
            AstralLanUi.Retitle(__instance);
            AstralLanUi.Populate(__instance);
            return false;
        }
    }

    [HarmonyPatch(typeof(JoinGameBox), nameof(JoinGameBox.JoinSelectedGame))]
    internal static class Patch_JoinSelectedGame
    {
        private static bool Prefix(JoinGameBox __instance)
        {
            AstralLanUi.TryJoinSelected(__instance);
            return false;
        }
    }

    [HarmonyPatch(typeof(JoinGame_Selection), nameof(JoinGame_Selection.Set))]
    internal static class Patch_JoinSelectionSet
    {
        private static bool Prefix(JoinGame_Selection __instance, CSteamID steamID, bool passwordProtected)
        {
            LanRoom room;
            if (!AstralLanDiscovery.TryGet(steamID, out room))
            {
                return true;
            }

            __instance.steamID = steamID;
            __instance.passwordProtected = passwordProtected;
            Text name = AccessTools.Field(typeof(JoinGame_Selection), "text_GameName").GetValue(__instance) as Text;
            if (name != null)
            {
                name.text = room.DisplayName;
            }

            Image lockImage = AccessTools.Field(typeof(JoinGame_Selection), "image_passwordLock").GetValue(__instance) as Image;
            if (lockImage != null)
            {
                lockImage.gameObject.SetActive(passwordProtected);
            }

            return false;
        }
    }

    internal static class AstralJoinConsole
    {
        public static void Unlock(JoinGameBoxConsole box)
        {
            if (box == null)
            {
                return;
            }

            AccessTools.Field(typeof(JoinGameBoxConsole), "multiplayerAllowed").SetValue(box, true);
            AccessTools.Field(typeof(JoinGameBoxConsole), "crossplayAllowed").SetValue(box, true);
            GameObject offline = Field<GameObject>(box, "onlineFeaturesNotAvailable");
            if (offline != null)
            {
                offline.SetActive(false);
            }

            Button refresh = Field<Button>(box, "refreshButton");
            GameObject refreshText = Field<GameObject>(box, "refreshText");
            if (refresh != null)
            {
                refresh.interactable = true;
            }

            if (refreshText != null)
            {
                refreshText.SetActive(true);
            }

            JoinGameConsole_Selection selected = Field<JoinGameConsole_Selection>(box, "selectedGame");
            Button join = Field<Button>(box, "joinGameButton");
            GameObject joinText = Field<GameObject>(box, "joinGameText");
            bool canJoin = selected != null && selected.session.steamID.IsValid();
            if (join != null)
            {
                join.interactable = canJoin;
            }

            if (joinText != null)
            {
                joinText.SetActive(canJoin);
            }

            Button worldCode = Field<Button>(box, "crossPlatformButton");
            GameObject worldText = Field<GameObject>(box, "worldButtonText");
            if (worldCode != null)
            {
                worldCode.gameObject.SetActive(false);
            }

            if (worldText != null)
            {
                worldText.SetActive(false);
            }
        }

        public static void Retitle(JoinGameBoxConsole box)
        {
            if (box == null)
            {
                return;
            }

            Text[] texts = box.GetComponentsInChildren<Text>(true);
            bool titled = false;
            bool listed = false;
            for (int i = 0; i < texts.Length; i++)
            {
                Text text = texts[i];
                if (text == null || text.GetComponentInParent<Button>() != null)
                {
                    continue;
                }

                DisableLocalize(text.gameObject);
                string value = text.text ?? string.Empty;
                if (!titled && (value.Contains("加入世界") || value.IndexOf("Join", System.StringComparison.OrdinalIgnoreCase) >= 0 || value.Contains("astral")))
                {
                    text.text = "加入astral房间";
                    titled = true;
                    continue;
                }

                if (!listed && (value.Contains("玩家") || value.IndexOf("Player", System.StringComparison.OrdinalIgnoreCase) >= 0 || value.Contains("好友")))
                {
                    text.text = "lan发现";
                    listed = true;
                }
            }

            RelabelEmpty(Field<GameObject>(box, "noGamesFoundsText"), "未发现Astral房间");
            RelabelEmpty(Field<GameObject>(box, "onlineFeaturesNotAvailable"), "未发现Astral房间");
        }

        public static void Populate(JoinGameBoxConsole box)
        {
            ScrollRect scroll = Field<ScrollRect>(box, "scrollRect");
            JoinGameConsole_Selection prefab = Field<JoinGameConsole_Selection>(box, "gameSelectionPrefab");
            List<JoinGameConsole_Selection> list = Field<List<JoinGameConsole_Selection>>(box, "joinGameSelections");
            GameObject none = Field<GameObject>(box, "noGamesFoundsText");
            if (scroll == null || prefab == null || list == null)
            {
                return;
            }

            for (int i = 0; i < list.Count; i++)
            {
                if (list[i] != null)
                {
                    UnityEngine.Object.Destroy(list[i].gameObject);
                }
            }

            list.Clear();
            AccessTools.Field(typeof(JoinGameBoxConsole), "selectedGame").SetValue(box, null);

            List<LanRoom> rooms = AstralLanDiscovery.Snapshot();
            for (int i = 0; i < rooms.Count; i++)
            {
                LanRoom room = rooms[i];
                JoinGameConsole_Selection item = UnityEngine.Object.Instantiate(prefab, scroll.content);
                list.Add(item);
                JoinableSession session = default(JoinableSession);
                session.onlineId = room.DisplayName;
                session.steamID = new CSteamID(room.SteamId);
                item.SetInfo(session, room.Password);
                Text mode = AccessTools.Field(typeof(JoinGameConsole_Selection), "gameMode").GetValue(item) as Text;
                if (mode != null)
                {
                    mode.text = "Astral";
                }

                Text cross = AccessTools.Field(typeof(JoinGameConsole_Selection), "crossPlay").GetValue(item) as Text;
                if (cross != null)
                {
                    cross.text = "LAN";
                }
            }

            if (none != null)
            {
                none.SetActive(list.Count == 0);
            }
        }

        public static bool TryJoin(JoinGameBoxConsole box)
        {
            JoinGameConsole_Selection selected = Field<JoinGameConsole_Selection>(box, "selectedGame");
            if (selected == null || !selected.session.steamID.IsValid())
            {
                return false;
            }

            LanRoom room;
            if (!AstralLanDiscovery.TryGet(selected.session.steamID, out room))
            {
                AstralLog.Error("LAN room expired, refresh");
                return true;
            }

            AstralLog.Info("join LAN " + room.EndPoint);
            AstralTransport.ConnectAndJoin(room.EndPoint, GameManager.Password ?? string.Empty);
            ConnectingBox connecting = Field<ConnectingBox>(box, "connectingBox");
            if (connecting != null)
            {
                connecting.gameObject.SetActive(true);
            }

            return true;
        }

        private static void RelabelEmpty(GameObject go, string label)
        {
            if (go == null)
            {
                return;
            }

            DisableLocalize(go);
            Text text = go.GetComponentInChildren<Text>(true);
            if (text != null)
            {
                text.text = label;
            }
        }

        private static void DisableLocalize(GameObject go)
        {
            MonoBehaviour[] behaviours = go.GetComponentsInChildren<MonoBehaviour>(true);
            for (int i = 0; i < behaviours.Length; i++)
            {
                if (behaviours[i] != null && behaviours[i].GetType().Name == "Localize")
                {
                    behaviours[i].enabled = false;
                }
            }
        }

        private static T Field<T>(object instance, string name) where T : class
        {
            try
            {
                return AccessTools.Field(instance.GetType(), name).GetValue(instance) as T;
            }
            catch
            {
                return null;
            }
        }
    }

    internal static class AstralLanUi
    {
        public static void Retitle(JoinGameBox box)
        {
            if (box == null)
            {
                return;
            }

            Text[] texts = box.GetComponentsInChildren<Text>(true);
            bool titled = false;
            for (int i = 0; i < texts.Length; i++)
            {
                Text text = texts[i];
                if (text == null || text.GetComponentInParent<Button>() != null)
                {
                    continue;
                }

                DisableLocalize(text.gameObject);
                string value = text.text ?? string.Empty;
                if (!titled && (value.Contains("加入世界") || value.IndexOf("Join", System.StringComparison.OrdinalIgnoreCase) >= 0 || value.Contains("astral")))
                {
                    text.text = "加入astral房间";
                    titled = true;
                    continue;
                }

                if (value.Contains("创建") || value.IndexOf("Friend", System.StringComparison.OrdinalIgnoreCase) >= 0 || value.Contains("好友"))
                {
                    text.text = "lan发现";
                }
            }

            GameObject none = AccessTools.Field(typeof(JoinGameBox), "noGamesFoundsText").GetValue(box) as GameObject;
            if (none != null)
            {
                DisableLocalize(none);
                Text noneText = none.GetComponentInChildren<Text>(true);
                if (noneText != null)
                {
                    noneText.text = "未发现Astral房间";
                }
            }
        }

        public static void Populate(JoinGameBox box)
        {
            ScrollRect scroll = AccessTools.Field(typeof(JoinGameBox), "scrollRect").GetValue(box) as ScrollRect;
            JoinGame_Selection prefab = AccessTools.Field(typeof(JoinGameBox), "gameSelectionPrefab").GetValue(box) as JoinGame_Selection;
            List<JoinGame_Selection> list = AccessTools.Field(typeof(JoinGameBox), "joinGameSelections").GetValue(box) as List<JoinGame_Selection>;
            GameObject none = AccessTools.Field(typeof(JoinGameBox), "noGamesFoundsText").GetValue(box) as GameObject;
            if (scroll == null || prefab == null || list == null)
            {
                return;
            }

            for (int i = 0; i < list.Count; i++)
            {
                if (list[i] != null)
                {
                    UnityEngine.Object.Destroy(list[i].gameObject);
                }
            }

            list.Clear();
            AccessTools.Field(typeof(JoinGameBox), "selectedGame").SetValue(box, null);

            List<LanRoom> rooms = AstralLanDiscovery.Snapshot();
            for (int i = 0; i < rooms.Count; i++)
            {
                LanRoom room = rooms[i];
                JoinGame_Selection item = UnityEngine.Object.Instantiate(prefab, scroll.content);
                list.Add(item);
                item.Set(new CSteamID(room.SteamId), room.Password);
            }

            if (none != null)
            {
                none.SetActive(list.Count == 0);
            }
        }

        public static bool TryJoinSelected(JoinGameBox box)
        {
            JoinGame_Selection selected = AccessTools.Field(typeof(JoinGameBox), "selectedGame").GetValue(box) as JoinGame_Selection;
            if (selected == null || !selected.steamID.IsValid())
            {
                return false;
            }

            LanRoom room;
            if (!AstralLanDiscovery.TryGet(selected.steamID, out room))
            {
                AstralLog.Error("LAN room expired, refresh");
                return true;
            }

            AstralLog.Info("join LAN " + room.EndPoint);
            AstralTransport.ConnectAndJoin(room.EndPoint, GameManager.Password ?? string.Empty);
            if (box.connectingBox != null)
            {
                box.connectingBox.gameObject.SetActive(true);
            }

            return true;
        }

        private static void DisableLocalize(GameObject go)
        {
            MonoBehaviour[] behaviours = go.GetComponentsInChildren<MonoBehaviour>(true);
            for (int i = 0; i < behaviours.Length; i++)
            {
                if (behaviours[i] != null && behaviours[i].GetType().Name == "Localize")
                {
                    behaviours[i].enabled = false;
                }
            }
        }
    }
}
