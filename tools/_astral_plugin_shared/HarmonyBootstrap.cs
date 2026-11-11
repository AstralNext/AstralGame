// 共享模板：由两个插件项目通过 Link 方式引用
// 在 Raft 项目定义 ASTRAL_RAFT，Valheim 项目定义 ASTRAL_VALHEIM
#if ASTRAL_RAFT
namespace AstralRaftNet
#elif ASTRAL_VALHEIM
namespace AstralValheimNet
#endif
{
    using System;
    using System.Collections.Generic;
    using System.Reflection;
    using HarmonyLib;
    using UnityEngine;

    internal static class HarmonyBootstrap
    {
#if ASTRAL_RAFT
        private const string Id = "fan.astral.raft.net";
        private const string GameObjectName = "AstralRaftNet";
#elif ASTRAL_VALHEIM
        private const string Id = "fan.astral.valheim.net";
        private const string GameObjectName = "AstralValheimNet";
#endif
        private static Harmony _harmony;
        private static bool _overlayReady;

#if ASTRAL_RAFT
        private static readonly string[] RequiredGameTypes =
        {
            "JoinGameBoxConsole",
            "Network_UserId",
            "Message_Compound",
            "ConnectingBox"
        };

        /// <summary>
        /// 校验补丁依赖的游戏成员是否齐备。返回 null 表示全部命中，
        /// 否则返回可直接展示给玩家的缺失清单。
        /// </summary>
        private static string FindMissingTargets()
        {
            List<string> missing = new List<string>();
            Assembly game = typeof(Raft_Network).Assembly;
            for (int i = 0; i < RequiredGameTypes.Length; i++)
            {
                if (game.GetType(RequiredGameTypes[i], false) == null)
                {
                    missing.Add(RequiredGameTypes[i]);
                }
            }

            // 所有反射访问都在 AstralReflection 一张表里，统一校验一次。
            AstralReflection.Initialize();
            if (!string.IsNullOrEmpty(AstralReflection.Missing))
            {
                missing.Add(AstralReflection.Missing);
            }

            return missing.Count == 0 ? null : string.Join("、", missing.ToArray());
        }
#endif

        public static void Apply()
        {
            if (_harmony != null)
            {
                return;
            }

            _harmony = new Harmony(Id);

#if ASTRAL_RAFT
            string missing = FindMissingTargets();
            if (missing != null)
            {
                string notice = "Astral 联机增强未生效：当前 Raft 版本不受支持（缺少 " + missing
                    + "）。游戏仍可正常单机或官方联机，请更新游戏或换用匹配的补丁版本。";
                AstralLog.Error(notice);
                EnsureOverlay();
                AstralOverlay.ShowFatalNotice(notice);
                return;
            }
#endif

            try
            {
                _harmony.PatchAll(typeof(HarmonyBootstrap).Assembly);
            }
            catch (Exception ex)
            {
                AstralLog.Error("PatchAll failed: " + ex);
#if ASTRAL_RAFT
                EnsureOverlay();
                AstralOverlay.ShowFatalNotice(
                    "Astral 联机增强加载失败，补丁未生效。游戏仍可正常单机或官方联机，详情见日志 astral_raft_net.log。");
#endif
                return;
            }

            AstralLanDiscovery.EnsureReceiver();
            EnsureOverlay();
#if ASTRAL_VALHEIM
            string pluginFile = typeof(HarmonyBootstrap).Assembly.Location;
            if (string.IsNullOrEmpty(pluginFile))
            {
                pluginFile = "(memory)";
            }

            AstralLog.Info("plugin file " + pluginFile);
#endif
            AstralLog.Info("Harmony patches applied");
        }

        public static void Remove()
        {
            if (_harmony != null)
            {
                _harmony.UnpatchAll(Id);
                _harmony = null;
            }

            AstralOverlay.Destroy();
            AstralLanDiscovery.StopAll();
#if ASTRAL_RAFT
            AstralTransport.StopAll();
#elif ASTRAL_VALHEIM
            SteamIpListen.Close();
#endif
        }

        public static void EnsureOverlay()
        {
            if (_overlayReady)
            {
                return;
            }

            _overlayReady = true;
            GameObject go = new GameObject(GameObjectName);
            UnityEngine.Object.DontDestroyOnLoad(go);
            go.hideFlags = HideFlags.HideAndDontSave;
            go.AddComponent<AstralOverlay>();
            AstralLog.Info("overlay ready, press F7");
        }
    }
}
