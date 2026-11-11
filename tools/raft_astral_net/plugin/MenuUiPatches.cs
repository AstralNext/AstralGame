using System;
using HarmonyLib;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(NewGameBox), nameof(NewGameBox.Open), new Type[0])]
    internal static class Patch_NewGameOpen
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.UnlockNewGame(__instance);
        }
    }

    [HarmonyPatch(typeof(NewGameBox), "Update", new Type[0])]
    internal static class Patch_NewGameUpdate
    {
        private static void Postfix(NewGameBox __instance)
        {
            AstralMenuUi.UnlockNewGame(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), nameof(LoadGameBox.Open), new Type[0])]
    internal static class Patch_LoadGameOpen
    {
        private static void Postfix(LoadGameBox __instance)
        {
            AstralMenuUi.UnlockLoadGame(__instance);
        }
    }

    [HarmonyPatch(typeof(LoadGameBox), "Update", new Type[0])]
    internal static class Patch_LoadGameUpdate
    {
        private static void Postfix(LoadGameBox __instance)
        {
            AstralMenuUi.UnlockLoadGame(__instance);
        }
    }
}
