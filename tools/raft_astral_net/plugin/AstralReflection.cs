using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using PlayFab.ClientModels;
using PlayFab.Party;
using Steamworks;
using UnityEngine;
using UnityEngine.UI;

namespace AstralRaftNet
{
    /// <summary>
    /// 所有对游戏私有字段/方法的反射访问都集中在这张表里：
    /// 类型 + 成员名 + 期望签名。启动时统一校验一次，缺失就走红底横幅提示。
    /// 这样游戏更新改名后的失效方式是玩家可见的提示，而不是运行期静默不回包。
    /// </summary>
    internal static class AstralReflection
    {
        private sealed class Entry
        {
            public string TypeName;
            public Type Type;
            public string Member;
            public Type[] Args;        // null 表示字段
            public Type FieldType;     // 字段期望类型，可空
            public Type ReturnType;    // 方法期望返回类型，可空
            public FieldInfo Field;
            public MethodInfo Method;

            public string Key
            {
                get { return KeyOf(TypeName, Member, Args); }
            }

            public string Describe()
            {
                string member = TypeName + "." + Member;
                if (Args == null)
                {
                    return member;
                }

                string[] names = new string[Args.Length];
                for (int i = 0; i < Args.Length; i++)
                {
                    names[i] = Args[i].Name;
                }

                return member + "(" + string.Join(", ", names) + ")";
            }
        }

        private static readonly Type[] NoArgs = new Type[0];

