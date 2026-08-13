using UnityEngine;

namespace AstralRaftNet
{
    internal sealed class AstralOverlay : MonoBehaviour
    {
        private static AstralOverlay _instance;
        private bool _visible;
        private string _address = "127.0.0.1:6488";
        private string _password = string.Empty;
        private string _portText = "6488";
        private Vector2 _logScroll;
        private Rect _window = new Rect(40f, 80f, 420f, 420f);

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
        }

        private GUIStyle _badgeStyle;

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

            _window = GUI.Window(0x41535452, _window, DrawWindow, "Astral Raft IP");
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
            GUI.Box(rect, "Astral已注入", _badgeStyle);
            GUI.color = prev;
        }

        private void DrawWindow(int id)
        {
            GUILayout.Label("F7 显示/隐藏    TCP " + AstralTransport.DefaultPort);
            GUILayout.Label("状态: " + AstralTransport.Status + "    peers=" + AstralTransport.PeerCount);

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

            GUILayout.Space(8f);
            GUILayout.Label("日志");
            _logScroll = GUILayout.BeginScrollView(_logScroll, GUILayout.Height(180f));
            foreach (string line in AstralLog.Snapshot)
            {
                GUILayout.Label(line);
            }

            GUILayout.EndScrollView();
            GUI.DragWindow();
        }
    }
}
