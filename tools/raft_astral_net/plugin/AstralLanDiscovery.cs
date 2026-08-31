using System;
using System.Collections.Generic;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Steamworks;

namespace AstralRaftNet
{
    internal sealed class LanRoom
    {
        public ulong SteamId;
        public string Ip;
        public int TcpPort;
        public string Name;
        public bool Password;
        public DateTime LastSeenUtc;

        public string EndPoint
        {
            get { return Ip + ":" + TcpPort; }
        }

        public string DisplayName
        {
            get
            {
                string name = string.IsNullOrEmpty(Name) ? SteamId.ToString() : Name;
                return name + "  " + EndPoint;
            }
        }
    }

    internal static class AstralLanDiscovery
    {
        public const int DiscoveryPort = 6489;
        private const int Magic = 0x41535452;
        private const byte Version = 1;
        private const byte KindAnnounce = 10;
        private const int RoomTtlMs = 8000;

        private static readonly object Sync = new object();
        private static readonly Dictionary<ulong, LanRoom> Rooms = new Dictionary<ulong, LanRoom>();

        private static Socket _socket;
        private static Thread _recvThread;
        private static Thread _broadcastThread;
        private static volatile bool _recvRunning;
        private static volatile bool _broadcastRunning;
        private static int _tcpPort = AstralTransport.DefaultPort;
        private static bool _password;
        private static string _name = "ASGAME";

        public static void EnsureReceiver()
        {
            lock (Sync)
            {
                if (_recvRunning)
                {
                    return;
                }

                try
                {
                    Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
                    socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                    socket.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.Broadcast, true);
                    socket.Bind(new IPEndPoint(IPAddress.Any, DiscoveryPort));
                    socket.ReceiveTimeout = 1000;
                    _socket = socket;
                    _recvRunning = true;
                    _recvThread = new Thread(RecvLoop)
                    {
                        IsBackground = true,
                        Name = "AstralLanRecv"
                    };
                    _recvThread.Start();
                    AstralLog.Info("LAN discovery listen UDP " + DiscoveryPort);
                }
                catch (Exception ex)
                {
                    _recvRunning = false;
                    AstralLog.Error("LAN listen failed: " + ex.Message);
                }
            }
        }

        public static void StartBroadcast(int tcpPort, bool password, string name)
        {
            EnsureReceiver();
            _tcpPort = tcpPort <= 0 ? AstralTransport.DefaultPort : tcpPort;
            _password = password;
            _name = string.IsNullOrEmpty(name) ? "ASGAME" : name;
            if (_broadcastRunning)
            {
                return;
            }

            _broadcastRunning = true;
            _broadcastThread = new Thread(BroadcastLoop)
            {
                IsBackground = true,
                Name = "AstralLanBroadcast"
            };
            _broadcastThread.Start();
            AstralLog.Info("LAN broadcast 255.255.255.255:" + DiscoveryPort + " tcp=" + _tcpPort);
        }

        public static void StopBroadcast()
        {
            _broadcastRunning = false;
        }

        public static void StopAll()
        {
            _broadcastRunning = false;
            _recvRunning = false;
            try
            {
                if (_socket != null)
                {
                    _socket.Close();
                }
            }
            catch (Exception ex)
            {
                AstralLog.Info("StopAll socket close: " + ex.Message);
            }

            _socket = null;
            lock (Sync)
            {
                Rooms.Clear();
            }
        }

        public static List<LanRoom> Snapshot()
        {
            DateTime now = DateTime.UtcNow;
            List<LanRoom> list = new List<LanRoom>();
            ulong local = 0;
            try
            {
                local = SteamUser.GetSteamID().m_SteamID;
            }
            catch (Exception ex)
            {
                AstralLog.Info("Snapshot SteamUser unavailable: " + ex.Message);
            }

            lock (Sync)
            {
                List<ulong> expired = new List<ulong>();
                foreach (KeyValuePair<ulong, LanRoom> pair in Rooms)
                {
                    if ((now - pair.Value.LastSeenUtc).TotalMilliseconds > RoomTtlMs)
                    {
                        expired.Add(pair.Key);
                        continue;
                    }

                    if (local != 0 && pair.Key == local)
                    {
                        continue;
                    }

                    list.Add(pair.Value);
                }

                for (int i = 0; i < expired.Count; i++)
                {
                    Rooms.Remove(expired[i]);
                }
            }

            return list;
        }

        public static bool TryGet(CSteamID steamId, out LanRoom room)
        {
            room = null;
            if (steamId == null || !steamId.IsValid())
            {
                return false;
            }

            lock (Sync)
            {
                LanRoom found;
                if (!Rooms.TryGetValue(steamId.m_SteamID, out found))
                {
                    return false;
                }

                if ((DateTime.UtcNow - found.LastSeenUtc).TotalMilliseconds > RoomTtlMs)
                {
                    Rooms.Remove(steamId.m_SteamID);
                    return false;
                }

                room = found;
                return true;
            }
        }

        private static void BroadcastLoop()
        {
            while (_broadcastRunning)
            {
                try
                {
                    byte[] packet = BuildAnnounce();
                    SendBroadcast(packet);
                }
                catch (Exception ex)
                {
                    AstralLog.Error("LAN broadcast: " + ex.Message);
                }

                int waited = 0;
                while (_broadcastRunning && waited < 2000)
                {
                    Thread.Sleep(100);
                    waited += 100;
                }
            }
        }

