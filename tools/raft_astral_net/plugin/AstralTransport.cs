using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Steamworks;
using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralTransport
    {
        public const int DefaultPort = 6488;
        private const int MaxPacket = 4 * 1024 * 1024;
        private const byte KindHello = 1;
        private const byte KindWelcome = 2;
        private const byte KindData = 3;

        private static readonly ConcurrentQueue<Action> MainThread = new ConcurrentQueue<Action>();
        private static readonly ConcurrentQueue<QueuedPacket>[] Incoming =
        {
            new ConcurrentQueue<QueuedPacket>(),
            new ConcurrentQueue<QueuedPacket>()
        };

        private static readonly Dictionary<ulong, Peer> Peers = new Dictionary<ulong, Peer>();
        private static readonly object PeersLock = new object();

        private static TcpListener _listener;
        private static Thread _listenThread;
        private static volatile bool _listening;
        private static int _listenPort = DefaultPort;
        private static string _status = "idle";

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

            _status = "idle";
        }

        public static bool IsPeer(CSteamID steamId)
        {
            if (!steamId.IsValid())
            {
                return false;
            }

            lock (PeersLock)
            {
                return Peers.ContainsKey(steamId.m_SteamID);
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

            Peer peer;
            lock (PeersLock)
            {
                if (!Peers.TryGetValue(steamId.m_SteamID, out peer))
                {
                    return false;
                }
            }

            int length = (int)Math.Min(cubData, (uint)data.Length);
            byte[] body = new byte[2 + length];
            body[0] = KindData;
            body[1] = (byte)channel;
            Buffer.BlockCopy(data, 0, body, 2, length);
            try
            {
                peer.Send(body);
                return true;
            }
            catch (Exception ex)
            {
                AstralLog.Error("send failed: " + ex.Message);
                RemovePeer(steamId.m_SteamID);
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
                WriteFrame(stream, BuildHello(localId, localName));

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

                stream.ReadTimeout = Timeout.Infinite;
                Peer peer = new Peer(client, stream, hostSteam);
                lock (PeersLock)
                {
                    Peers[hostSteam] = peer;
                }

                Thread recv = new Thread(() => RecvLoop(peer))
                {
                    IsBackground = true,
                    Name = "AstralRaftRecv"
                };
                recv.Start();

                _status = "connected " + host + ":" + port + " peers=" + PeerCount;
                AstralLog.Info("handshake ok, host=" + hostSteam + " local=" + localId.m_SteamID);
                MainThread.Enqueue(() => JoinHost(hostId, password));
            }
            catch (Exception ex)
            {
                _status = "connect failed";
                AstralLog.Error("connect failed: " + ex.Message);
            }
        }

        private static void JoinHost(CSteamID hostId, string password)
        {
            Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
            if (network == null)
            {
                AstralLog.Error("Raft_Network not found");
                return;
            }

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

            Raft_Network.OnJoinResult -= LogJoinResult;
            Raft_Network.OnJoinResult += LogJoinResult;
            network.TryToJoinGame(hostId, password ?? string.Empty);
            AstralLog.Info("TryToJoinGame " + hostId.m_SteamID);
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

                CSteamID localId = SteamUser.GetSteamID();
                string localName = SteamFriends.GetPersonaName() ?? "host";
                WriteFrame(stream, BuildWelcome(localId, localName));
                stream.ReadTimeout = Timeout.Infinite;

                Peer peer = new Peer(client, stream, remoteSteam);
                lock (PeersLock)
                {
                    Peers[remoteSteam] = peer;
                }

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
                    Incoming[channel].Enqueue(new QueuedPacket
                    {
                        SteamId = peer.SteamId,
                        Data = payload
                    });
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("recv closed " + peer.SteamId + ": " + ex.Message);
            }
            finally
            {
                RemovePeer(peer.SteamId);
            }
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

        private static byte[] BuildHello(CSteamID id, string name)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            byte[] body = new byte[1 + 8 + 2 + nameBytes.Length];
            body[0] = KindHello;
            WriteU64(body, 1, id.m_SteamID);
            WriteU16(body, 9, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 11, nameBytes.Length);
            return body;
        }

        private static byte[] BuildWelcome(CSteamID id, string name)
        {
            byte[] nameBytes = Encoding.UTF8.GetBytes(name ?? string.Empty);
            byte[] body = new byte[1 + 8 + 2 + nameBytes.Length];
            body[0] = KindWelcome;
            WriteU64(body, 1, id.m_SteamID);
            WriteU16(body, 9, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, body, 11, nameBytes.Length);
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
