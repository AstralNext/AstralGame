using System;
using UnityEngine;

namespace AstralValheimNet
{
    internal sealed class AstralOverlay : MonoBehaviour
    {
        private static AstralOverlay _instance;
        private bool _visible;
        private string _address = string.Empty;
        private Vector2 _logScroll;
        private Rect _window = new Rect(40f, 60f, 520f, 420f);
        private string _logText = string.Empty;
        private int _logVersion = -1;
        private string _copyHint = string.Empty;
        private float _copyHintUntil;
        private GUIStyle _badgeStyle;
        private GUIStyle _hostHintStyle;
        private GUIStyle _logStyle;
        private float _nextAttach;

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
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.F7))
            {
                _visible = !_visible;
            }

            if (Time.unscaledTime >= _nextAttach)
            {
                _nextAttach = Time.unscaledTime + 1.5f;
                AstralLanServerList.TryAttachExisting();
            }
        }

        private void OnGUI()
        {
            if (OnMainMenu())
            {
                DrawInjectedBadge();
                DrawHostHint();
            }

            if (!_visible)
            {
                return;
            }

            _window = GUI.Window(0x41535648, _window, DrawWindow, "Astral Valheim IP / 连接日志");
        }

        private static bool OnMainMenu()
        {
            try
            {
                return FejdStartup.instance != null;
            }
            catch
            {
                return true;
            }
        }

        private static bool HostPanelOpen()
        {
            try
            {
                FejdStartup startup = FejdStartup.instance;
                return startup != null &&
                       startup.m_startGamePanel != null &&
                       startup.m_startGamePanel.activeInHierarchy;
            }
            catch
            {
                return false;
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

            const float width = 176f;
            const float height = 36f;
            Rect rect = new Rect(Screen.width - width - 18f, 16f, width, height);
            Color prev = GUI.color;
            GUI.color = new Color(0.10f, 0.16f, 0.12f, 0.86f);
            GUI.Box(rect, "Astral已注入 · F7", _badgeStyle);
            GUI.color = prev;
        }

        private void DrawHostHint()
        {
            if (!HostPanelOpen())
            {
                return;
            }

            if (_hostHintStyle == null)
            {
                _hostHintStyle = new GUIStyle(GUI.skin.box)
                {
                    alignment = TextAnchor.MiddleLeft,
                    fontSize = 14,
                    wordWrap = true,
                    padding = new RectOffset(12, 12, 8, 8),
                    normal =
                    {
                        textColor = new Color(0.95f, 0.93f, 0.78f)
                    }
                };
            }

            float width = Mathf.Min(420f, Screen.width - 40f);
            Rect rect = new Rect(20f, 16f, width, 58f);
            Color prev = GUI.color;
            GUI.color = new Color(0.14f, 0.12f, 0.08f, 0.88f);
            GUI.Box(
                rect,
                "Astral开房：已关闭跨平台，走 Steam IP " + AstralValheim.GamePort +
                "。加入方打开服务器列表「astral局域网」。",
                _hostHintStyle);
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

        private void DrawWindow(int id)
        {
            RefreshLogText();
            GUILayout.Label("F7 显示/隐藏 · 游戏口 UDP " + AstralValheim.GamePort +
                            " · 发现 UDP " + AstralValheim.DiscoveryPort +
                            (SteamIpListen.IsListening ? " · IP听服中" : " · 未听IP"));

            GUILayout.BeginHorizontal();
            GUILayout.Label("IP:端口", GUILayout.Width(56f));
            _address = GUILayout.TextField(_address);
            GUILayout.EndHorizontal();

            if (GUILayout.Button("加入 Steam IP"))
            {
                string host;
                int port;
                ParseHostPort(_address, out host, out port);
                FejdStartup startup = FejdStartup.instance;
                if (startup == null)
                {
                    AstralLog.Error("join skipped: no FejdStartup");
                }
                else
                {
                    AstralLog.Info("overlay join " + host + ":" + port);
                    AstralJoin.TryJoinDedicated(startup, host, port);
                }
            }

            GUILayout.Space(6f);
            GUILayout.BeginHorizontal();
            GUILayout.Label("连接日志", GUILayout.ExpandWidth(true));
            if (GUILayout.Button("复制全部", GUILayout.Width(80f)))
            {
                GUIUtility.systemCopyBuffer = string.IsNullOrEmpty(_logText) ? AstralLog.Dump() : _logText;
                _copyHint = "已复制 (" + AstralLog.Count + " 行)";
                _copyHintUntil = Time.realtimeSinceStartup + 2.5f;
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
                GUILayout.MinHeight(180f));
            GUILayout.EndScrollView();
            GUI.DragWindow(new Rect(0f, 0f, 10000f, 24f));
        }

        private static void ParseHostPort(string raw, out string host, out int port)
        {
            host = (raw ?? string.Empty).Trim();
            port = AstralValheim.GamePort;
            int colon = host.LastIndexOf(':');
            if (colon <= 0 || colon == host.Length - 1)
            {
                return;
            }

            int parsed;
            if (int.TryParse(host.Substring(colon + 1), out parsed) && parsed > 0 && parsed <= 65535)
            {
                port = parsed;
                host = host.Substring(0, colon);
            }
        }
    }
}
