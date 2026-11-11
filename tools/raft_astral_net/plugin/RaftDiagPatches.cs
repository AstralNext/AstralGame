using HarmonyLib;
using UnityEngine;

namespace AstralRaftNet
{
    /// <summary>
    /// 客机应用世界快照时的三条静默丢弃通道。原版全部无日志、无计数，
    /// 这里只增加观测：Prefix 记录后仍然返回 true，原方法照常执行，
    /// 不改变任何分支与数据流。
    /// </summary>
    [HarmonyPatch(typeof(Raft_Network), "AddPlayer", new[] { typeof(Message_Player_Create) })]
    internal static class Patch_DiagAddPlayer
    {
        private static void Prefix(Raft_Network __instance, Message_Player_Create msg)
        {
            if (__instance == null || msg == null)
            {
                return;
            }

            try
            {
                // 原版 AddPlayer(msg) 在 bedRespawnPoint == null 时直接 return，
                // 客机表现为「房主玩家从未创建」，随后房主 BlockCreator 的所有消息全部静默失效。
                GameObject bed = AstralReflection.Field(typeof(Raft_Network), "bedRespawnPoint")
                    .GetValue(__instance) as GameObject;
                if (bed == null)
                {
                    AstralDiag.Note(
                        "drop CreatePlayer (bedRespawnPoint=null)",
                        "user=" + msg.UserId.Id + " local=" + __instance.LocalSteamID.Id);
                }
            }
            catch (System.Exception ex)
            {
                AstralLog.Error("diag CreatePlayer: " + ex.Message);
            }
        }
    }

    /// <summary>
    /// DeserializeSingleMessage 在 NetworkedBehaviours 里找不到 BehaviourIndex 时完全静默。
    /// 这里统计「因为 index 缺失被丢弃」的消息，按类型聚合。
    /// </summary>
    [HarmonyPatch(typeof(NetworkUpdateManager), "DeserializeSingleMessage", new[]
    {
        typeof(Message), typeof(Network_UserId)
    })]
    internal static class Patch_DiagDeserializeMessage
    {
        private static void Prefix(Message msg)
        {
            Message_NetworkBehaviour behaviour = msg as Message_NetworkBehaviour;
            if (behaviour == null)
            {
                return;
            }

            try
            {
                if (NetworkUpdateManager.NetworkedBehaviours.ContainsKey(behaviour.BehaviourIndex))
                {
                    return;
                }

                AstralDiag.Note(
                    "drop missing behaviour " + behaviour.Type,
                    "idx=" + behaviour.BehaviourIndex
                    + " registered=" + NetworkUpdateManager.NetworkedBehaviours.Count);
            }
            catch (System.Exception ex)
            {
                AstralLog.Error("diag deserialize: " + ex.Message);
            }
        }
    }

    /// <summary>
    /// 快照里的每个方块都要 ItemManager.GetItemByIndex 拿 Item_Base；拿不到时
    /// 原版 CreateBlock 静默 return null，方块凭空消失。这里统计缺失的 BlockIndex。
    /// </summary>
    [HarmonyPatch(typeof(BlockCreator), "Deserialize", new[]
    {
        typeof(Message_NetworkBehaviour), typeof(Network_UserId)
    })]
    internal static class Patch_DiagBlockCreatorDeserialize
    {
        private static void Prefix(Message_NetworkBehaviour msg)
        {
            if (msg == null || msg.Type != Messages.BlockCreator_Create)
            {
                return;
            }

            try
            {
                Message_BlockCreator_Create create = msg as Message_BlockCreator_Create;
                if (create == null || create.rgdBlocks == null)
                {
                    return;
                }

                int missing = 0;
                string firstIndexes = string.Empty;
                for (int i = 0; i < create.rgdBlocks.Length; i++)
                {
                    RGD_Block block = create.rgdBlocks[i];
                    if (block == null || ItemManager.GetItemByIndex(block.BlockIndex) != null)
                    {
                        continue;
                    }

                    missing++;
                    if (firstIndexes.Length < 120)
                    {
                        firstIndexes += (firstIndexes.Length == 0 ? string.Empty : ",") + block.BlockIndex;
                    }
                }

                if (missing > 0)
                {
                    AstralDiag.Note(
                        "drop block (item missing)",
                        "msg=" + missing + "/" + create.rgdBlocks.Length
                        + " idx=" + firstIndexes
                        + " behaviourIndex=" + create.BehaviourIndex);
                }
            }
            catch (System.Exception ex)
            {
                AstralLog.Error("diag block create: " + ex.Message);
            }
        }
    }
}
