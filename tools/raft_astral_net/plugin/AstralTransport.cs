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
using Steamworks;
using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralTransport
    {
        public const int DefaultPort = 6488;
        private const int MaxPacket = 64 * 1024 * 1024;
        private const byte KindHello = 1;
        private const byte KindWelcome = 2;
        private const byte KindData = 3;

        private static readonly ConcurrentQueue<Action> MainThread = new ConcurrentQueue<Action>();
        private static readonly ConcurrentQueue<QueuedPacket>[] Incoming =
        {
            new ConcurrentQueue<QueuedPacket>(),
            new ConcurrentQueue<QueuedPacket>()
        };
        private static readonly ConcurrentQueue<QueuedPacket> IncomingMessages = new ConcurrentQueue<QueuedPacket>();
        private static readonly List<PendingMessage> Pending = new List<PendingMessage>();
        private static readonly Dictionary<ulong, object> FakePlayers = new Dictionary<ulong, object>();
        private static MethodInfo _parseRemote;
        private static float _lastQueueLog;
        private const int MaxDeliverPerFrame = 80;

        private static readonly Dictionary<ulong, Peer> Peers = new Dictionary<ulong, Peer>();
        private static readonly object PeersLock = new object();

        private static TcpListener _listener;
        private static Thread _listenThread;
        private static volatile bool _listening;
        private static int _listenPort = DefaultPort;
        private static string _status = "idle";
        private static volatile bool _connecting;
        private static ulong _joinHostSteam;
        private static bool _sceneLoadStarted;
        private static bool _astralWorldReceived;

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

            DeliverMessages();
            TickWorldInit();
        }

        public static bool IsJoining
        {
            get { return _connecting || _joinHostSteam != 0UL || _sceneLoadStarted; }
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

                if (network == null)
                {
                    network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
                }

                if (network == null)
                {
                    return;
                }

                FieldInfo field = AccessTools.Field(typeof(Raft_Network), "localSteamID");
                Network_UserId id = new Network_UserId(steam.m_SteamID);
                Network_UserId current = (Network_UserId)field.GetValue(network);
                if (current.Id == id.Id)
                {
                    return;
                }

                field.SetValue(network, id);
                AstralLog.Info("bind localSteamID steam=" + steam.m_SteamID + " was=" + current.Id);
            }
            catch (Exception ex)
            {
                AstralLog.Error("bind localSteamID: " + ex.Message);
            }
        }

        private static void TickWorldInit()
        {
            BindLocalSteamId(null);
            if (!_astralWorldReceived)
            {
                return;
            }

            try
            {
                Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
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

                    Pending.Add(new PendingMessage
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

            Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
            if (network == null)
            {
                return;
            }

            if (_parseRemote == null)
            {
                _parseRemote = AccessTools.Method(typeof(Raft_Network), "ParseRemoteMessage");
            }

            int applied = 0;
            while (Pending.Count > 0 && applied < MaxDeliverPerFrame)
            {
                PendingMessage item = Pending[0];
                Pending.RemoveAt(0);
                if (item.Message != null && item.Message.Type == Messages.Compound)
                {
                    Message_Compound compound = item.Message as Message_Compound;
                    if (compound == null || compound.messages == null)
                    {
                        AstralLog.Error("compound empty from=" + item.SteamId);
                        continue;
                    }

                    AstralLog.Info("expand Compound children=" + compound.messages.Count + " from=" + item.SteamId);
                    List<PendingMessage> children = new List<PendingMessage>(compound.messages.Count);
                    for (int i = 0; i < compound.messages.Count; i++)
                    {
                        children.Add(new PendingMessage
                        {
                            SteamId = item.SteamId,
                            Message = compound.messages[i]
                        });
                    }

                    Pending.InsertRange(0, children);
                    continue;
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

                    _parseRemote.Invoke(network, new object[] { item.Message, fake });

                    if (item.Message != null && item.Message.Type == Messages.WorldReceived)
                    {
                        _astralWorldReceived = true;
                        _status = "world received peers=" + PeerCount;
                        AstralLog.Info("world snapshot applied, localPlayer=" + (network.GetLocalPlayer() != null));
                    }
                }
                catch (TargetInvocationException ex)
                {
                    Exception inner = ex.InnerException ?? ex;
                    AstralLog.Error("parse " + (item.Message != null ? item.Message.Type.ToString() : "?") + ": " + inner);
                }
                catch (Exception ex)
                {
                    AstralLog.Error("parse: " + ex.Message);
                }

                applied++;
            }

            if (Pending.Count > 0 && Time.realtimeSinceStartup - _lastQueueLog > 1f)
            {
                _lastQueueLog = Time.realtimeSinceStartup;
                AstralLog.Info("world apply remaining=" + Pending.Count);
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
                _listener = new TcpListener(IPAddress.Any, Port);
                _listener.Start();
                _listening = true;
                _status = "listen 0.0.0.0:" + Port;
                _listenThread = new Thread(AcceptLoop)
                {
                    IsBackground = true,
                    Name = "AstralRaftListen"
                };
                _listenThread.Start();
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
            try
            {
                if (_listener != null)
                {
                    _listener.Stop();
                }
            }
            catch
            {
            }

            _listener = null;
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

        public static bool TrySend(CSteamID steamId, byte[] data, uint cubData, int channel)
        {
            if (!steamId.IsValid() || !ValidChannel(channel) || data == null)
            {
                return false;
            }

            int length = (int)Math.Min(cubData, (uint)data.Length);
            byte[] payload = new byte[length];
            Buffer.BlockCopy(data, 0, payload, 0, length);
            return TrySendRaw(steamId.m_SteamID, payload, channel);
        }

        public static bool TrySendMessage(ulong steamId, Message message, int channel)
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
                if (ShouldLog(message.Type) || payload.Length >= 100000)
                {
                    AstralLog.Info("send " + message.Type + " to=" + steamId + " bytes=" + payload.Length);
                }

                return TrySendRaw(steamId, payload, channel);
            }
            catch (Exception ex)
            {
                AstralLog.Error("serialize failed " + message.Type + ": " + ex.Message);
                return false;
            }
        }

        public static bool TrySendMessageOrHost(ulong steamId, Message message, int channel)
        {
            if (TrySendMessage(steamId, message, channel))
            {
                return true;
            }

            if (_joinHostSteam != 0UL && steamId != _joinHostSteam && TrySendMessage(_joinHostSteam, message, channel))
            {
                AstralLog.Info("send remap to host steam type=" + message.Type + " from=" + steamId);
                return true;
            }

            return false;
        }

        public static void BroadcastMessage(Message message, int channel, ulong excludeSteamId)
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

                TrySendMessage(ids[i], message, channel);
            }
        }

        private static bool TrySendRaw(ulong steamId, byte[] payload, int channel)
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

            byte[] body = new byte[2 + payload.Length];
            body[0] = KindData;
            body[1] = (byte)channel;
            Buffer.BlockCopy(payload, 0, body, 2, payload.Length);
            try
            {
                peer.Send(body);
                return true;
            }
            catch (Exception ex)
            {
                AstralLog.Error("send failed: " + ex.Message);
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
            ThreadPool.QueueUserWorkItem(_ => ConnectWorker(host, port, password ?? string.Empty));
        }

        private static void ConnectWorker(string host, int port, string password)
        {
            try
            {
                TcpClient client = new TcpClient();
                client.NoDelay = true;
                IAsyncResult ar = client.BeginConnect(host, port, null, null);
                if (!ar.AsyncWaitHandle.WaitOne(TimeSpan.FromSeconds(8)) || !client.Connected)
                {
                    client.Close();
                    throw new TimeoutException("connect timeout");
                }

                client.EndConnect(ar);
                NetworkStream stream = client.GetStream();
                stream.ReadTimeout = 15000;
                stream.WriteTimeout = Timeout.Infinite;

                CSteamID localId = SteamUser.GetSteamID();
                string localName = SteamFriends.GetPersonaName() ?? "player";
                WriteFrame(stream, BuildHello(localId, localName, password));

                byte[] welcome = ReadFrame(stream);
                if (welcome == null || welcome.Length < 11 || welcome[0] != KindWelcome)
                {
                    throw new IOException("bad welcome");
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

                stream.ReadTimeout = Timeout.Infinite;
                Peer peer = new Peer(client, stream, hostSteam);
                ReplacePeer(hostSteam, peer);

                Thread recv = new Thread(() => RecvLoop(peer))
                {
                    IsBackground = true,
                    Name = "AstralRaftRecv"
                };
                recv.Start();

                _joinHostSteam = hostSteam;
                _connecting = false;
                _status = "connected " + host + ":" + port + " peers=" + PeerCount;
                AstralLog.Info("handshake ok, host=" + hostSteam + " local=" + localId.m_SteamID + " mode=" + hostMode);
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

            Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
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
                AstralLog.Info("tcp ready, skip duplicate LoadScene host=" + hostId.m_SteamID);
                if (!_astralWorldReceived && !Raft_Network.WorldHasBeenRecieved)
                {
                    try
                    {
                        AccessTools.Method(typeof(Raft_Network), "Platform_RequestWorldAsClient").Invoke(network, null);
                        AstralLog.Info("re-request world after tcp reconnect");
                    }
                    catch (Exception ex)
                    {
                        AstralLog.Error("re-request world: " + ex.Message);
                    }
                }

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
            _sceneLoadStarted = true;
            AccessTools.Method(typeof(Raft_Network), "LoadScene").Invoke(network, new object[] { Raft_Network.GameSceneName });
            _status = "joining " + hostId.m_SteamID;
            AstralLog.Info("Astral join load scene host=" + hostId.m_SteamID + " localSteam=" + network.LocalSteamID.Id + " mode=" + GameManager.GameMode);
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

        private static void AcceptLoop()
        {
            while (_listening && _listener != null)
            {
                try
                {
                    TcpClient client = _listener.AcceptTcpClient();
                    client.NoDelay = true;
                    ThreadPool.QueueUserWorkItem(_ => HandleIncoming(client));
                }
                catch (SocketException)
                {
                    if (!_listening)
                    {
                        break;
                    }
                }
                catch (Exception ex)
                {
                    if (_listening)
                    {
                        AstralLog.Error("accept: " + ex.Message);
                    }
                }
            }
        }

        private static void HandleIncoming(TcpClient client)
        {
            try
            {
                NetworkStream stream = client.GetStream();
                stream.ReadTimeout = 15000;
                stream.WriteTimeout = Timeout.Infinite;
                byte[] hello = ReadFrame(stream);
                if (hello == null || hello.Length < 11 || hello[0] != KindHello)
                {
                    client.Close();
                    return;
                }

                ulong remoteSteam = BitConverter.ToUInt64(hello, 1);
                CSteamID remoteId = new CSteamID(remoteSteam);
                if (!remoteId.IsValid())
                {
                    client.Close();
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

                if (GameManager.HasPassword && password != GameManager.Password)
                {
                    AstralLog.Error("bad password from " + remoteSteam);
                    client.Close();
                    return;
                }

                CSteamID localId = SteamUser.GetSteamID();
                string localName = SteamFriends.GetPersonaName() ?? "host";
                WriteFrame(stream, BuildWelcome(localId, localName));
                stream.ReadTimeout = Timeout.Infinite;

                Peer peer = new Peer(client, stream, remoteSteam);
                ReplacePeer(remoteSteam, peer);

                AstralLog.Info("peer " + remoteSteam + " from " + client.Client.RemoteEndPoint);
                RecvLoop(peer);
            }
            catch (Exception ex)
            {
                AstralLog.Error("incoming: " + ex.Message);
                try
                {
                    client.Close();
                }
                catch
                {
                }
            }
        }

        private static void RecvLoop(Peer peer)
        {
            try
            {
                while (true)
                {
                    byte[] frame = ReadFrame(peer.Stream);
                    if (frame == null || frame.Length < 2 || frame[0] != KindData)
                    {
                        continue;
                    }

                    int channel = frame[1];
                    if (!ValidChannel(channel))
                    {
                        continue;
                    }

                    byte[] payload = new byte[frame.Length - 2];
                    Buffer.BlockCopy(frame, 2, payload, 0, payload.Length);
                    QueuedPacket packet = new QueuedPacket
                    {
                        SteamId = peer.SteamId,
                        Data = payload
                    };
                    Incoming[channel].Enqueue(packet);
                    IncomingMessages.Enqueue(packet);
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("recv closed " + peer.SteamId + ": " + ex.Message);
            }
            finally
            {
                RemovePeerIfSame(peer);
            }
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

        private static void WriteFrame(Stream stream, byte[] body)
        {
            byte[] header = BitConverter.GetBytes(body.Length);
            stream.Write(header, 0, 4);
            stream.Write(body, 0, body.Length);
            stream.Flush();
        }

        private static byte[] ReadFrame(Stream stream)
        {
            byte[] header = ReadExact(stream, 4);
            int length = BitConverter.ToInt32(header, 0);
            if (length <= 0 || length > MaxPacket)
            {
                throw new IOException("bad frame length " + length);
            }

            return ReadExact(stream, length);
        }

        private static byte[] ReadExact(Stream stream, int size)
        {
            byte[] buffer = new byte[size];
            int offset = 0;
            while (offset < size)
            {
                int read = stream.Read(buffer, offset, size - offset);
                if (read <= 0)
                {
                    throw new EndOfStreamException();
                }

                offset += read;
            }

            return buffer;
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
            private readonly object _sendLock = new object();

            public Peer(TcpClient client, NetworkStream stream, ulong steamId)
            {
                Client = client;
                Stream = stream;
                SteamId = steamId;
            }

            public TcpClient Client { get; private set; }
            public NetworkStream Stream { get; private set; }
            public ulong SteamId { get; private set; }

            public void Send(byte[] body)
            {
                lock (_sendLock)
                {
                    WriteFrame(Stream, body);
                }
            }

            public void Close()
            {
                try
                {
                    Client.Close();
                }
                catch
                {
                }
            }
        }
    }
}
