// 共享模板：由两个插件项目通过 Link 方式引用
// 在 Raft 项目定义 ASTRAL_RAFT，Valheim 项目定义 ASTRAL_VALHEIM
#if ASTRAL_RAFT
namespace AstralRaftNet
#elif ASTRAL_VALHEIM
namespace AstralValheimNet
#endif
{
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

        public static void Apply()
        {
            if (_harmony != null)
            {
                return;
            }

            _harmony = new Harmony(Id);
            _harmony.PatchAll(typeof(HarmonyBootstrap).Assembly);
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
