using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using HarmonyLib;
using kcp2k;
using PlayFab.Party;
using Steamworks;
using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralTransport
    {
        public const int DefaultPort = 6488;
        private const int MaxPacket = 64 * 1024 * 1024;
        private const int MaxKcpMessage = 240 * 1024;
        private const int MaxUnreliable = 1190;
        private const byte KindHello = 1;
        private const byte KindWelcome = 2;
        private const byte KindKcp = 3;
        private const byte KindUnreliable = 4;
        // 握手 v2：密码不明文，只发 nonce + SHA256(nonce||password)。
        private const byte KindHelloV2 = 5;

        // 中继帧：可靠帧的 channel 字节最高位置 1，负载前 8 字节是原始发送者 SteamID。
        private const byte ChannelRelayFlag = AstralWireFormat.ChannelRelayFlag;

        // 每帧最多应用/反序列化的网络消息数。首次进房世界快照上万条，
        // 单帧全量应用会直接卡死主线程，必须分帧。
        private const int ApplyBudgetPerFrame = 200;
        private const int DeserializeBudgetPerFrame = 400;
        private const int PendingHighWater = 1000;

        // 世界下发超时（秒）。超时后自动重试，重试次数用完才提示玩家。
        private const float WorldTimeoutSeconds = 60f;
        // 超时后自动重试的最大次数（不含首次请求）；用完即停，不会无限循环。
        private const int MaxWorldAutoRetries = 3;

        // 单机/离线没有 SteamID 时使用的自建身份，持久化保证存档归属稳定。
        private const string PrefLocalId = "AstralLocalId";

        private static readonly ConcurrentQueue<Action> MainThread = new ConcurrentQueue<Action>();
        private static readonly ConcurrentQueue<QueuedPacket>[] Incoming =
        {
            new ConcurrentQueue<QueuedPacket>(),
            new ConcurrentQueue<QueuedPacket>()
        };
        private static readonly ConcurrentQueue<QueuedPacket> IncomingMessages = new ConcurrentQueue<QueuedPacket>();
        private static readonly Queue<PendingMessage> Pending = new Queue<PendingMessage>();
        private static readonly Dictionary<ulong, object> FakePlayers = new Dictionary<ulong, object>();
        private static readonly object[] ParseArgs = new object[2];
        private static MethodInfo _parseRemote;
        private static FastInvokeHandler _parseRemoteInvoke;
        private static Raft_Network _cachedNetwork;
        private static bool _worldInitDone;
        private static readonly object LocalIdLock = new object();
        private static ulong _generatedLocalId;

        private static readonly Dictionary<ulong, Peer> Peers = new Dictionary<ulong, Peer>();
        private static readonly object PeersLock = new object();

        private static UdpClient _udp;
        private static readonly object UdpSendLock = new object();
        private static Thread _recvThread;
        private static volatile bool _recvRunning;
        private static volatile bool _listening;
        private static byte[] _handshakeWelcome;
        private static IPEndPoint _handshakeTarget;
        private static ulong _announcedHostSteam;
        private static int _listenPort = DefaultPort;
        private static string _status = "idle";
        private static volatile bool _connecting;
        private static ulong _joinHostSteam;
        private static bool _sceneLoadStarted;
        private static bool _astralWorldReceived;
        private static float _lastWorldRequest;
        private static float _lastLandmarkWaitLog;
        private static float _joinWatchdogStart;
        private static volatile bool _worldTimedOut;
        private static int _worldAutoRetries;

        // 中继去重：房主应用某条客机消息期间，游戏自身可能已经用 RPC/RPCExclude 转发过，
        // 这里记录应用期间已经发到过的 peer，之后只补发没收到的那部分。
        private static readonly HashSet<ulong> RelaySent = new HashSet<ulong>();
        private static bool _relayTracking;

        // 分帧展开 Compound 的游标，跨帧保持。
        private static Message_Compound _expandingCompound;
        private static int _expandingIndex;
        private static PendingMessage _expandingItem;

        public static int Port
        {
            get { return _listenPort; }
            set { _listenPort = value <= 0 ? DefaultPort : value; }
        }

        public static string Status
        {
            get { return _status; }
        }

        public static bool Listening
        {
            get { return _listening; }
        }

        public static int PeerCount
        {
            get
            {
                lock (PeersLock)
                {
                    return Peers.Count;
                }
            }
        }

        public static void PumpMainThread()
        {
            Action action;
            while (MainThread.TryDequeue(out action))
            {
                try
                {
                    action();
                }
                catch (Exception ex)
                {
                    AstralLog.Error(ex.ToString());
                }
            }

            TickKcp();
            DeliverMessages();
            TryRequestWorldAsClient();
            TickWorldInit();
            TickWorldTimeout();
            if (IsJoining && !_astralWorldReceived)
            {
                StopConnectingBox();
            }
        }

        public static bool IsJoining
        {
            get { return _connecting || (_sceneLoadStarted && !_astralWorldReceived); }
        }

        public static bool WorldReceived
        {
            get { return _astralWorldReceived; }
        }

        /// <summary>
        /// 联机身份：只认真实 SteamID。拿不到时返回 0，调用方必须报错，
        /// 不允许静默改用别的 ID。LocalId 只在离线单机给存档归属用。
        /// </summary>
        public static ulong SteamId
        {
            get
            {
                try
                {
                    CSteamID steam = SteamUser.GetSteamID();
                    return steam.IsValid() ? steam.m_SteamID : 0UL;
                }
                catch (Exception)
                {
                    return 0UL;
                }
            }
        }

        /// <summary>
        /// 离线身份：仅在拿不到 SteamID 的单机/离线场景用于存档归属，
        /// 不参与联机握手、peer 标识或 hostID。
        /// </summary>
        public static ulong LocalId
        {
            get
            {
                ulong steam = SteamId;
                if (steam != 0UL)
                {
                    return steam;
                }

                lock (LocalIdLock)
                {
                    if (_generatedLocalId != 0UL)
                    {
                        return _generatedLocalId;
                    }

                    string saved = PlayerPrefs.GetString(PrefLocalId, string.Empty);
                    ulong id;
                    if (!ulong.TryParse(saved, out id) || id == 0UL)
                    {
                        id = BitConverter.ToUInt64(Guid.NewGuid().ToByteArray(), 0);
                        if (id == 0UL)
                        {
                            id = 1UL;
                        }

                        PlayerPrefs.SetString(PrefLocalId, id.ToString());
                        PlayerPrefs.Save();
                        AstralLog.Info("generated local id " + id);
                    }

                    _generatedLocalId = id;
                    return id;
                }
            }
        }

        public static void ClearJoinState()
        {
            _connecting = false;
            _joinHostSteam = 0UL;
            _announcedHostSteam = 0UL;
            _handshakeWelcome = null;
            _handshakeTarget = null;
            _sceneLoadStarted = false;
            _astralWorldReceived = false;
            _worldInitDone = false;
            _cachedNetwork = null;
            _worldAutoRetries = 0;
            _lastWorldRequest = 0f;
            _lastLandmarkWaitLog = 0f;
            _joinWatchdogStart = 0f;
            _worldTimedOut = false;
            _expandingCompound = null;
            _expandingIndex = 0;
            _expandingItem = default(PendingMessage);
            _relayTracking = false;
            RelaySent.Clear();
        }

        private static void TickWorldInit()
        {
            if (_worldInitDone)
            {
                return;
            }

            if (!_astralWorldReceived)
            {
                return;
            }

            try
            {
                Raft_Network network = GetNetwork();
                if (network == null || Raft_Network.IsHost)
                {
                    return;
                }

                object running = AstralReflection.Field(typeof(Raft_Network), "worldLoadedCoroutine").GetValue(network);
                if (running == null)
                {
                    MethodInfo method = AstralReflection.Method(typeof(Raft_Network), "WorldHasBeenLoaded");
                    IEnumerator routine = method.Invoke(network, null) as IEnumerator;
                    if (routine != null)
                    {
                        Coroutine started = network.StartCoroutine(routine);
                        AstralReflection.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, started);
                        AstralLog.Info("start WorldHasBeenLoaded");
                    }
                }

                Network_Player local = network.GetLocalPlayer();
                if (local != null && local.IsLocalPlayer && Raft_Network.WorldHasBeenRecieved)
                {
                    _status = "in world peers=" + PeerCount;
                    _worldInitDone = true;
                }
                else if (Raft_Network.WorldHasBeenRecieved)
                {
                    _status = "world received, waiting local player";
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("world init: " + ex.Message);
            }
        }

        private static Raft_Network GetNetwork()
        {
            if (_cachedNetwork != null)
            {
                return _cachedNetwork;
            }

            _cachedNetwork = UnityEngine.Object.FindObjectOfType<Raft_Network>();
            return _cachedNetwork;
        }

        private static void DeliverMessages()
        {
            QueuedPacket packet;
            int deserializeBudget = DeserializeBudgetPerFrame;
            while (deserializeBudget > 0 && Pending.Count < PendingHighWater && IncomingMessages.TryDequeue(out packet))
            {
                try
                {
                    Message message = AstralMessages.Deserialize(packet.Data);
                    if (message == null)
                    {
                        AstralLog.Error("deserialize failed bytes=" + packet.Data.Length + " from=" + packet.SteamId);
                        continue;
                    }

                    Message_Compound compound = message as Message_Compound;
                    deserializeBudget -= compound != null && compound.messages != null
                        ? Math.Max(1, compound.messages.Count)
                        : 1;
                    Pending.Enqueue(new PendingMessage
                    {
                        SteamId = packet.SteamId,
                        Message = message,
                        Raw = packet.Data,
                        Channel = packet.Channel,
                        Unreliable = packet.Unreliable,
                        Relayed = packet.Relayed
                    });
                }
                catch (Exception ex)
                {
                    AstralLog.Error("deliver: " + ex.Message);
                }
            }

            if (Pending.Count == 0 && _expandingCompound == null)
            {
                return;
            }

            Raft_Network network = GetNetwork();
            if (network == null)
            {
                return;
            }

            if (_parseRemoteInvoke == null)
            {
                _parseRemote = AstralReflection.Method(typeof(Raft_Network), "ParseRemoteMessage",
                    typeof(Message), typeof(PlayFabPlayer));
                _parseRemoteInvoke = MethodInvoker.GetHandler(_parseRemote);
            }

            // 每帧只应用固定配额，剩余留在队列里。实体位移等实时消息只是晚一两帧，
            // 而世界快照不会再把主线程一次性卡死。
            int budget = ApplyBudgetPerFrame;
            while (budget > 0)
            {
                if (_expandingCompound != null)
                {
                    if (_expandingIndex >= _expandingCompound.messages.Count)
                    {
                        FinishExpand();
                        continue;
                    }

                    Message child = _expandingCompound.messages[_expandingIndex++];
                    ApplyOne(network, _expandingItem.SteamId, child);
                    budget--;
                    if (_expandingIndex >= _expandingCompound.messages.Count)
                    {
                        FinishExpand();
                    }

                    continue;
                }

                if (Pending.Count == 0)
                {
                    break;
                }

                PendingMessage item = Pending.Dequeue();
                if (item.Message != null && item.Message.Type == Messages.Compound)
                {
                    Message_Compound compound = item.Message as Message_Compound;
                    if (compound == null || compound.messages == null)
                    {
                        AstralLog.Error("compound empty from=" + item.SteamId);
                        continue;
                    }

                    AstralLog.Info("expand Compound children=" + compound.messages.Count + " from=" + item.SteamId);
                    _expandingCompound = compound;
                    _expandingIndex = 0;
                    _expandingItem = item;
                    continue;
                }

                ApplyWithRelay(network, item);
                budget--;
            }
        }

        private static void FinishExpand()
        {
            // Compound 只由房主在世界下发时生成，客机不会发 Compound，
            // 因此这里不转发，避免把整份世界快照再回灌给其他客机。
            _expandingCompound = null;
            _expandingIndex = 0;
            _expandingItem = default(PendingMessage);
        }

        /// <summary>
        /// 应用一条客机消息；房主应用结束后，把游戏自身没有转发到的 peer 补齐。
        /// </summary>
        private static void ApplyWithRelay(Raft_Network network, PendingMessage item)
        {
            bool relay = CanRelay(item);
            if (relay)
            {
                RelaySent.Clear();
                _relayTracking = true;
            }

            try
            {
                ApplyOne(network, item.SteamId, item.Message);
            }
            finally
            {
                _relayTracking = false;
            }

            if (relay)
            {
                RelayToPeers(item, RelaySent);
            }
        }

        private static bool CanRelay(PendingMessage item)
        {
            if (!_listening || item.Relayed || item.Raw == null || item.SteamId == 0UL || item.Message == null)
            {
                return false;
            }

            if (!Raft_Network.IsHost || IsSessionControl(item.Message.Type))
            {
                return false;
            }

            // 只有房主 + 至少两个客机才需要中继。
            return PeerCount > 1;
        }

        /// <summary>
        /// 会话控制类消息只属于客机 ↔ 房主，不能转给其他客机。
        /// 例如 PlayerJoined 被转发后，其他客机会误以为有人要加入并回 KickUser。
        /// </summary>
        private static bool IsSessionControl(Messages type)
        {
            switch (type)
            {
                case Messages.RequestWorld:
                case Messages.PlayerJoined:
                case Messages.InitiateResult:
                case Messages.NetworkVersion:
                case Messages.KickUser:
                case Messages.Ping:
                case Messages.Pong:
                case Messages.WorldReceived:
                case Messages.WorldGuid:
                case Messages.Save:
                case Messages.CreatePlayer:
                case Messages.Compound:
                    return true;
                default:
                    return false;
            }
        }

        private static void RelayToPeers(PendingMessage item, HashSet<ulong> alreadySent)
        {
            List<ulong> ids;
            lock (PeersLock)
            {
                ids = new List<ulong>(Peers.Keys);
            }

            int relayed = 0;
            for (int i = 0; i < ids.Count; i++)
            {
                ulong id = ids[i];
                if (id == item.SteamId || alreadySent.Contains(id))
                {
                    continue;
                }

                if (TrySendRelayed(id, item.Raw, item.Channel, item.Unreliable, item.SteamId))
                {
                    relayed++;
                }
            }

            if (relayed > 0)
            {
                AstralLog.Info(
                    "relay " + item.Message.Type + " from=" + item.SteamId + " to=" + relayed + " peers");
            }
        }

        /// <summary>
        /// 转发时保留原始发送者：负载前 8 字节写入来源 SteamID，
        /// 接收端据此还原 remoteID，避免所有中继消息都被当成房主发的。
        /// </summary>
        private static bool TrySendRelayed(ulong steamId, byte[] raw, int channel, bool unreliable, ulong origin)
        {
            if (raw == null || origin == 0UL)
            {
                return false;
            }

            Peer peer;
            lock (PeersLock)
            {
                if (!Peers.TryGetValue(steamId, out peer))
                {
                    return false;
                }
            }

            byte[] framed = AstralWireFormat.FrameRelay(raw, origin);
            byte marked = (byte)(channel | ChannelRelayFlag);

            try
            {
                if (unreliable && framed.Length <= MaxUnreliable)
                {
                    peer.SendUnreliable(marked, framed);
                }
                else
                {
                    peer.SendReliable(marked, framed);
                }

                return true;
            }
            catch (Exception ex)
            {
                AstralLog.Error("relay send failed to=" + steamId + ": " + ex.Message);
                RemovePeer(steamId);
                return false;
            }
        }

        private static ulong ReadRelayOrigin(ref byte[] payload)
        {
            ulong origin;
            return AstralWireFormat.TryUnframeRelay(ref payload, out origin) ? origin : 0UL;
        }

        private static int ApplyOne(Raft_Network network, ulong steamId, Message message)
        {
            try
            {
                object fake;
                if (!FakePlayers.TryGetValue(steamId, out fake) || fake == null)
                {
                    fake = AstralMessages.FakePlayer(steamId);
                    FakePlayers[steamId] = fake;
                }

                if (message != null && ShouldLog(message.Type))
                {
                    AstralLog.Info("recv " + message.Type + " from=" + steamId + " left=" + Pending.Count);
                }

                if (message != null && message.Type == Messages.CreatePlayer)
                {
                    Message_Player_Create create = message as Message_Player_Create;
                    if (create != null)
                    {
                        AstralLog.Info("recv CreatePlayer user=" + create.UserId.Id + " local=" + network.LocalSteamID.Id);
                    }
                }

                ParseArgs[0] = message;
                ParseArgs[1] = fake;
                _parseRemoteInvoke(network, ParseArgs);
                ParseArgs[0] = null;
                ParseArgs[1] = null;

                if (message != null && message.Type == Messages.WorldReceived)
                {
                    _astralWorldReceived = true;
                    _worldTimedOut = false;
                    _status = "world received peers=" + PeerCount;
                    AstralLog.Info("world snapshot applied, localPlayer=" + (network.GetLocalPlayer() != null));
                    SnapLocalPlayerToBed(network);
                }

                return 1;
            }
            catch (TargetInvocationException ex)
            {
                Exception inner = ex.InnerException ?? ex;
                AstralLog.Error("parse " + (message != null ? message.Type.ToString() : "?") + ": " + inner);
                return 1;
            }
            catch (Exception ex)
            {
                AstralLog.Error("parse: " + ex.Message);
                return 1;
            }
        }

        /// <summary>
        /// 原版 InternalAddPlayer 用 bedRespawnPoint（RespawnPointBed）世界坐标 Instantiate；
        /// CreatePlayer 消息本身不含坐标。世界快照应用完后强制对齐一次，避免限流窗口内掉落残留。
        /// </summary>
        private static void SnapLocalPlayerToBed(Raft_Network network)
        {
            if (network == null || Raft_Network.IsHost)
            {
                return;
            }

            try
            {
                Network_Player local = network.GetLocalPlayer();
                FieldInfo bedField = AstralReflection.Field(typeof(Raft_Network), "bedRespawnPoint");
                GameObject bed = bedField != null ? bedField.GetValue(network) as GameObject : null;
                if (bed == null)
                {
                    bed = GameObject.FindWithTag("RespawnPointBed");
                    if (bed != null && bedField != null)
                    {
                        bedField.SetValue(network, bed);
                    }
                }

                if (local == null || bed == null)
                {
                    AstralLog.Info(
                        "snap bed skipped local=" + (local != null) + " bed=" + (bed != null));
                    return;
                }

                Vector3 pos = bed.transform.position;
                Behaviour controller = null;
                if (local.PersonController != null)
                {
                    FieldInfo controllerField = AstralReflection.Field(typeof(PersonController), "controller");
                    if (controllerField != null)
                    {
                        controller = controllerField.GetValue(local.PersonController) as Behaviour;
                    }
                }

                if (controller != null)
                {
                    controller.enabled = false;
                }

                local.transform.position = pos;
                if (controller != null)
                {
                    controller.enabled = true;
                }

                AstralLog.Info("snap local to bed " + pos);
            }
            catch (Exception ex)
            {
                AstralLog.Error("snap bed: " + ex.Message);
            }
        }

        private static bool ShouldLog(Messages type)
        {
            return type == Messages.PlayerJoined
                || type == Messages.RequestWorld
                || type == Messages.NetworkVersion
                || type == Messages.WorldReceived
                || type == Messages.KickUser
                || type == Messages.InitiateResult
                || type == Messages.Compound
                || type == Messages.CreatePlayer;
        }

        public static void StartListen(int port)
        {
            if (_listening)
            {
                StartLanBroadcast();
                return;
            }

            Port = port;
            try
            {
                // 联机身份必须是真实 SteamID；拿不到就报错，不静默换成 LocalId。
                if (SteamId == 0UL)
                {
                    _status = "listen failed: no steam id";
                    AstralLog.Error("listen refused: no valid SteamID, online play needs Steam");
                    return;
                }

                EnsureSocket(Port);
                _listening = true;
                _status = "listen udp 0.0.0.0:" + Port;
                AstralLog.Info(_status);
            }
            catch (Exception ex)
            {
                _listening = false;
                _status = "listen failed";
                AstralLog.Error("listen failed: " + ex.Message);
                return;
            }

            StartLanBroadcast();
        }

        private static void StartLanBroadcast()
        {
            string name = "ASGAME";
            try
            {
                name = SteamFriends.GetPersonaName() ?? name;
                if (!string.IsNullOrEmpty(SaveAndLoad.CurrentGameFileName))
                {
                    name = name + " · " + SaveAndLoad.CurrentGameFileName;
                }
            }
            catch (Exception ex)
            {
                AstralLog.Info("LAN broadcast name unavailable, use " + name + ": " + ex.Message);
            }

            bool password = false;
            try
            {
                password = GameManager.HasPassword;
            }
            catch (Exception ex)
            {
                AstralLog.Info("LAN broadcast password flag unavailable, assume open: " + ex.Message);
            }

            AstralLanDiscovery.StartBroadcast(Port, password, name);
        }

        public static void StopListen()
        {
            _listening = false;
            AstralLanDiscovery.StopBroadcast();
            if (!_status.StartsWith("connected", StringComparison.Ordinal))
            {
                _status = "idle";
            }
        }

        public static void DisconnectPeers()
        {
            List<Peer> snapshot;
            lock (PeersLock)
            {
                snapshot = new List<Peer>(Peers.Values);
                Peers.Clear();
            }

            foreach (Peer peer in snapshot)
            {
                peer.Close();
            }
        }

        public static void StopAll()
        {
            AstralLanDiscovery.StopAll();
            StopListen();
            DisconnectPeers();
            CloseSocket();
            QueuedPacket unused;
            for (int i = 0; i < Incoming.Length; i++)
            {
                while (Incoming[i].TryDequeue(out unused))
                {
                }
            }

            while (IncomingMessages.TryDequeue(out unused))
            {
            }

            Pending.Clear();
            FakePlayers.Clear();
            ClearJoinState();
            _status = "idle";
        }

        public static bool TrySendMessage(ulong steamId, Message message, int channel, EP2PSend sendType)
        {
            if (steamId == 0UL || message == null)
            {
                return false;
            }

            try
            {
                Message_Compound compound = message as Message_Compound;
                if (compound != null && compound.messages != null)
                {
                    compound.messages.RemoveAll(child => child == null);
                }

                byte[] payload = AstralMessages.Serialize(message);
                bool big = payload.Length >= 1024;
                if (ShouldLog(message.Type) || big)
                {
                    string extra = string.Empty;
                    if (compound != null && compound.messages != null)
                    {
                        extra = " children=" + compound.messages.Count;
                    }

                    AstralLog.Info(
                        "send " + message.Type + " to=" + steamId
                        + " bytes=" + payload.Length + extra
                        + " ch=" + channel
                        + (IsUnreliable(sendType) ? " udp" : " kcp"));
                }

                return TrySendRaw(steamId, payload, channel, IsUnreliable(sendType));
            }
            catch (Exception ex)
            {
                AstralLog.Error("serialize failed " + message.Type + ": " + ex.Message);
                return false;
            }
        }

        public static bool TrySendMessageOrHost(ulong steamId, Message message, int channel, EP2PSend sendType)
        {
            if (TrySendMessage(steamId, message, channel, sendType))
            {
                return true;
            }

            if (_joinHostSteam != 0UL && steamId != _joinHostSteam && TrySendMessage(_joinHostSteam, message, channel, sendType))
            {
                AstralLog.Info("send remap to host steam type=" + message.Type + " from=" + steamId);
                return true;
            }

            return false;
        }

        public static void BroadcastMessage(Message message, int channel, ulong excludeSteamId, EP2PSend sendType)
        {
            List<ulong> ids;
            lock (PeersLock)
            {
                ids = new List<ulong>(Peers.Keys);
            }

            for (int i = 0; i < ids.Count; i++)
            {
                if (ids[i] == excludeSteamId)
                {
                    continue;
                }

                TrySendMessage(ids[i], message, channel, sendType);
            }
        }

        private static bool IsUnreliable(EP2PSend sendType)
        {
            return (int)sendType <= 1;
        }

        private static bool TrySendRaw(ulong steamId, byte[] payload, int channel, bool unreliable)
        {
            if (payload == null)
            {
                return false;
            }

            Peer peer;
            lock (PeersLock)
            {
                if (!Peers.TryGetValue(steamId, out peer))
                {
                    return false;
                }
            }

            try
            {
                if (unreliable && payload.Length <= MaxUnreliable)
                {
                    peer.SendUnreliable((byte)channel, payload);
                }
                else
                {
                    peer.SendReliable((byte)channel, payload);
                    if (payload.Length >= 65536)
                    {
                        AstralLog.Info("kcp wrote bytes=" + payload.Length + " to=" + steamId);
                    }
                }

                // 房主应用客机消息期间，游戏自身的 RPC/RPCExclude 会主动转发一部分消息；
                // 记录这些 peer，之后只补发没被转发到的，避免重复投递。
                if (_relayTracking)
                {
                    RelaySent.Add(steamId);
                }

                return true;
            }
            catch (Exception ex)
            {
                AstralLog.Error("send failed to=" + steamId + " bytes=" + payload.Length + ": " + ex.Message);
                RemovePeer(steamId);
                return false;
            }
        }

        public static void ConnectAndJoin(string hostPort, string password)
        {
            ConnectAndJoin(hostPort, password, 0UL);
        }

        /// <param name="announcedSteam">
        /// 发现广播里声称的房主 SteamID。只用于"发现"，真实身份以握手 WELCOME 为准，
        /// 两者不一致时以握手值为准并记录日志。
        /// </param>
        public static void ConnectAndJoin(string hostPort, string password, ulong announcedSteam)
        {
            string host;
            int port;
            if (!TryParseHostPort(hostPort, out host, out port))
            {
                AstralLog.Error("bad address: " + hostPort);
                return;
            }

            if (_connecting)
            {
                AstralLog.Info("ignore duplicate connect, still connecting");
                return;
            }

            // 联机身份必须是真实 SteamID；拿不到就报错，不静默换成 LocalId。
            ulong localId = SteamId;
            if (localId == 0UL)
            {
                _status = "connect failed: no steam id";
                AstralLog.Error("join refused: no valid SteamID, online play needs Steam");
                return;
            }

            _connecting = true;
            _announcedHostSteam = announcedSteam;
            _handshakeWelcome = null;
            _handshakeTarget = null;
            _status = "connecting " + host + ":" + port;
            StopConnectingBox();
            ThreadPool.QueueUserWorkItem(_ => ConnectWorker(host, port, password ?? string.Empty, localId));
        }

        private static void ConnectWorker(string host, int port, string password, ulong localSteamId)
        {
            try
            {
                EnsureSocket(0);
                IPAddress[] addresses = Dns.GetHostAddresses(host);
                IPAddress ip = null;
                for (int i = 0; i < addresses.Length; i++)
                {
                    if (addresses[i].AddressFamily == AddressFamily.InterNetwork)
                    {
                        ip = addresses[i];
                        break;
                    }
                }

                if (ip == null)
                {
                    throw new IOException("no ipv4 for " + host);
                }

                IPEndPoint hostEp = new IPEndPoint(ip, port);
                CSteamID localId = new CSteamID(localSteamId);
                string localName = SteamFriends.GetPersonaName() ?? "player";
                _handshakeWelcome = null;
                // WELCOME 只接受来自这个端点的包，避免同网段任意主机抢先冒充房主。
                _handshakeTarget = hostEp;

                byte[] hello = BuildHelloV2(localId, localName, password);
                for (int attempt = 0; attempt < 12 && _handshakeWelcome == null; attempt++)
                {
                    SendUdp(hostEp, hello);
                    for (int wait = 0; wait < 16 && _handshakeWelcome == null; wait++)
                    {
                        Thread.Sleep(25);
                    }
                }

                if (_handshakeWelcome == null)
                {
                    // 旧版房主只认老的带明文密码的 HELLO。为了能加入旧房主必须回退一次，
                    // 这会在链路上暴露明文密码，日志里明确提示双方升级。
                    AstralLog.Info("handshake v2 no reply from " + hostEp
                        + ", fallback to legacy HELLO (cleartext password); upgrade both sides to avoid");
                    byte[] legacy = BuildLegacyHello(localId, localName, password);
                    for (int attempt = 0; attempt < 12 && _handshakeWelcome == null; attempt++)
                    {
                        SendUdp(hostEp, legacy);
                        for (int wait = 0; wait < 16 && _handshakeWelcome == null; wait++)
                        {
                            Thread.Sleep(25);
                        }
                    }
                }

                byte[] welcome = _handshakeWelcome;
                if (welcome == null || welcome.Length < 11 || welcome[0] != KindWelcome)
                {
                    throw new TimeoutException("udp handshake timeout");
                }

                ulong hostSteam = BitConverter.ToUInt64(welcome, 1);
                CSteamID hostId = new CSteamID(hostSteam);
                if (!hostId.IsValid())
                {
                    throw new IOException("host steam id invalid");
                }

                ushort nameLen = BitConverter.ToUInt16(welcome, 9);
                int extra = 11 + nameLen;
                GameMode hostMode = GameMode.Normal;
                bool friendlyFire = false;
                bool crossplay = true;
                if (welcome.Length > extra)
                {
                    hostMode = (GameMode)welcome[extra];
                }

                if (welcome.Length > extra + 1)
                {
                    byte flags = welcome[extra + 1];
                    friendlyFire = (flags & 1) != 0;
                    crossplay = (flags & 2) != 0;
                }

                // 发现包里的身份只是线索；握手结果才是本次会话的房主身份。
                AstralLanDiscovery.ConfirmHandshake(_announcedHostSteam, hostSteam);
                _handshakeTarget = null;
                CreatePeer(hostSteam, hostEp, localId.m_SteamID);

                _joinHostSteam = hostSteam;
                _connecting = false;
                _status = "connected " + host + ":" + port + " peers=" + PeerCount;
                AstralLog.Info("handshake ok udp/kcp, host=" + hostSteam + " local=" + localId.m_SteamID + " mode=" + hostMode);
                MainThread.Enqueue(() => JoinHost(hostId, password, hostMode, friendlyFire, crossplay));
            }
            catch (Exception ex)
            {
                _connecting = false;
                _handshakeTarget = null;
                _status = "connect failed";
                AstralLog.Error("connect failed: " + ex.Message);
            }
        }

        private static void JoinHost(CSteamID hostId, string password, GameMode hostMode, bool friendlyFire, bool crossplay)
        {
            StopConnectingBox();

            Raft_Network network = GetNetwork();
            if (network == null)
            {
                AstralLog.Error("Raft_Network not found");
                return;
            }

            ApplyHostGameMode(hostMode, friendlyFire, crossplay);

            // 本机联机身份 = 真实 SteamID；LocalId 不参与联机。
            CSteamID localId = new CSteamID(SteamId);
            if (hostId == localId)
            {
                AstralLog.Error("不能加入自己。请用另一台电脑/另一个Raft，填房主的虚拟IP，不要填 127.0.0.1");
                _status = "self-join blocked";
                return;
            }

            if (Raft_Network.IsHost && network.IsConnectedToHost)
            {
                AstralLog.Error("当前窗口已经是房主，不能再加入。加入请用另一个Raft客户端");
                _status = "already host";
                return;
            }

            if (_sceneLoadStarted || LoadSceneManager.IsLoadingScene || LoadSceneManager.IsGameSceneLoaded)
            {
                AstralLog.Info("udp ready, skip duplicate LoadScene host=" + hostId.m_SteamID);
                // 上次 RequestWorldAsClient 协程句柄可能仍挂着，不清掉就不会再要世界。
                AstralReflection.Field(typeof(Raft_Network), "worldRequestedCoroutine").SetValue(network, null);
                AstralReflection.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, null);
                _joinWatchdogStart = Time.realtimeSinceStartup;
                _worldTimedOut = false;
                _worldAutoRetries = 0;
                TryRequestWorldAsClient();
                _status = "reconnected " + hostId.m_SteamID;
                return;
            }

            GameManager.Password = password ?? string.Empty;
            AstralReflection.Field(typeof(Raft_Network), "isHost").SetValue(null, false);
            AstralReflection.Field(typeof(Raft_Network), "connectedToHost").SetValue(network, true);
            AstralReflection.Field(typeof(Raft_Network), "hostID").SetValue(network, new Network_UserId(hostId.m_SteamID));
            AstralReflection.Field(typeof(Raft_Network), "m_currentSteamHost").SetValue(network, hostId);
            AstralReflection.Field(typeof(Raft_Network), "gameManagerStartCalled").SetValue(network, false);
            AstralReflection.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, null);
            AstralReflection.Field(typeof(Raft_Network), "worldRequestedCoroutine").SetValue(network, null);
            _sceneLoadStarted = true;
            _joinWatchdogStart = Time.realtimeSinceStartup;
            _worldTimedOut = false;
            _worldAutoRetries = 0;
            AstralReflection.Method(typeof(Raft_Network), "LoadScene", typeof(string))
                .Invoke(network, new object[] { Raft_Network.GameSceneName });
            _status = "joining " + hostId.m_SteamID;
            AstralLog.Info("Astral join load scene host=" + hostId.m_SteamID + " localSteam=" + network.LocalSteamID.Id + " mode=" + GameManager.GameMode);
        }

        internal static void TryRequestWorldAsClient()
        {
            if (_joinHostSteam == 0UL)
            {
                return;
            }

            if (_astralWorldReceived)
            {
                return;
            }

            try
            {
                if (Raft_Network.WorldHasBeenRecieved)
                {
                    _astralWorldReceived = true;
                    return;
                }

                Raft_Network network = GetNetwork();
                if (network == null || Raft_Network.IsHost)
                {
                    return;
                }

                // 与原版 OnSceneLoaded 一致：走 RequestWorldAsClient 协程，
                // 内部会等 hostID + IsAllLandmarksLoaded，再 Platform_RequestWorldAsClient。
                // 重试不要求场景已加载完成：IsGameSceneLoaded 只在 WorldHasBeenRecieved 之后
                // 才置 true，拿它当守卫会让「重试世界」在加载界面里永远点不动。
                FieldInfo coroField = AstralReflection.Field(typeof(Raft_Network), "worldRequestedCoroutine");
                object running = coroField != null ? coroField.GetValue(network) : null;
                if (running != null)
                {
                    return;
                }

                if (!Raft_Network.IsAllLandmarksLoaded)
                {
                    if (Time.realtimeSinceStartup - _lastLandmarkWaitLog > 2f)
                    {
                        _lastLandmarkWaitLog = Time.realtimeSinceStartup;
                        AstralLog.Info("wait IsAllLandmarksLoaded before RequestWorld");
                    }

                    return;
                }

                if (Time.realtimeSinceStartup - _lastWorldRequest < 1f)
                {
                    return;
                }

                _lastWorldRequest = Time.realtimeSinceStartup;
                MethodInfo method = AstralReflection.Method(typeof(Raft_Network), "RequestWorldAsClient");
                IEnumerator routine = method.Invoke(network, null) as IEnumerator;
                if (routine == null)
                {
                    AstralLog.Error("RequestWorldAsClient returned null");
                    return;
                }

                Coroutine started = network.StartCoroutine(routine);
                if (coroField != null)
                {
                    coroField.SetValue(network, started);
                }

                AstralLog.Info(
                    "start RequestWorldAsClient coroutine host=" + _joinHostSteam
                    + " peers=" + PeerCount
                    + " landmarks=ready");
            }
            catch (Exception ex)
            {
                AstralLog.Error("request world: " + ex.Message);
            }
        }

        public static bool WorldTimedOut
        {
            get { return _worldTimedOut; }
        }

        /// <summary>
        /// 玩家手动重试世界下发：重置自动重试预算，清掉协程句柄后重新走 RequestWorldAsClient。
        /// </summary>
        public static void RetryWorld()
        {
            if (_joinHostSteam == 0UL)
            {
                AstralLog.Info("retry world skipped: not in an Astral session");
                return;
            }

            _worldAutoRetries = 0;
            RetryWorldInternal(true);
        }

        private static void RetryWorldInternal(bool manual)
        {
            _astralWorldReceived = false;
            _worldTimedOut = false;
            _lastWorldRequest = 0f;
            _joinWatchdogStart = Time.realtimeSinceStartup;
            _status = manual
                ? "retry world"
                : "auto retry world " + _worldAutoRetries + "/" + MaxWorldAutoRetries;
            try
            {
                Raft_Network network = GetNetwork();
                if (network != null)
                {
                    FieldInfo coroField = AstralReflection.Field(typeof(Raft_Network), "worldRequestedCoroutine");
                    object running = coroField != null ? coroField.GetValue(network) : null;
                    Coroutine coroutine = running as Coroutine;
                    if (coroutine != null)
                    {
                        network.StopCoroutine(coroutine);
                    }

                    if (coroField != null)
                    {
                        coroField.SetValue(network, null);
                    }

                    AstralReflection.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, null);
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("retry world reset: " + ex.Message);
            }

            AstralLog.Info((manual ? "retry world" : "auto retry world")
                + " host=" + _joinHostSteam
                + " attempt=" + _worldAutoRetries + "/" + MaxWorldAutoRetries);
            TryRequestWorldAsClient();
        }

        private static void TickWorldTimeout()
        {
            if (_astralWorldReceived || _joinHostSteam == 0UL || _joinWatchdogStart <= 0f)
            {
                _worldTimedOut = false;
                return;
            }

            if (_worldTimedOut || Time.realtimeSinceStartup - _joinWatchdogStart < WorldTimeoutSeconds)
            {
                return;
            }

            if (_worldAutoRetries < MaxWorldAutoRetries)
            {
                _worldAutoRetries++;
                AstralLog.Error("world timeout " + (int)WorldTimeoutSeconds + "s, auto retry "
                    + _worldAutoRetries + "/" + MaxWorldAutoRetries);
                AstralOverlay.ShowNotice("等待世界下发超时，正在自动重试（"
                    + _worldAutoRetries + "/" + MaxWorldAutoRetries + "）");
                RetryWorldInternal(false);
                return;
            }

            _worldTimedOut = true;
            _status = "world timeout " + (int)WorldTimeoutSeconds + "s";
            string notice = "等待房主下发世界超时（" + (int)WorldTimeoutSeconds
                + " 秒，已自动重试 " + MaxWorldAutoRetries
                + " 次）。按 F7 打开面板点「重试世界」，或确认房主仍停留在游戏中。";
            AstralLog.Error(notice);
            AstralOverlay.ShowNotice(notice);
        }

        private static void ApplyHostGameMode(GameMode hostMode, bool friendlyFire, bool crossplay)
        {
            try
            {
                GameModeValueManager.SelectCurrentGameMode(hostMode);
                GameManager.FriendlyFire = friendlyFire;
                GameManager.Crossplay = crossplay;
                AstralLog.Info("apply host gameMode=" + hostMode + " ff=" + friendlyFire + " crossplay=" + crossplay);
            }
            catch (Exception ex)
            {
                AstralLog.Error("apply gameMode: " + ex.Message);
            }
        }

        private static void StopConnectingBox()
        {
            try
            {
                ConnectingBox box = UnityEngine.Object.FindObjectOfType<ConnectingBox>();
                if (box == null)
                {
                    return;
                }

                box.StopAllCoroutines();
                box.gameObject.SetActive(false);
            }
            catch (Exception ex)
            {
                AstralLog.Info("hide ConnectingBox failed: " + ex.Message);
            }
        }

        private static void LogJoinResult(CSteamID remoteID, InitiateResult result)
        {
            AstralLog.Info("InitiateResult=" + result + " from=" + remoteID.m_SteamID);
            if (result != InitiateResult.Success)
            {
                _status = "join fail " + result;
            }
        }

        private static void EnsureSocket(int bindPort)
        {
            int want = bindPort < 0 ? 0 : bindPort;
            if (_udp != null)
            {
                int actual = 0;
                try
                {
                    IPEndPoint bound = _udp.Client.LocalEndPoint as IPEndPoint;
                    if (bound != null)
                    {
                        actual = bound.Port;
                    }
                }
                catch (Exception ex)
                {
                    AstralLog.Error("read udp endpoint: " + ex.Message);
                }

                // want == 0 表示"随便给个端口"，复用现有 socket 即可；
                // 否则必须确保实际监听端口与将要广播的端口一致，不能出现"广播 6488、实际随机端口"。
                if (want == 0 || actual == want)
                {
                    return;
                }

                AstralLog.Info("rebind udp " + actual + " -> " + want);
                CloseSocket();
            }

            IPEndPoint local = new IPEndPoint(IPAddress.Any, want);
            UdpClient udp = new UdpClient(local);
            udp.Client.SendBufferSize = 1024 * 1024;
            udp.Client.ReceiveBufferSize = 1024 * 1024;
            udp.Client.ReceiveTimeout = 500;
            _udp = udp;
            _recvRunning = true;
            _recvThread = new Thread(UdpRecvLoop)
            {
                IsBackground = true,
                Name = "AstralUdpRecv"
            };
            _recvThread.Start();
            AstralLog.Info("udp bind " + udp.Client.LocalEndPoint);
        }

        private static void CloseSocket()
        {
            _recvRunning = false;
            UdpClient udp = _udp;
            _udp = null;
            if (udp != null)
            {
                try
                {
                    udp.Close();
                }
                catch (Exception ex)
                {
                    AstralLog.Info("udp close: " + ex.Message);
                }
            }

            // 等旧接收线程退出，避免它在新 socket 建立后继续读取同一个 _udp 字段造成双线程抢包。
            Thread recv = _recvThread;
            _recvThread = null;
            if (recv != null && recv != Thread.CurrentThread)
            {
                try
                {
                    recv.Join(500);
                }
                catch (Exception ex)
                {
                    AstralLog.Info("udp recv thread join: " + ex.Message);
                }
            }
        }

        private static void SendUdp(IPEndPoint to, byte[] data)
        {
            UdpClient udp = _udp;
            if (udp == null || to == null || data == null || data.Length == 0)
            {
                return;
            }

            lock (UdpSendLock)
            {
                udp.Send(data, data.Length, to);
            }
        }

        private static void TickKcp()
        {
            uint now = (uint)Environment.TickCount;
            List<Peer> snapshot;
            lock (PeersLock)
            {
                snapshot = new List<Peer>(Peers.Values);
            }

            for (int i = 0; i < snapshot.Count; i++)
            {
                snapshot[i].Tick(now);
            }
        }

        private static void UdpRecvLoop()
        {
            byte[] data;
            IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
            // 固定本次线程负责的 socket：重绑后旧线程必须退出，不能继续读 _udp 上的新 socket。
            UdpClient bound = _udp;
            while (_recvRunning && bound != null && ReferenceEquals(_udp, bound))
            {
                try
                {
                    data = bound.Receive(ref from);
                    if (data == null || data.Length < 1)
                    {
                        continue;
                    }

                    HandleUdpDatagram(data, new IPEndPoint(from.Address, from.Port));
                }
                catch (SocketException)
                {
                    if (!_recvRunning || !ReferenceEquals(_udp, bound))
                    {
                        break;
                    }
                }
                catch (ObjectDisposedException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    if (_recvRunning)
                    {
                        AstralLog.Error("udp recv: " + ex.Message);
                    }
                }
            }
        }

        private static void HandleUdpDatagram(byte[] data, IPEndPoint from)
        {
            byte kind = data[0];
            if (kind == KindHelloV2)
            {
                HandleHelloV2(data, from);
                return;
            }

            if (kind == KindHello)
            {
                HandleHello(data, from);
                return;
            }

            if (kind == KindWelcome)
            {
                // 只接受"正在连接且来源端点就是本次目标"的 WELCOME，
                // 否则同网段任何主机都能抢先返回一个伪造的房主身份。
                if (!_connecting || data.Length < 11)
                {
                    AstralLog.Info("ignore WELCOME from " + from + " (not connecting)");
                    return;
                }

                if (_handshakeTarget == null || from == null || !_handshakeTarget.Equals(from))
                {
                    AstralLog.Info("ignore WELCOME from unexpected endpoint " + from
                        + " expected " + _handshakeTarget);
                    return;
                }

                _handshakeWelcome = data;
                return;
            }

            Peer peer = FindPeerByEndpoint(from);
            if (peer == null)
            {
                return;
            }

            if (kind == KindUnreliable)
            {
                if (data.Length < 3)
                {
                    return;
                }

                int rawChannel = data[1];
                bool relayed = (rawChannel & ChannelRelayFlag) != 0;
                int channel = rawChannel & 0x7F;
                if (!ValidChannel(channel))
                {
                    return;
                }

                byte[] payload = new byte[data.Length - 2];
                Buffer.BlockCopy(data, 2, payload, 0, payload.Length);
                ulong sender = peer.SteamId;
                if (relayed)
                {
                    sender = ReadRelayOrigin(ref payload);
                    if (sender == 0UL)
                    {
                        return;
                    }
                }

                IncomingMessages.Enqueue(new QueuedPacket
                {
                    SteamId = sender,
                    Data = payload,
                    Channel = channel,
                    Unreliable = true,
                    Relayed = relayed
                });
                return;
            }

            if (kind == KindKcp)
            {
                peer.InputKcp(data, 1, data.Length - 1);
            }
        }

        /// <summary>
        /// 旧版 HELLO：名称字段后直接跟明文密码长度 + 密码。
        /// 保留是为了能和新版客户端之外的旧客户端互通，日志里会明确提示升级。
        /// </summary>
        private static void HandleHello(byte[] hello, IPEndPoint from)
        {
            if (!_listening || hello.Length < 11)
            {
                return;
            }

            ulong remoteSteam = BitConverter.ToUInt64(hello, 1);
            CSteamID remoteId = new CSteamID(remoteSteam);
            if (!remoteId.IsValid())
            {
                return;
            }

            ushort nameLen = BitConverter.ToUInt16(hello, 9);
            int passwordOffset = 11 + nameLen;
            string password = string.Empty;
            if (hello.Length >= passwordOffset + 2)
            {
                ushort passwordLen = BitConverter.ToUInt16(hello, passwordOffset);
                if (passwordLen > 0 && hello.Length >= passwordOffset + 2 + passwordLen)
                {
                    password = Encoding.UTF8.GetString(hello, passwordOffset + 2, passwordLen);
                }
            }

            try
            {
                if (GameManager.HasPassword && password != GameManager.Password)
                {
                    AstralLog.Error("bad password from " + remoteSteam);
                    return;
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("legacy hello password check failed from " + remoteSteam + ": " + ex.Message);
                return;
            }

            AcceptPeer(remoteSteam, from, true);
        }

        /// <summary>
        /// 握手 v2：名称字段后是 hasPassword + nonce(16) + proof(32)。
        /// proof = SHA256(nonce || password)，比较使用常量时间。
        /// </summary>
        private static void HandleHelloV2(byte[] hello, IPEndPoint from)
        {
            if (!_listening || hello.Length < 12)
            {
                return;
            }

            if (hello[1] != AstralHandshake.Version2)
            {
                AstralLog.Info("ignore HELLO protocol " + hello[1] + " from " + from);
                return;
            }

            ulong remoteSteam = BitConverter.ToUInt64(hello, 2);
            CSteamID remoteId = new CSteamID(remoteSteam);
            if (!remoteId.IsValid())
            {
                return;
            }

            ushort nameLen = BitConverter.ToUInt16(hello, 10);
            int offset = 12 + nameLen;
            int nonceOffset = offset + 1;
            if (hello.Length < nonceOffset + AstralHandshake.NonceSize)
            {
                return;
            }

            bool clientHasPassword = hello[offset] != 0;
            byte[] nonce = new byte[AstralHandshake.NonceSize];
            Buffer.BlockCopy(hello, nonceOffset, nonce, 0, nonce.Length);

            bool hostHasPassword;
            string hostPassword;
            try
            {
                hostHasPassword = GameManager.HasPassword;
                hostPassword = GameManager.Password ?? string.Empty;
            }
            catch (Exception ex)
            {
                AstralLog.Error("read host password failed, reject hello from " + remoteSteam + ": " + ex.Message);
                return;
            }

            if (hostHasPassword)
            {
                int proofOffset = nonceOffset + AstralHandshake.NonceSize;
                if (!clientHasPassword || hello.Length < proofOffset + AstralHandshake.ProofSize)
                {
                    AstralLog.Error("reject HELLO v2 from " + remoteSteam + ": password required");
                    return;
                }

                byte[] proof = new byte[AstralHandshake.ProofSize];
                Buffer.BlockCopy(hello, proofOffset, proof, 0, proof.Length);
                byte[] expected = AstralHandshake.ComputeProof(nonce, hostPassword);
                if (!AstralHandshake.FixedTimeEquals(proof, expected))
                {
                    AstralLog.Error("bad password proof from " + remoteSteam);
                    return;
                }
            }
            else if (clientHasPassword)
            {
                // 房主没设密码时客户端多发一个证明无害，直接放行。
                AstralLog.Info("hello v2 from " + remoteSteam + " carries password proof but host has none");
            }

            AcceptPeer(remoteSteam, from, false);
        }

        private static void AcceptPeer(ulong remoteSteam, IPEndPoint from, bool legacy)
        {
            ulong localSteam = SteamId;
            if (localSteam == 0UL)
            {
                AstralLog.Error("reject peer " + remoteSteam + ": host has no valid SteamID");
                return;
            }

            string localName = SteamFriends.GetPersonaName() ?? "host";
            lock (PeersLock)
            {
                Peer existing;
                if (Peers.TryGetValue(remoteSteam, out existing) && existing != null)
                {
                    // 同一个 SteamID 不允许从另一个 IP 端点抢走已有的 peer；
                    // 同机切端口（地址相同）则允许更新。
                    if (existing.Remote != null && from != null
                        && !existing.Remote.Address.Equals(from.Address))
                    {
                        AstralLog.Error("reject peer " + remoteSteam + " from " + from
                            + ", already bound to " + existing.Remote);
                        return;
                    }

                    existing.Remote = from;
                    SendUdp(from, BuildWelcome(localSteam, localName));
                    return;
                }
            }

            SendUdp(from, BuildWelcome(localSteam, localName));
            CreatePeer(remoteSteam, from, localSteam);
            AstralLog.Info("peer " + remoteSteam + " from " + from
                + (legacy ? " (legacy hello, cleartext password)" : " (hello v2)"));
        }

        private static void CreatePeer(ulong remoteSteam, IPEndPoint remote, ulong localSteam)
        {
            Peer peer = new Peer(remoteSteam, remote, ConvFor(localSteam, remoteSteam));
            ReplacePeer(remoteSteam, peer);
        }

        private static uint ConvFor(ulong a, ulong b)
        {
            ulong mixed = a ^ b ^ 0xA57A1UL;
            uint conv = (uint)mixed ^ (uint)(mixed >> 32);
            return conv == 0 ? 1u : conv;
        }

        private static Peer FindPeerByEndpoint(IPEndPoint from)
        {
            if (from == null)
            {
                return null;
            }

            lock (PeersLock)
            {
                foreach (KeyValuePair<ulong, Peer> kv in Peers)
                {
                    if (kv.Value != null && kv.Value.Remote != null && kv.Value.Remote.Equals(from))
                    {
                        return kv.Value;
                    }
                }
            }

            return null;
        }

        private static void EnqueueReliablePayload(ulong steamId, int channel, byte[] payload, bool relayed)
        {
            if (!ValidChannel(channel) || payload == null)
            {
                return;
            }

            IncomingMessages.Enqueue(new QueuedPacket
            {
                SteamId = steamId,
                Data = payload,
                Channel = channel,
                Unreliable = false,
                Relayed = relayed
            });
        }

        private static void ReplacePeer(ulong steamId, Peer peer)
        {
            Peer old;
            lock (PeersLock)
            {
                Peers.TryGetValue(steamId, out old);
                Peers[steamId] = peer;
            }

            if (old != null && !ReferenceEquals(old, peer))
            {
                old.Close();
            }
        }

        private static void RemovePeerIfSame(Peer peer)
        {
            if (peer == null)
            {
                return;
            }

            lock (PeersLock)
            {
                Peer current;
                if (!Peers.TryGetValue(peer.SteamId, out current) || !ReferenceEquals(current, peer))
                {
                    return;
                }

                Peers.Remove(peer.SteamId);
            }

            peer.Close();
            AstralLog.Info("peer closed " + peer.SteamId);
        }

        private static void RemovePeer(ulong steamId)
        {
            Peer peer;
            lock (PeersLock)
            {
                if (!Peers.TryGetValue(steamId, out peer))
                {
                    return;
                }

                Peers.Remove(steamId);
            }

            peer.Close();
            AstralLog.Info("peer closed " + steamId);
        }

        private static byte[] BuildHelloV2(CSteamID id, string name, string password)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            bool hasPassword = !string.IsNullOrEmpty(password);
            byte[] nonce = AstralHandshake.NewNonce();
            int offset = 12 + nameBytes.Length;
            int length = offset + 1 + nonce.Length + (hasPassword ? AstralHandshake.ProofSize : 0);
            byte[] body = new byte[length];
            body[0] = KindHelloV2;
            body[1] = AstralHandshake.Version2;
            WriteU64(body, 2, id.m_SteamID);
            WriteU16(body, 10, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 12, nameBytes.Length);
            body[offset] = (byte)(hasPassword ? 1 : 0);
            Buffer.BlockCopy(nonce, 0, body, offset + 1, nonce.Length);
            if (hasPassword)
            {
                byte[] proof = AstralHandshake.ComputeProof(nonce, password);
                Buffer.BlockCopy(proof, 0, body, offset + 1 + nonce.Length, proof.Length);
            }

            return body;
        }

        /// <summary>旧协议，明文密码，只在降级兼容旧房主时使用。</summary>
        private static byte[] BuildLegacyHello(CSteamID id, string name, string password)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            byte[] passwordBytes = Encoding.UTF8.GetBytes(password ?? string.Empty);
            byte[] body = new byte[1 + 8 + 2 + nameBytes.Length + 2 + passwordBytes.Length];
            body[0] = KindHello;
            WriteU64(body, 1, id.m_SteamID);
            WriteU16(body, 9, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 11, nameBytes.Length);
            int offset = 11 + nameBytes.Length;
            WriteU16(body, offset, (ushort)passwordBytes.Length);
            Buffer.BlockCopy(passwordBytes, 0, body, offset + 2, passwordBytes.Length);
            return body;
        }

        private static byte[] BuildWelcome(ulong id, string name)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            byte[] body = new byte[1 + 8 + 2 + nameBytes.Length + 2];
            body[0] = KindWelcome;
            WriteU64(body, 1, id);
            WriteU16(body, 9, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 11, nameBytes.Length);
            int extra = 11 + nameBytes.Length;
            GameMode mode = GameMode.Normal;
            byte flags = 0;
            try
            {
                mode = GameManager.GameMode;
            }
            catch (Exception ex)
            {
                AstralLog.Info("welcome: GameMode unavailable, fallback Normal: " + ex.Message);
            }

            try
            {
                if (GameManager.FriendlyFire)
                {
                    flags |= 1;
                }
            }
            catch (Exception ex)
            {
                AstralLog.Info("welcome: FriendlyFire unavailable, default off: " + ex.Message);
            }

            try
            {
                if (GameManager.Crossplay)
                {
                    flags |= 2;
                }
            }
            catch (Exception ex)
            {
                AstralLog.Info("welcome: Crossplay unavailable, default off: " + ex.Message);
            }

            body[extra] = (byte)mode;
            body[extra + 1] = flags;
            return body;
        }

        private static void WriteU64(byte[] buffer, int offset, ulong value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            Buffer.BlockCopy(bytes, 0, buffer, offset, 8);
        }

        private static void WriteU16(byte[] buffer, int offset, ushort value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            Buffer.BlockCopy(bytes, 0, buffer, offset, 2);
        }

        private static bool ValidChannel(int channel)
        {
            return channel == 0 || channel == 1;
        }

        public static bool TryParseHostPort(string text, out string host, out int port)
        {
            host = null;
            port = DefaultPort;
            if (string.IsNullOrEmpty(text))
            {
                return false;
            }

            text = text.Trim();
            int colon = text.LastIndexOf(':');
            if (colon > 0 && colon < text.Length - 1)
            {
                host = text.Substring(0, colon).Trim();
                return int.TryParse(text.Substring(colon + 1), out port) && port > 0 && port < 65536 && host.Length > 0;
            }

            host = text;
            return host.Length > 0;
        }

        private struct QueuedPacket
        {
            public ulong SteamId;
            public byte[] Data;
            public int Channel;
            public bool Unreliable;
            public bool Relayed;
        }

        private struct PendingMessage
        {
            public ulong SteamId;
            public Message Message;
            public byte[] Raw;
            public int Channel;
            public bool Unreliable;
            public bool Relayed;
        }

        private sealed class Peer
        {
            private readonly object _kcpLock = new object();
            private readonly Kcp _kcp;
            private readonly MemoryStream _reliable = new MemoryStream();
            private readonly byte[] _recvScratch = new byte[MaxKcpMessage];

            public Peer(ulong steamId, IPEndPoint remote, uint conv)
            {
                SteamId = steamId;
                Remote = remote;
                _kcp = new Kcp(conv, Output);
                _kcp.SetNoDelay(1, 10, 2, true);
                _kcp.SetWindowSize(512, 512);
            }

            public ulong SteamId { get; private set; }
            public IPEndPoint Remote { get; set; }

            private void Output(byte[] data, int size)
            {
                byte[] packet = new byte[1 + size];
                packet[0] = KindKcp;
                Buffer.BlockCopy(data, 0, packet, 1, size);
                SendUdp(Remote, packet);
            }

            public void SendUnreliable(byte channel, byte[] payload)
            {
                byte[] packet = new byte[2 + payload.Length];
                packet[0] = KindUnreliable;
                packet[1] = channel;
                Buffer.BlockCopy(payload, 0, packet, 2, payload.Length);
                SendUdp(Remote, packet);
            }

            public void SendReliable(byte channel, byte[] payload)
            {
                byte[] frame = new byte[5 + payload.Length];
                byte[] len = BitConverter.GetBytes(payload.Length);
                Buffer.BlockCopy(len, 0, frame, 0, 4);
                frame[4] = channel;
                Buffer.BlockCopy(payload, 0, frame, 5, payload.Length);
                lock (_kcpLock)
                {
                    int offset = 0;
                    uint now = (uint)Environment.TickCount;
                    while (offset < frame.Length)
                    {
                        int n = Math.Min(MaxKcpMessage, frame.Length - offset);
                        int spins = 0;
                        int sent;
                        while (true)
                        {
                            sent = _kcp.Send(frame, offset, n);
                            if (sent == 0)
                            {
                                break;
                            }

                            if (sent == -2 && spins++ < 2000)
                            {
                                _kcp.Flush();
                                now = (uint)Environment.TickCount;
                                _kcp.Update(now);
                                Monitor.Wait(_kcpLock, 4);
                                continue;
                            }

                            throw new IOException("kcp send " + sent);
                        }

                        offset += n;
                    }

                    _kcp.Flush();
                }
            }

            public void InputKcp(byte[] data, int offset, int size)
            {
                lock (_kcpLock)
                {
                    _kcp.Input(data, offset, size);
                    DrainUnlocked();
                    _kcp.Flush();
                }
            }

            public void Tick(uint now)
            {
                lock (_kcpLock)
                {
                    _kcp.Update(now);
                    DrainUnlocked();
                }
            }

            private void DrainUnlocked()
            {
                while (true)
                {
                    int peek = _kcp.PeekSize();
                    if (peek < 0)
                    {
                        break;
                    }

                    if (peek > _recvScratch.Length)
                    {
                        AstralLog.Error("kcp peek too large " + peek);
                        break;
                    }

                    int n = _kcp.Receive(_recvScratch, peek);
                    if (n <= 0)
                    {
                        break;
                    }

                    _reliable.Write(_recvScratch, 0, n);
                    ExtractUnlocked();
                }
            }

            private void ExtractUnlocked()
            {
                byte[] buf = _reliable.GetBuffer();
                int length = (int)_reliable.Length;
                int pos = 0;
                while (length - pos >= 5)
                {
                    int payloadLen = BitConverter.ToInt32(buf, pos);
                    if (payloadLen < 0 || payloadLen > MaxPacket)
                    {
                        _reliable.SetLength(0);
                        return;
                    }

                    if (length - pos < 5 + payloadLen)
                    {
                        break;
                    }

                    int rawChannel = buf[pos + 4];
                    bool relayed = (rawChannel & ChannelRelayFlag) != 0;
                    int channel = rawChannel & 0x7F;
                    byte[] payload = new byte[payloadLen];
                    Buffer.BlockCopy(buf, pos + 5, payload, 0, payloadLen);
                    ulong sender = SteamId;
                    if (relayed)
                    {
                        sender = ReadRelayOrigin(ref payload);
                        if (sender == 0UL)
                        {
                            pos += 5 + payloadLen;
                            continue;
                        }
                    }

                    EnqueueReliablePayload(sender, channel, payload, relayed);
                    pos += 5 + payloadLen;
                }

                if (pos <= 0)
                {
                    return;
                }

                int remain = length - pos;
                if (remain > 0)
                {
                    Buffer.BlockCopy(buf, pos, buf, 0, remain);
                }

                _reliable.SetLength(remain);
                _reliable.Position = remain;
            }

            public void Close()
            {
            }
        }
    }
}