        private static readonly List<Entry> Entries = new List<Entry>
        {
            // Raft_Network 字段
            Field(typeof(Raft_Network), "localSteamID", typeof(Network_UserId)),
            Field(typeof(Raft_Network), "worldLoadedCoroutine", typeof(Coroutine)),
            Field(typeof(Raft_Network), "worldRequestedCoroutine", typeof(Coroutine)),
            Field(typeof(Raft_Network), "bedRespawnPoint", typeof(GameObject)),
            Field(typeof(Raft_Network), "isHost", typeof(bool)),
            Field(typeof(Raft_Network), "connectedToHost", typeof(bool)),
            Field(typeof(Raft_Network), "hostID", typeof(Network_UserId)),
            Field(typeof(Raft_Network), "m_currentSteamHost", typeof(CSteamID)),
            Field(typeof(Raft_Network), "gameManagerStartCalled", typeof(bool)),
            Field(typeof(Raft_Network), "remoteUsers", typeof(Dictionary<Network_UserId, Network_Player>)),
            Field(typeof(Raft_Network), "m_hostedPlayFab", typeof(bool)),
            Field(typeof(Raft_Network), "playerInfos", typeof(Dictionary<Network_UserId, PlayerInfo>)),

            // Raft_Network 方法
            Method(typeof(Raft_Network), "WorldHasBeenLoaded", typeof(System.Collections.IEnumerator), NoArgs),
            Method(typeof(Raft_Network), "RequestWorldAsClient", typeof(System.Collections.IEnumerator), NoArgs),
            Method(typeof(Raft_Network), "GetWorld", typeof(List<Message>), NoArgs),
            Method(typeof(Raft_Network), "ParseRemoteMessage", typeof(void),
                new[] { typeof(Message), typeof(PlayFabPlayer) }),
            Method(typeof(Raft_Network), "ParseLocalMessage", typeof(void),
                new[] { typeof(Message), typeof(Network_UserId) }),
            Method(typeof(Raft_Network), "LoadScene", typeof(void), new[] { typeof(string) }),
            Method(typeof(Raft_Network), "SendP2P", typeof(void),
                new[] { typeof(Network_UserId), typeof(Message), typeof(EP2PSend), typeof(NetworkChannel) }),
            Method(typeof(Raft_Network), "OnDisconnect", typeof(void),
                new[] { typeof(Network_UserId), typeof(DisconnectReason), typeof(bool) }),

            // 其它运行时类型
            Field(typeof(PersonController), "controller", typeof(Component)),
            Method(typeof(PlayFabPlayer), "_SetEntityKey", typeof(void), new[] { typeof(EntityKey) }),

            // 创建 / 读取游戏界面
            Field(typeof(NewGameBox), "multiplayerAllowed", typeof(bool)),
            Field(typeof(NewGameBox), "offlineText", typeof(Text)),
            Field(typeof(NewGameBox), "toggle_FriendlyFire", typeof(Toggle)),
            Field(typeof(NewGameBox), "inputfield_Password", typeof(InputField)),
            Field(typeof(NewGameBox), "inputfield_GameName", typeof(InputField)),
            Field(typeof(NewGameBox), "text_nameFeedback", typeof(Text)),
            Field(typeof(NewGameBox), "createGameButton", typeof(Button)),
            Field(typeof(NewGameBox), "createGameText", typeof(GameObject)),
            Field(typeof(LoadGameBox), "multiplayerAllowed", typeof(bool)),
            Field(typeof(LoadGameBox), "offlineText", typeof(Text)),
            Field(typeof(LoadGameBox), "allowFriendlyFireToggle", typeof(Toggle)),
            Field(typeof(LoadGameBox), "inputfield_Password", typeof(InputField)),
            Field(typeof(LoadGameBox), "selectedGame", typeof(LoadGame_Selection)),
            Field(typeof(LoadGameBox), "loadButton", typeof(Button)),
            Field(typeof(LoadGameBox), "loadGameText", typeof(GameObject)),

            // 加入界面（Console 版）
            Field(typeof(JoinGameBoxConsole), "multiplayerAllowed", typeof(bool)),
            Field(typeof(JoinGameBoxConsole), "crossplayAllowed", typeof(bool)),
            Field(typeof(JoinGameBoxConsole), "onlineFeaturesNotAvailable", typeof(GameObject)),
            Field(typeof(JoinGameBoxConsole), "refreshButton", typeof(Button)),
            Field(typeof(JoinGameBoxConsole), "refreshText", typeof(GameObject)),
            Field(typeof(JoinGameBoxConsole), "selectedGame", typeof(JoinGameConsole_Selection)),
            Field(typeof(JoinGameBoxConsole), "joinGameButton", typeof(Button)),
            Field(typeof(JoinGameBoxConsole), "joinGameText", typeof(GameObject)),
            Field(typeof(JoinGameBoxConsole), "crossPlatformButton", typeof(Button)),
            Field(typeof(JoinGameBoxConsole), "worldButtonText", typeof(GameObject)),
            Field(typeof(JoinGameBoxConsole), "scrollRect", typeof(ScrollRect)),
            Field(typeof(JoinGameBoxConsole), "gameSelectionPrefab", typeof(JoinGameConsole_Selection)),
            Field(typeof(JoinGameBoxConsole), "joinGameSelections", typeof(List<JoinGameConsole_Selection>)),
            Field(typeof(JoinGameBoxConsole), "noGamesFoundsText", typeof(GameObject)),
            Field(typeof(JoinGameBoxConsole), "connectingBox", typeof(ConnectingBox)),
            Field(typeof(JoinGameConsole_Selection), "gameMode", typeof(Text)),
            Field(typeof(JoinGameConsole_Selection), "crossPlay", typeof(Text)),

            // 加入界面（旧版）
            Field(typeof(JoinGameBox), "joinGameButton", typeof(Button)),
            Field(typeof(JoinGameBox), "cheat_joinGameSteamID", typeof(InputField)),
            Field(typeof(JoinGameBox), "cheat_joinGamePassword", typeof(InputField)),
            Field(typeof(JoinGameBox), "noGamesFoundsText", typeof(GameObject)),
            Field(typeof(JoinGameBox), "scrollRect", typeof(ScrollRect)),
            Field(typeof(JoinGameBox), "gameSelectionPrefab", typeof(JoinGame_Selection)),
            Field(typeof(JoinGameBox), "joinGameSelections", typeof(List<JoinGame_Selection>)),
            Field(typeof(JoinGameBox), "selectedGame", typeof(JoinGame_Selection)),
            Field(typeof(JoinGameBox), "connectingBox", typeof(ConnectingBox)),
            Field(typeof(JoinGame_Selection), "text_GameName", typeof(Text)),
            Field(typeof(JoinGame_Selection), "image_passwordLock", typeof(Image))
        };

