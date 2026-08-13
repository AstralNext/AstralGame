using HarmonyLib;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(NewGameBox), nameof(NewGameBox.Open))]
    internal static class Patch_NewGameOpen
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.EnsureNewGame(__instance);
            AstralMenuUi.SyncNewGameVisibility(__instance);
        }
    }

    [HarmonyPatch(typeof(NewGameBox), nameof(NewGameBox.OnAllowFriendsToggle))]
    internal static class Patch_NewGameAuth
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.SyncNewGameVisibility(__instance);
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
            AstralMenuUi.EnsureLoadGame(__instance);
            AstralMenuUi.SyncLoadGameVisibility(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), nameof(LoadGameBox.OnAllowFriendsToggle))]
    internal static class Patch_LoadGameAuth
    {
        private static void Postfix(LoadGameBox __instance)
        {
            AstralMenuUi.SyncLoadGameVisibility(__instance);
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
