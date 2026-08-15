using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using UnityEngine;

namespace AstralRaftNet
{
    internal sealed class AstralOverlay : MonoBehaviour
    {
        private static AstralOverlay _instance;
        private bool _visible;
        private string _address = string.Empty;
        private string _password = string.Empty;
        private string _portText = "6488";
        private Vector2 _logScroll;
        private Vector2 _playerScroll;
        private Rect _window = new Rect(40f, 60f, 560f, 620f);
        private string _logText = string.Empty;
        private int _logVersion = -1;
        private string _copyHint = string.Empty;
        private float _copyHintUntil;
        private string _tpHint = string.Empty;
        private float _tpHintUntil;
        private GUIStyle _logStyle;
        private GUIStyle _badgeStyle;
        private float _nextPlayerRefresh;
        private readonly List<PlayerPick> _players = new List<PlayerPick>();

        private struct PlayerPick
        {
            public Network_Player Player;
            public string Label;
        }

        public static void Destroy()
        {
            if (_instance != null)
            {
                UnityEngine.Object.Destroy(_instance.gameObject);
                _instance = null;
            }
        }

        private void Awake()
        {
            _instance = this;
            if (!string.IsNullOrEmpty(AstralSettings.Address))
            {
                _address = AstralSettings.Address;
            }
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.F7))
            {
                _visible = !_visible;
            }
        }

        private void OnGUI()
        {
            if (OnStartMenu())
            {
                DrawInjectedBadge();
            }

            if (!_visible)
            {
                return;
            }

            _window = GUI.Window(0x41535452, _window, DrawWindow, "Astral Raft IP / 连接日志");
        }

        private static bool OnStartMenu()
        {
            try
            {
                if (LoadSceneManager.IsGameSceneLoaded || LoadSceneManager.IsLoadingScene)
                {
                    return false;
                }

                return UnityEngine.Object.FindObjectOfType<StartMenuScreen>() != null;
            }
            catch
            {
                return true;
            }
        }

        private void DrawInjectedBadge()
        {
            if (_badgeStyle == null)
            {
                _badgeStyle = new GUIStyle(GUI.skin.box)
                {
                    alignment = TextAnchor.MiddleCenter,
                    fontSize = 16,
                    fontStyle = FontStyle.Bold,
                    normal =
                    {
                        textColor = new Color(0.82f, 0.98f, 0.78f)
                    }
                };
            }

            const float width = 168f;
            const float height = 36f;
            Rect rect = new Rect(Screen.width - width - 18f, 16f, width, height);
            Color prev = GUI.color;
            GUI.color = new Color(0.10f, 0.16f, 0.12f, 0.86f);
            GUI.Box(rect, "Astral已注入 · F7", _badgeStyle);
            GUI.color = prev;
        }

        private void RefreshLogText()
        {
            int version = AstralLog.Version;
            if (version == _logVersion)
            {
                return;
            }

            _logVersion = version;
            _logText = AstralLog.Dump();
            _logScroll.y = float.MaxValue;
        }

        private void RefreshPlayers()
        {
            if (Time.realtimeSinceStartup < _nextPlayerRefresh)
            {
                return;
            }

            _nextPlayerRefresh = Time.realtimeSinceStartup + 0.5f;
            _players.Clear();

            try
            {
                Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
                if (network == null)
                {
                    return;
                }

                Dictionary<Network_UserId, Network_Player> remoteUsers =
                    AccessTools.Field(typeof(Raft_Network), "remoteUsers")
                        .GetValue(network) as Dictionary<Network_UserId, Network_Player>;
                if (remoteUsers == null)
                {
                    return;
                }

                Network_Player local = network.GetLocalPlayer();
                foreach (KeyValuePair<Network_UserId, Network_Player> kv in remoteUsers)
                {
                    Network_Player player = kv.Value;
                    if (player == null || player == local || player.IsLocalPlayer)
                    {
                        continue;
                    }

                    string name = null;
                    try
                    {
                        if (!string.IsNullOrEmpty(player.visualName))
                        {
                            name = player.visualName;
                        }
                        else if (player.characterSettings != null)
                        {
                            name = player.characterSettings.Name;
                        }
                    }
                    catch
                    {
                    }

                    if (string.IsNullOrEmpty(name))
                    {
                        name = "player";
                    }

                    _players.Add(new PlayerPick
                    {
                        Player = player,
                        Label = name + "  (" + kv.Key.Id + ")"
                    });
                }
            }
            catch (Exception ex)
            {
                AstralLog.Error("refresh players: " + ex.Message);
            }
        }

        private static void TeleportLocalTo(Network_Player target)
        {
            if (target == null)
            {
                return;
            }

            Raft_Network network = UnityEngine.Object.FindObjectOfType<Raft_Network>();
            if (network == null)
            {
                return;
            }

            Network_Player local = network.GetLocalPlayer();
            if (local == null)
            {
                AstralLog.Info("teleport skipped: no local player");
                return;
            }

            Vector3 pos = target.transform.position;
            Behaviour controller = null;
            try
            {
                if (local.PersonController != null)
                {
                    FieldInfo controllerField = AccessTools.Field(typeof(PersonController), "controller");
                    if (controllerField != null)
                    {
                        controller = controllerField.GetValue(local.PersonController) as Behaviour;
                    }
                }
            }
            catch
            {
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

            string targetName = !string.IsNullOrEmpty(target.visualName)
                ? target.visualName
                : target.name;
            AstralLog.Info("teleport to " + targetName + " @ " + pos);
        }

        private void DrawWindow(int id)
        {
            RefreshLogText();
            RefreshPlayers();

            GUILayout.Label("F7 显示/隐藏 · UDP/KCP " + AstralTransport.Port
                + " · peers=" + AstralTransport.PeerCount
                + (AstralTransport.WorldReceived ? " · world=ok" : " · world=waiting"));
            GUILayout.Label("状态: " + AstralTransport.Status);

            GUILayout.BeginHorizontal();
            GUILayout.Label("端口", GUILayout.Width(40f));
            _portText = GUILayout.TextField(_portText, GUILayout.Width(80f));
            if (GUILayout.Button(AstralTransport.Listening ? "已监听" : "开始监听", GUILayout.Width(90f)))
            {
                int port;
                if (!int.TryParse(_portText, out port))
                {
                    port = AstralTransport.DefaultPort;
                }

                AstralTransport.Port = port;
                AstralTransport.StartListen(port);
            }

            if (GUILayout.Button("停听", GUILayout.Width(60f)))
            {
                AstralTransport.StopListen();
            }

            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            GUILayout.Label("IP", GUILayout.Width(40f));
            _address = GUILayout.TextField(_address);
            GUILayout.EndHorizontal();

            GUILayout.BeginHorizontal();
            GUILayout.Label("密码", GUILayout.Width(40f));
            _password = GUILayout.TextField(_password);
            GUILayout.EndHorizontal();

            if (GUILayout.Button("加入 IP:端口"))
            {
                int port;
                if (int.TryParse(_portText, out port))
                {
                    AstralTransport.Port = port;
                }

                AstralTransport.ConnectAndJoin(_address, _password);
            }

            GUILayout.Space(6f);
            GUILayout.Label("传送到玩家");
            if (_players.Count == 0)
            {
                GUILayout.Label("（暂无其他玩家）");
            }
            else
            {
                _playerScroll = GUILayout.BeginScrollView(_playerScroll, GUILayout.Height(90f));
                for (int i = 0; i < _players.Count; i++)
                {
                    PlayerPick pick = _players[i];
                    GUILayout.BeginHorizontal();
                    GUILayout.Label(pick.Label, GUILayout.ExpandWidth(true));
                    if (GUILayout.Button("传送", GUILayout.Width(60f)))
                    {
                        TeleportLocalTo(pick.Player);
                        _tpHint = "已传送 → " + pick.Label;
                        _tpHintUntil = Time.realtimeSinceStartup + 2.5f;
                    }

                    GUILayout.EndHorizontal();
                }

                GUILayout.EndScrollView();
            }

            if (!string.IsNullOrEmpty(_tpHint) && Time.realtimeSinceStartup <= _tpHintUntil)
            {
                GUILayout.Label(_tpHint);
            }

            GUILayout.Space(6f);
            GUILayout.BeginHorizontal();
            GUILayout.Label("连接日志（可拖选，或点复制）", GUILayout.ExpandWidth(true));
            if (GUILayout.Button("复制全部", GUILayout.Width(80f)))
            {
                GUIUtility.systemCopyBuffer = string.IsNullOrEmpty(_logText)
                    ? AstralLog.Dump()
                    : _logText;
                _copyHint = "已复制到剪贴板 (" + AstralLog.Count + " 行)";
                _copyHintUntil = Time.realtimeSinceStartup + 2.5f;
                AstralLog.Info("log copied to clipboard lines=" + AstralLog.Count);
            }

            if (GUILayout.Button("清空", GUILayout.Width(50f)))
            {
                AstralLog.Clear();
                _logText = string.Empty;
                _logVersion = -1;
            }

            GUILayout.EndHorizontal();

            if (!string.IsNullOrEmpty(_copyHint) && Time.realtimeSinceStartup <= _copyHintUntil)
            {
                GUILayout.Label(_copyHint);
            }

            if (_logStyle == null)
            {
                _logStyle = new GUIStyle(GUI.skin.textArea)
                {
                    fontSize = 12,
                    wordWrap = false,
                    richText = false,
                    alignment = TextAnchor.UpperLeft
                };
            }

            _logScroll = GUILayout.BeginScrollView(_logScroll, GUILayout.ExpandHeight(true));
            GUILayout.TextArea(
                string.IsNullOrEmpty(_logText) ? "(暂无日志)" : _logText,
                _logStyle,
                GUILayout.ExpandHeight(true),
                GUILayout.MinHeight(240f));
            GUILayout.EndScrollView();

            GUI.DragWindow(new Rect(0f, 0f, 10000f, 24f));
        }
    }
}