        private static readonly Dictionary<string, Entry> Index =
            new Dictionary<string, Entry>(StringComparer.Ordinal);

        private static string _missing;
        private static bool _initialized;

        /// <summary>缺失清单；null 表示表中所有成员都命中。</summary>
        public static string Missing
        {
            get { return _missing; }
        }

        public static void Initialize()
        {
            if (_initialized)
            {
                return;
            }

            _initialized = true;
            List<string> missing = new List<string>();
            for (int i = 0; i < Entries.Count; i++)
            {
                Entry entry = Entries[i];
                Index[entry.Key] = entry;
                if (entry.Type == null)
                {
                    missing.Add(entry.TypeName + "（类型缺失）");
                    continue;
                }

                if (entry.Args == null)
                {
                    entry.Field = AccessTools.Field(entry.Type, entry.Member);
                    if (entry.Field == null)
                    {
                        missing.Add(entry.Describe());
                        continue;
                    }

                    if (entry.FieldType != null && !entry.FieldType.IsAssignableFrom(entry.Field.FieldType))
                    {
                        missing.Add(entry.Describe() + "（实际字段类型 " + entry.Field.FieldType.Name + "）");
                    }

                    continue;
                }

                entry.Method = AccessTools.Method(entry.Type, entry.Member, entry.Args);
                if (entry.Method == null)
                {
                    missing.Add(entry.Describe());
                    continue;
                }

                if (entry.ReturnType != null && entry.ReturnType != entry.Method.ReturnType)
                {
                    missing.Add(entry.Describe() + "（实际返回类型 " + entry.Method.ReturnType.Name + "）");
                }
            }

            _missing = missing.Count == 0 ? null : string.Join("、", missing.ToArray());
        }

        public static FieldInfo Field(Type type, string name)
        {
            EnsureInitialized();
            Entry entry;
            if (!Index.TryGetValue(KeyOf(type.Name, name, null), out entry))
            {
                // 表里没有登记就说明有新的散落反射调用漏网，直接暴露出来。
                AstralLog.Error("reflection field not registered: " + type.Name + "." + name);
                return null;
            }

            return entry.Field;
        }

        public static MethodInfo Method(Type type, string name, params Type[] args)
        {
            EnsureInitialized();
            Entry entry;
            if (!Index.TryGetValue(KeyOf(type.Name, name, args), out entry))
            {
                AstralLog.Error("reflection method not registered: " + type.Name + "." + name);
                return null;
            }

            return entry.Method;
        }

        private static void EnsureInitialized()
        {
            if (!_initialized)
            {
                Initialize();
            }
        }

        private static string KeyOf(string typeName, string member, Type[] args)
        {
            if (args == null)
            {
                return typeName + "|" + member + "|field";
            }

            string[] names = new string[args.Length];
            for (int i = 0; i < args.Length; i++)
            {
                names[i] = args[i].FullName ?? args[i].Name;
            }

            return typeName + "|" + member + "|" + string.Join(",", names);
        }

        private static Entry Field(Type type, string name, Type fieldType)
        {
            return new Entry
            {
                TypeName = type.Name,
                Type = type,
                Member = name,
                FieldType = fieldType
            };
        }

        private static Entry Method(Type type, string name, Type returnType, Type[] args)
        {
            return new Entry
            {
                TypeName = type.Name,
                Type = type,
                Member = name,
                Args = args,
                ReturnType = returnType
            };
        }
    }
}