        private static void RecvLoop()
        {
            byte[] buffer = new byte[1024];
            EndPoint remote = new IPEndPoint(IPAddress.Any, 0);
            while (_recvRunning && _socket != null)
            {
                try
                {
                    int read = _socket.ReceiveFrom(buffer, ref remote);
                    IPEndPoint ep = remote as IPEndPoint;
                    if (ep == null || read < 19)
                    {
                        continue;
                    }

                    LanRoom room;
                    if (!TryParseAnnounce(buffer, read, ep.Address, out room))
                    {
                        continue;
                    }

                    ulong local = 0;
                    try
                    {
                        local = SteamUser.GetSteamID().m_SteamID;
                    }
                    catch (Exception ex)
                    {
                        AstralLog.Info("RecvLoop SteamUser unavailable: " + ex.Message);
                    }

                    if (local != 0 && room.SteamId == local)
                    {
                        continue;
                    }

                    lock (Sync)
                    {
                        Rooms[room.SteamId] = room;
                    }
                }
                catch (SocketException ex)
                {
                    if (_recvRunning &&
                        ex.SocketErrorCode != SocketError.TimedOut &&
                        ex.SocketErrorCode != SocketError.Interrupted)
                    {
                        AstralLog.Error("LAN recv socket: " + ex.SocketErrorCode + " " + ex.Message);
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
                        AstralLog.Error("LAN recv: " + ex.Message);
                    }
                }
            }
        }

        private static void SendBroadcast(byte[] packet)
        {
            Socket socket = _socket;
            if (socket == null)
            {
                return;
            }

            try
            {
                socket.SendTo(packet, new IPEndPoint(IPAddress.Broadcast, DiscoveryPort));
            }
            catch (Exception ex)
            {
                AstralLog.Info("LAN bcast 255.255.255.255 fail: " + ex.Message);
            }

            try
            {
                foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (nic.OperationalStatus != OperationalStatus.Up)
                    {
                        continue;
                    }

                    foreach (UnicastIPAddressInformation unicast in nic.GetIPProperties().UnicastAddresses)
                    {
                        if (unicast.Address == null || unicast.Address.AddressFamily != AddressFamily.InterNetwork)
                        {
                            continue;
                        }

                        byte[] ip = unicast.Address.GetAddressBytes();
                        byte[] mask = unicast.IPv4Mask != null ? unicast.IPv4Mask.GetAddressBytes() : new byte[] { 255, 255, 255, 0 };
                        byte[] bcast = new byte[4];
                        for (int i = 0; i < 4; i++)
                        {
                            bcast[i] = (byte)(ip[i] | ~mask[i]);
                        }

                        try
                        {
                            socket.SendTo(packet, new IPEndPoint(new IPAddress(bcast), DiscoveryPort));
                        }
                        catch (Exception ex)
                        {
                            AstralLog.Info("LAN bcast nic " + unicast.Address + " fail: " + ex.Message);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                AstralLog.Info("LAN bcast nic enum fail: " + ex.Message);
            }
        }

        private static byte[] BuildAnnounce()
        {
            ulong steamId = 0;
            try
            {
                steamId = SteamUser.GetSteamID().m_SteamID;
            }
            catch
            {
            }

            byte[] nameBytes = Encoding.UTF8.GetBytes(_name ?? "ASGAME");
            if (nameBytes.Length > 80)
            {
                Array.Resize(ref nameBytes, 80);
            }

            byte[] packet = new byte[19 + nameBytes.Length];
            WriteU32(packet, 0, Magic);
            packet[4] = Version;
            packet[5] = KindAnnounce;
            WriteU64(packet, 6, steamId);
            WriteU16(packet, 14, (ushort)_tcpPort);
            packet[16] = (byte)(_password ? 1 : 0);
            WriteU16(packet, 17, (ushort)nameBytes.Length);
            Buffer.BlockCopy(nameBytes, 0, packet, 19, nameBytes.Length);
            return packet;
        }

        private static bool TryParseAnnounce(byte[] buffer, int length, IPAddress source, out LanRoom room)
        {
            room = null;
            if (length < 19 || ReadU32(buffer, 0) != Magic || buffer[4] != Version || buffer[5] != KindAnnounce)
            {
                return false;
            }

            int nameLen = ReadU16(buffer, 17);
            if (nameLen < 0 || 19 + nameLen > length)
            {
                return false;
            }

            IPAddress ipv4 = source;
            if (ipv4.AddressFamily == AddressFamily.InterNetworkV6)
            {
                ipv4 = ipv4.MapToIPv4();
            }

            room = new LanRoom
            {
                SteamId = ReadU64(buffer, 6),
                Ip = ipv4.ToString(),
                TcpPort = ReadU16(buffer, 14),
                Password = (buffer[16] & 1) != 0,
                Name = Encoding.UTF8.GetString(buffer, 19, nameLen),
                LastSeenUtc = DateTime.UtcNow
            };
            return room.SteamId != 0 && room.TcpPort > 0;
        }

        private static void WriteU32(byte[] buffer, int offset, int value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            Buffer.BlockCopy(bytes, 0, buffer, offset, 4);
        }

        private static void WriteU16(byte[] buffer, int offset, ushort value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            Buffer.BlockCopy(bytes, 0, buffer, offset, 2);
        }

        private static void WriteU64(byte[] buffer, int offset, ulong value)
        {
            byte[] bytes = BitConverter.GetBytes(value);
            Buffer.BlockCopy(bytes, 0, buffer, offset, 8);
        }

        private static int ReadU32(byte[] buffer, int offset)
        {
            return BitConverter.ToInt32(buffer, offset);
        }

        private static int ReadU16(byte[] buffer, int offset)
        {
            return BitConverter.ToUInt16(buffer, offset);
        }

        private static ulong ReadU64(byte[] buffer, int offset)
        {
            return BitConverter.ToUInt64(buffer, offset);
        }
    }
}
