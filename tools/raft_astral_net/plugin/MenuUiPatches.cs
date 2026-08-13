using HarmonyLib;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(NewGameBox), nameof(NewGameBox.Open))]
    internal static class Patch_NewGameOpen
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.UnlockNewGameIfLan(__instance);
        }
    }

    [HarmonyPatch(typeof(NewGameBox), "Update")]
    internal static class Patch_NewGameUpdate
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.UnlockNewGameIfLan(__instance);
        }
    }

    [HarmonyPatch(typeof(NewGameBox), nameof(NewGameBox.Button_CreateNewGame))]
    internal static class Patch_CreateNewGame
    {
        private static void Prefix(NewGameBox __instance)
        {
            AstralSettings.EnableLan = AstralMenuUi.ReadNewGameLan(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), nameof(LoadGameBox.Open))]
    internal static class Patch_LoadGameOpen
    {
        private static void Postfix(LoadGameBox __instance)
        {
            AstralMenuUi.UnlockLoadGameIfLan(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), "Update")]
    internal static class Patch_LoadGameUpdate
    {
        private static void Postfix(LoadGameBox __instance)
        {
            AstralMenuUi.UnlockLoadGameIfLan(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), nameof(LoadGameBox.Button_LoadGame))]
    internal static class Patch_LoadGame
    {
        private static void Prefix(LoadGameBox __instance)
        {
            AstralSettings.EnableLan = AstralMenuUi.ReadLoadGameLan(__instance);
        }
    }
}
