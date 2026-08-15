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
        private static FieldInfo _localSteamField;
        private static ulong _boundSteamId;
        private static Raft_Network _cachedNetwork;
        private static bool _worldInitDone;

        private static readonly Dictionary<ulong, Peer> Peers = new Dictionary<ulong, Peer>();
        private static readonly object PeersLock = new object();

        private static UdpClient _udp;
        private static readonly object UdpSendLock = new object();
        private static Thread _recvThread;
        private static volatile bool _recvRunning;
        private static volatile bool _listening;
        private static byte[] _handshakeWelcome;
        private static IPEndPoint _handshakeFrom;
        private static int _listenPort = DefaultPort;
        private static string _status = "idle";
        private static volatile bool _connecting;
        private static ulong _joinHostSteam;
        private static bool _sceneLoadStarted;
        private static bool _astralWorldReceived;
        private static float _lastWorldRequest;
        private static float _lastLandmarkWaitLog;

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

        public static bool IsActive
        {
            get { return AstralSettings.EnableLan || _listening || IsJoining || PeerCount > 0; }
        }

        public static void ClearJoinState()
        {
            _connecting = false;
            _joinHostSteam = 0UL;
            _sceneLoadStarted = false;
            _astralWorldReceived = false;
            _worldInitDone = false;
            _cachedNetwork = null;
            _boundSteamId = 0UL;
            _lastWorldRequest = 0f;
            _lastLandmarkWaitLog = 0f;
        }

        public static void BindLocalSteamId(Raft_Network network = null)
        {
            if (!IsActive)
            {
                return;
            }

            try
            {
                CSteamID steam = SteamUser.GetSteamID();
                if (!steam.IsValid())
                {
                    return;
                }

                if (_boundSteamId == steam.m_SteamID && _cachedNetwork != null)
                {
                    return;
                }

                if (network == null)
                {
                    network = GetNetwork();
                }

                if (network == null)
                {
                    return;
                }

                if (_localSteamField == null)
                {
                    _localSteamField = AccessTools.Field(typeof(Raft_Network), "localSteamID");
                }

                Network_UserId id = new Network_UserId(steam.m_SteamID);
                Network_UserId current = (Network_UserId)_localSteamField.GetValue(network);
                _boundSteamId = steam.m_SteamID;
                _cachedNetwork = network;
                if (current.Id == id.Id)
                {
                    return;
                }

                _localSteamField.SetValue(network, id);
                AstralLog.Info("bind localSteamID steam=" + steam.m_SteamID + " was=" + current.Id);
            }
            catch (Exception ex)
            {
                AstralLog.Error("bind localSteamID: " + ex.Message);
            }
        }

        private static void TickWorldInit()
        {
            if (_worldInitDone)
            {
                return;
            }

            BindLocalSteamId(null);
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

                BindLocalSteamId(network);
                object running = AccessTools.Field(typeof(Raft_Network), "worldLoadedCoroutine").GetValue(network);
                if (running == null)
                {
                    MethodInfo method = AccessTools.Method(typeof(Raft_Network), "WorldHasBeenLoaded");
                    IEnumerator routine = method.Invoke(network, null) as IEnumerator;
                    if (routine != null)
                    {
                        Coroutine started = network.StartCoroutine(routine);
                        AccessTools.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, started);
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
            while (IncomingMessages.TryDequeue(out packet))
            {
                try
                {
                    Message message = AstralMessages.Deserialize(packet.Data);
                    if (message == null)
                    {
                        AstralLog.Error("deserialize failed bytes=" + packet.Data.Length + " from=" + packet.SteamId);
                        continue;
                    }

                    Pending.Enqueue(new PendingMessage
                    {
                        SteamId = packet.SteamId,
                        Message = message
                    });
                }
                catch (Exception ex)
                {
                    AstralLog.Error("deliver: " + ex.Message);
                }
            }

            if (Pending.Count == 0)
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
                _parseRemote = AccessTools.Method(typeof(Raft_Network), "ParseRemoteMessage");
                _parseRemoteInvoke = MethodInvoker.GetHandler(_parseRemote);
            }

            // 原版 PlayFab 回调里会把当前收到的包全部处理完。进房后若每帧只吃几十条，
            // 玩家位移/木筏同步会越积越多，体感就是卡顿掉帧。
            int applied = 0;
            while (Pending.Count > 0)
            {
                applied += ApplyPending(network, Pending.Dequeue());
            }

            if (applied > 200)
            {
                AstralLog.Info("applied " + applied + " net messages this frame");
            }
        }

        private static int ApplyPending(Raft_Network network, PendingMessage item)
        {
            if (item.Message != null && item.Message.Type == Messages.Compound)
            {
                Message_Compound compound = item.Message as Message_Compound;
                if (compound == null || compound.messages == null)
                {
                    AstralLog.Error("compound empty from=" + item.SteamId);
                    return 0;
                }

                AstralLog.Info("expand Compound children=" + compound.messages.Count + " from=" + item.SteamId);
                int applied = 0;
                for (int i = 0; i < compound.messages.Count; i++)
                {
                    applied += ApplyPending(network, new PendingMessage
                    {
                        SteamId = item.SteamId,
                        Message = compound.messages[i]
                    });
                }

                return applied;
            }

            try
            {
                object fake;
                if (!FakePlayers.TryGetValue(item.SteamId, out fake) || fake == null)
                {
                    fake = AstralMessages.FakePlayer(item.SteamId);
                    FakePlayers[item.SteamId] = fake;
                }

                if (item.Message != null && ShouldLog(item.Message.Type))
                {
                    AstralLog.Info("recv " + item.Message.Type + " from=" + item.SteamId + " left=" + Pending.Count);
                }

                if (item.Message != null && item.Message.Type == Messages.CreatePlayer)
                {
                    Message_Player_Create create = item.Message as Message_Player_Create;
                    if (create != null)
                    {
                        AstralLog.Info("recv CreatePlayer user=" + create.UserId.Id + " local=" + network.LocalSteamID.Id);
                    }
                }

                ParseArgs[0] = item.Message;
                ParseArgs[1] = fake;
                _parseRemoteInvoke(network, ParseArgs);
                ParseArgs[0] = null;
                ParseArgs[1] = null;

                if (item.Message != null && item.Message.Type == Messages.WorldReceived)
                {
                    _astralWorldReceived = true;
                    _status = "world received peers=" + PeerCount;
                    AstralLog.Info("world snapshot applied, localPlayer=" + (network.GetLocalPlayer() != null));
                    SnapLocalPlayerToBed(network);
                }

                return 1;
            }
            catch (TargetInvocationException ex)
            {
                Exception inner = ex.InnerException ?? ex;
                AstralLog.Error("parse " + (item.Message != null ? item.Message.Type.ToString() : "?") + ": " + inner);
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
                FieldInfo bedField = AccessTools.Field(typeof(Raft_Network), "bedRespawnPoint");
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
                    FieldInfo controllerField = AccessTools.Field(typeof(PersonController), "controller");
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
                EnsureSocket(Port);
                _listening = true;
                _status = "listen udp 0.0.0.0:" + Port;
                BindLocalSteamId(null);
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
            string name = "Astral";
            try
            {
                name = SteamFriends.GetPersonaName() ?? name;
                if (!string.IsNullOrEmpty(SaveAndLoad.CurrentGameFileName))
                {
                    name = name + " · " + SaveAndLoad.CurrentGameFileName;
                }
            }
            catch
            {
            }

            bool password = false;
            try
            {
                password = GameManager.HasPassword;
            }
            catch
            {
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

        public static bool IsPeer(CSteamID steamId)
        {
            return steamId.IsValid() && IsPeer(steamId.m_SteamID);
        }

        public static bool IsPeer(ulong steamId)
        {
            if (steamId == 0UL)
            {
                return false;
            }

            lock (PeersLock)
            {
                return Peers.ContainsKey(steamId);
            }
        }

        public static bool TryPeek(int channel, out uint size)
        {
            QueuedPacket packet;
            if (!ValidChannel(channel) || !Incoming[channel].TryPeek(out packet))
            {
                size = 0;
                return false;
            }

            size = (uint)packet.Data.Length;
            return true;
        }

        public static bool TryRead(int channel, byte[] dest, uint destSize, out uint size, out CSteamID steamId)
        {
            QueuedPacket packet;
            if (!ValidChannel(channel) || !Incoming[channel].TryDequeue(out packet))
            {
                size = 0;
                steamId = new CSteamID(0UL);
                return false;
            }

            int copy = Math.Min(packet.Data.Length, (int)destSize);
            Buffer.BlockCopy(packet.Data, 0, dest, 0, copy);
            size = (uint)packet.Data.Length;
            steamId = new CSteamID(packet.SteamId);
            return true;
        }

        public static bool TrySend(CSteamID steamId, byte[] data, uint cubData, int channel, EP2PSend eP2PSendType)
        {
            if (!steamId.IsValid() || !ValidChannel(channel) || data == null)
            {
                return false;
            }

            int length = (int)Math.Min(cubData, (uint)data.Length);
            byte[] payload = new byte[length];
            Buffer.BlockCopy(data, 0, payload, 0, length);
            return TrySendRaw(steamId.m_SteamID, payload, channel, IsUnreliable(eP2PSendType));
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

            AstralSettings.EnableLan = true;
            _connecting = true;
            _status = "connecting " + host + ":" + port;
            StopConnectingBox();
            ThreadPool.QueueUserWorkItem(_ => ConnectWorker(host, port, password ?? string.Empty));
        }

        private static void ConnectWorker(string host, int port, string password)
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
                CSteamID localId = SteamUser.GetSteamID();
                string localName = SteamFriends.GetPersonaName() ?? "player";
                byte[] hello = BuildHello(localId, localName, password);
                _handshakeWelcome = null;
                _handshakeFrom = null;

                for (int attempt = 0; attempt < 20 && _handshakeWelcome == null; attempt++)
                {
                    SendUdp(hostEp, hello);
                    for (int wait = 0; wait < 16 && _handshakeWelcome == null; wait++)
                    {
                        Thread.Sleep(25);
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

                IPEndPoint remote = _handshakeFrom ?? hostEp;
                CreatePeer(hostSteam, remote, localId.m_SteamID);

                _joinHostSteam = hostSteam;
                _connecting = false;
                _status = "connected " + host + ":" + port + " peers=" + PeerCount;
                AstralLog.Info("handshake ok udp/kcp, host=" + hostSteam + " local=" + localId.m_SteamID + " mode=" + hostMode);
                MainThread.Enqueue(() => JoinHost(hostId, password, hostMode, friendlyFire, crossplay));
            }
            catch (Exception ex)
            {
                _connecting = false;
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

            BindLocalSteamId(network);
            ApplyHostGameMode(hostMode, friendlyFire, crossplay);

            CSteamID localId = SteamUser.GetSteamID();
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
                AccessTools.Field(typeof(Raft_Network), "worldRequestedCoroutine").SetValue(network, null);
                AccessTools.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, null);
                TryRequestWorldAsClient();
                _status = "reconnected " + hostId.m_SteamID;
                return;
            }

            GameManager.Password = password ?? string.Empty;
            AccessTools.Field(typeof(Raft_Network), "isHost").SetValue(null, false);
            AccessTools.Field(typeof(Raft_Network), "connectedToHost").SetValue(network, true);
            AccessTools.Field(typeof(Raft_Network), "hostID").SetValue(network, new Network_UserId(hostId.m_SteamID));
            AccessTools.Field(typeof(Raft_Network), "m_currentSteamHost").SetValue(network, hostId);
            AccessTools.Field(typeof(Raft_Network), "gameManagerStartCalled").SetValue(network, false);
            AccessTools.Field(typeof(Raft_Network), "worldLoadedCoroutine").SetValue(network, null);
            AccessTools.Field(typeof(Raft_Network), "worldRequestedCoroutine").SetValue(network, null);
            _sceneLoadStarted = true;
            AccessTools.Method(typeof(Raft_Network), "LoadScene").Invoke(network, new object[] { Raft_Network.GameSceneName });
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
                // 以前直接调 Platform_RequestWorldAsClient，地标未就绪就要世界 → 第一次卡死，
                // 第二次场景/地标已热 → 立刻成功。
                FieldInfo coroField = AccessTools.Field(typeof(Raft_Network), "worldRequestedCoroutine");
                object running = coroField != null ? coroField.GetValue(network) : null;
                if (running != null)
                {
                    return;
                }

                if (!LoadSceneManager.IsGameSceneLoaded || LoadSceneManager.IsLoadingScene)
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
                MethodInfo method = AccessTools.Method(typeof(Raft_Network), "RequestWorldAsClient");
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
            catch
            {
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
            if (_udp != null)
            {
                return;
            }

            IPEndPoint local = new IPEndPoint(IPAddress.Any, bindPort < 0 ? 0 : bindPort);
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
                catch
                {
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
            while (_recvRunning)
            {
                try
                {
                    UdpClient udp = _udp;
                    if (udp == null)
                    {
                        break;
                    }

                    data = udp.Receive(ref from);
                    if (data == null || data.Length < 1)
                    {
                        continue;
                    }

                    HandleUdpDatagram(data, new IPEndPoint(from.Address, from.Port));
                }
                catch (SocketException)
                {
                    if (!_recvRunning)
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
            if (kind == KindHello)
            {
                HandleHello(data, from);
                return;
            }

            if (kind == KindWelcome)
            {
                _handshakeFrom = from;
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

                int channel = data[1];
                if (!ValidChannel(channel))
                {
                    return;
                }

                byte[] payload = new byte[data.Length - 2];
                Buffer.BlockCopy(data, 2, payload, 0, payload.Length);
                IncomingMessages.Enqueue(new QueuedPacket
                {
                    SteamId = peer.SteamId,
                    Data = payload
                });
                return;
            }

            if (kind == KindKcp)
            {
                peer.InputKcp(data, 1, data.Length - 1);
            }
        }

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
            catch
            {
            }

            CSteamID localId = SteamUser.GetSteamID();
            string localName = SteamFriends.GetPersonaName() ?? "host";
            lock (PeersLock)
            {
                Peer existing;
                if (Peers.TryGetValue(remoteSteam, out existing) && existing != null)
                {
                    existing.Remote = from;
                    SendUdp(from, BuildWelcome(localId, localName));
                    return;
                }
            }

            SendUdp(from, BuildWelcome(localId, localName));
            CreatePeer(remoteSteam, from, localId.m_SteamID);
            AstralLog.Info("peer " + remoteSteam + " from " + from);
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

        private static void EnqueueReliablePayload(ulong steamId, int channel, byte[] payload)
        {
            if (!ValidChannel(channel) || payload == null)
            {
                return;
            }

            IncomingMessages.Enqueue(new QueuedPacket
            {
                SteamId = steamId,
                Data = payload
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

        private static byte[] BuildHello(CSteamID id, string name, string password)
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

        private static byte[] BuildWelcome(CSteamID id, string name)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            byte[] body = new byte[1 + 8 + 2 + nameBytes.Length + 2];
            body[0] = KindWelcome;
            WriteU64(body, 1, id.m_SteamID);
            WriteU16(body, 9, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 11, nameBytes.Length);
            int extra = 11 + nameBytes.Length;
            GameMode mode = GameMode.Normal;
            byte flags = 0;
            try
            {
                mode = GameManager.GameMode;
            }
            catch
            {
            }

            try
            {
                if (GameManager.FriendlyFire)
                {
                    flags |= 1;
                }
            }
            catch
            {
            }

            try
            {
                if (GameManager.Crossplay)
                {
                    flags |= 2;
                }
            }
            catch
            {
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
        }

        private struct PendingMessage
        {
            public ulong SteamId;
            public Message Message;
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

                    int channel = buf[pos + 4];
                    byte[] payload = new byte[payloadLen];
                    Buffer.BlockCopy(buf, pos + 5, payload, 0, payloadLen);
                    EnqueueReliablePayload(SteamId, channel, payload);
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
