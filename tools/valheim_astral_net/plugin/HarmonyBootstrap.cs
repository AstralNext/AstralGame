using HarmonyLib;
using UnityEngine;

namespace AstralValheimNet
{
    internal static class HarmonyBootstrap
    {
        private const string Id = "fan.astral.valheim.net";
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
            SteamIpListen.Close();
        }

        public static void EnsureOverlay()
        {
            if (_overlayReady)
            {
                return;
            }

            _overlayReady = true;
            GameObject go = new GameObject("AstralValheimNet");
            UnityEngine.Object.DontDestroyOnLoad(go);
            go.hideFlags = HideFlags.HideAndDontSave;
            go.AddComponent<AstralOverlay>();
            AstralLog.Info("overlay ready, press F7");
        }
    }
}
