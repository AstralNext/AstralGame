using HarmonyLib;
using Steamworks;

namespace AstralRaftNet
{
    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.SendP2PPacket))]
    internal static class Patch_SendP2PPacket
    {
        private static bool Prefix(CSteamID steamIDRemote, byte[] pubData, uint cubData, EP2PSend eP2PSendType, int nChannel, ref bool __result)
        {
            if (!AstralTransport.TrySend(steamIDRemote, pubData, cubData, nChannel, eP2PSendType))
            {
                return true;
            }

            __result = true;
            return false;
        }
    }

    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.IsP2PPacketAvailable))]
    internal static class Patch_IsP2PPacketAvailable
    {
        private static bool Prefix(ref uint pcubMsgSize, int nChannel, ref bool __result)
        {
            uint size;
            if (!AstralTransport.TryPeek(nChannel, out size))
            {
                return true;
            }

            pcubMsgSize = size;
            __result = true;
            return false;
        }
    }

    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.ReadP2PPacket))]
    internal static class Patch_ReadP2PPacket
    {
        private static bool Prefix(byte[] pubDest, uint cubDest, ref uint pcubMsgSize, ref CSteamID psteamIDRemote, int nChannel, ref bool __result)
        {
            uint size;
            CSteamID steamId;
            if (!AstralTransport.TryRead(nChannel, pubDest, cubDest, out size, out steamId))
            {
                return true;
            }

            pcubMsgSize = size;
            psteamIDRemote = steamId;
            __result = true;
            return false;
        }
    }

    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.AcceptP2PSessionWithUser))]
    internal static class Patch_AcceptP2PSessionWithUser
    {
        private static bool Prefix(CSteamID steamIDRemote, ref bool __result)
        {
            if (!AstralTransport.IsPeer(steamIDRemote))
            {
                return true;
            }

            __result = true;
            return false;
        }
    }

    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.CloseP2PSessionWithUser))]
    internal static class Patch_CloseP2PSessionWithUser
    {
        private static bool Prefix(CSteamID steamIDRemote, ref bool __result)
        {
            if (!AstralTransport.IsPeer(steamIDRemote))
            {
                return true;
            }

            __result = true;
            return false;
        }
    }

    [HarmonyPatch(typeof(SteamNetworking), nameof(SteamNetworking.GetP2PSessionState))]
    internal static class Patch_GetP2PSessionState
    {
        private static bool Prefix(CSteamID steamIDRemote, ref P2PSessionState_t pConnectionState, ref bool __result)
        {
            if (!AstralTransport.IsPeer(steamIDRemote))
            {
                return true;
            }

            pConnectionState.m_bConnectionActive = 1;
            pConnectionState.m_bConnecting = 0;
            pConnectionState.m_eP2PSessionError = 0;
            pConnectionState.m_bUsingRelay = 0;
            __result = true;
            return false;
        }
    }
}
