using System;
using HarmonyLib;
using UnityEngine;
using UnityEngine.Events;
using UnityEngine.UI;

namespace AstralRaftNet
{
    internal static class AstralMenuUi
    {
        private const string NewToggleName = "AstralLanToggle_New";
        private const string LoadToggleName = "AstralLanToggle_Load";
        private const string JoinRootName = "AstralLanJoinRoot";

        public static void EnsureNewGame(NewGameBox box)
        {
            if (box == null || FindChild(box.transform, NewToggleName) != null)
            {
                return;
            }

            Toggle source = GetPrivate<Toggle>(box, "toggle_FriendlyFire");
            if (source == null)
            {
                return;
            }

            Toggle toggle = CloneToggle(source, NewToggleName, "启用Astral局域网");
            toggle.isOn = AstralSettings.EnableLan;
            toggle.onValueChanged.AddListener(new UnityAction<bool>(OnLanToggled));
            toggle.gameObject.SetActive(source.gameObject.activeSelf);
        }

        public static void EnsureLoadGame(LoadGameBox box)
        {
            if (box == null || FindChild(box.transform, LoadToggleName) != null)
            {
                return;
            }

            Toggle source = GetPrivate<Toggle>(box, "allowFriendlyFireToggle");
            if (source == null)
            {
                return;
            }

            Toggle toggle = CloneToggle(source, LoadToggleName, "启用Astral局域网");
            toggle.isOn = AstralSettings.EnableLan;
            toggle.onValueChanged.AddListener(new UnityAction<bool>(OnLanToggled));
            toggle.gameObject.SetActive(source.gameObject.activeSelf);
        }

        public static void EnsureJoinGame(JoinGameBox box)
        {
            if (box == null || FindChild(box.transform, JoinRootName) != null)
            {
                return;
            }

            Button joinButton = GetPrivate<Button>(box, "joinGameButton");
            InputField steamIdField = GetPrivate<InputField>(box, "cheat_joinGameSteamID");
            InputField passwordField = GetPrivate<InputField>(box, "cheat_joinGamePassword");
            Text sampleText = box.GetComponentInChildren<Text>(true);
            Transform parent = joinButton != null ? joinButton.transform.parent : box.transform;

            GameObject root = new GameObject(JoinRootName, typeof(RectTransform));
            root.transform.SetParent(parent, false);
            RectTransform rootRt = root.GetComponent<RectTransform>();
            if (joinButton != null)
            {
                RectTransform src = joinButton.GetComponent<RectTransform>();
                CopyRect(src, rootRt);
                root.transform.SetSiblingIndex(joinButton.transform.GetSiblingIndex() + 1);
                rootRt.anchoredPosition = src.anchoredPosition + new Vector2(0f, -(Mathf.Abs(src.rect.height) + 12f));
                rootRt.sizeDelta = new Vector2(Mathf.Max(src.sizeDelta.x, 360f), 90f);
            }
            else
            {
                rootRt.anchorMin = new Vector2(0.5f, 0f);
                rootRt.anchorMax = new Vector2(0.5f, 0f);
                rootRt.pivot = new Vector2(0.5f, 0f);
                rootRt.sizeDelta = new Vector2(360f, 90f);
                rootRt.anchoredPosition = new Vector2(0f, 20f);
            }

            VerticalLayoutGroup layout = root.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 6f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlHeight = true;
            layout.childControlWidth = true;
            layout.childForceExpandHeight = false;
            layout.childForceExpandWidth = true;

            CreateLabel(root.transform, sampleText, "加入局域网世界");

            InputField ip = CloneOrCreateInput(root.transform, steamIdField, sampleText, AstralSettings.Address, "IP:端口");
            ip.name = "AstralLanIp";
            InputField pw = CloneOrCreateInput(root.transform, passwordField, sampleText, AstralSettings.Password, "密码(可空)");
            pw.name = "AstralLanPassword";
            pw.contentType = InputField.ContentType.Password;

            Button lanJoin = CloneOrCreateButton(root.transform, joinButton, sampleText, "加入局域网世界");
            lanJoin.onClick.AddListener(delegate
            {
                AstralSettings.Address = ip.text;
                AstralSettings.Password = pw.text;
                AstralLog.Info("lan join " + ip.text);
                AstralTransport.ConnectAndJoin(ip.text, pw.text);
                if (box.connectingBox != null)
                {
                    box.connectingBox.gameObject.SetActive(true);
                    box.connectingBox.StartConnectTimeoutTimer();
                }
            });
        }

        public static void SyncNewGameVisibility(NewGameBox box)
        {
            Toggle source = GetPrivate<Toggle>(box, "toggle_FriendlyFire");
            Transform child = FindChild(box.transform, NewToggleName);
            if (source != null && child != null)
            {
                child.gameObject.SetActive(source.gameObject.activeSelf);
            }
        }

        public static void SyncLoadGameVisibility(LoadGameBox box)
        {
            Toggle source = GetPrivate<Toggle>(box, "allowFriendlyFireToggle");
            Transform child = FindChild(box.transform, LoadToggleName);
            if (source != null && child != null)
            {
                child.gameObject.SetActive(source.gameObject.activeSelf);
            }
        }

        public static bool ReadNewGameLan(NewGameBox box)
        {
            return ReadToggle(box.transform, NewToggleName);
        }

        public static bool ReadLoadGameLan(LoadGameBox box)
        {
            return ReadToggle(box.transform, LoadToggleName);
        }

        private static bool ReadToggle(Transform root, string name)
        {
            Transform child = FindChild(root, name);
            if (child == null)
            {
                return AstralSettings.EnableLan;
            }

            Toggle toggle = child.GetComponent<Toggle>();
            return toggle != null && toggle.isOn;
        }

        private static void OnLanToggled(bool on)
        {
            AstralSettings.EnableLan = on;
        }

        private static Toggle CloneToggle(Toggle source, string name, string label)
        {
            GameObject clone = UnityEngine.Object.Instantiate(source.gameObject, source.transform.parent);
            clone.name = name;
            clone.transform.SetSiblingIndex(source.transform.GetSiblingIndex() + 1);
            RectTransform srcRt = source.GetComponent<RectTransform>();
            RectTransform dstRt = clone.GetComponent<RectTransform>();
            if (srcRt != null && dstRt != null && source.transform.parent.GetComponent<VerticalLayoutGroup>() == null)
            {
                dstRt.anchoredPosition = srcRt.anchoredPosition + new Vector2(0f, -(Mathf.Abs(srcRt.rect.height) + 8f));
            }

            StripLocalize(clone);
            SetAnyLabel(clone, label);
            Toggle toggle = clone.GetComponent<Toggle>();
            toggle.onValueChanged.RemoveAllListeners();
            return toggle;
        }

        private static InputField CloneOrCreateInput(Transform parent, InputField source, Text sample, string value, string placeholder)
        {
            InputField field;
            if (source != null)
            {
                GameObject clone = UnityEngine.Object.Instantiate(source.gameObject, parent);
                clone.SetActive(true);
                StripLocalize(clone);
                field = clone.GetComponent<InputField>();
                field.onValueChanged.RemoveAllListeners();
                field.onEndEdit.RemoveAllListeners();
            }
            else
            {
                field = CreateInput(parent, sample, placeholder);
            }

            field.text = value ?? string.Empty;
            if (field.placeholder != null)
            {
                Text ph = field.placeholder as Text;
                if (ph != null)
                {
                    ph.text = placeholder;
                }
                else
                {
                    SetAnyLabel(field.placeholder.gameObject, placeholder);
                }
            }

            return field;
        }

        private static Button CloneOrCreateButton(Transform parent, Button source, Text sample, string label)
        {
            Button button;
            if (source != null)
            {
                GameObject clone = UnityEngine.Object.Instantiate(source.gameObject, parent);
                clone.SetActive(true);
                StripLocalize(clone);
                button = clone.GetComponent<Button>();
                button.onClick.RemoveAllListeners();
            }
            else
            {
                button = CreateButton(parent, sample, label);
            }

            SetAnyLabel(button.gameObject, label);
            return button;
        }

        private static InputField CreateInput(Transform parent, Text sample, string placeholder)
        {
            GameObject go = new GameObject("AstralInput", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image), typeof(InputField));
            go.transform.SetParent(parent, false);
            Image image = go.GetComponent<Image>();
            image.color = new Color(0f, 0f, 0f, 0.55f);
            LayoutElement le = go.AddComponent<LayoutElement>();
            le.minHeight = 28f;
            le.preferredHeight = 28f;

            GameObject textGo = new GameObject("Text", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            textGo.transform.SetParent(go.transform, false);
            Stretch(textGo.GetComponent<RectTransform>(), 6f);
            Text text = textGo.GetComponent<Text>();
            ApplyTextStyle(text, sample, Color.white);
            text.alignment = TextAnchor.MiddleLeft;

            GameObject phGo = new GameObject("Placeholder", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            phGo.transform.SetParent(go.transform, false);
            Stretch(phGo.GetComponent<RectTransform>(), 6f);
            Text ph = phGo.GetComponent<Text>();
            ApplyTextStyle(ph, sample, new Color(1f, 1f, 1f, 0.45f));
            ph.text = placeholder;
            ph.fontStyle = FontStyle.Italic;
            ph.alignment = TextAnchor.MiddleLeft;

            InputField field = go.GetComponent<InputField>();
            field.textComponent = text;
            field.placeholder = ph;
            return field;
        }

        private static Button CreateButton(Transform parent, Text sample, string label)
        {
            GameObject go = new GameObject("AstralButton", typeof(RectTransform), typeof(CanvasRenderer), typeof(Image), typeof(Button));
            go.transform.SetParent(parent, false);
            go.GetComponent<Image>().color = new Color(0.15f, 0.45f, 0.75f, 0.95f);
            LayoutElement le = go.AddComponent<LayoutElement>();
            le.minHeight = 32f;
            le.preferredHeight = 32f;

            GameObject textGo = new GameObject("Text", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            textGo.transform.SetParent(go.transform, false);
            Stretch(textGo.GetComponent<RectTransform>(), 0f);
            Text text = textGo.GetComponent<Text>();
            ApplyTextStyle(text, sample, Color.white);
            text.alignment = TextAnchor.MiddleCenter;
            text.text = label;
            return go.GetComponent<Button>();
        }

        private static void CreateLabel(Transform parent, Text sample, string label)
        {
            GameObject go = new GameObject("AstralLabel", typeof(RectTransform), typeof(CanvasRenderer), typeof(Text));
            go.transform.SetParent(parent, false);
            LayoutElement le = go.AddComponent<LayoutElement>();
            le.minHeight = 22f;
            le.preferredHeight = 22f;
            Text text = go.GetComponent<Text>();
            ApplyTextStyle(text, sample, Color.white);
            text.alignment = TextAnchor.MiddleLeft;
            text.text = label;
        }

        private static void ApplyTextStyle(Text target, Text sample, Color color)
        {
            if (sample != null)
            {
                target.font = sample.font;
                target.fontSize = sample.fontSize > 0 ? sample.fontSize : 16;
            }
            else
            {
                target.font = Resources.GetBuiltinResource<Font>("Arial.ttf");
                target.fontSize = 16;
            }

            target.color = color;
            target.horizontalOverflow = HorizontalWrapMode.Overflow;
            target.verticalOverflow = VerticalWrapMode.Overflow;
        }

        private static void Stretch(RectTransform rt, float pad)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = new Vector2(pad, 2f);
            rt.offsetMax = new Vector2(-pad, -2f);
        }

        private static void CopyRect(RectTransform src, RectTransform dst)
        {
            dst.anchorMin = src.anchorMin;
            dst.anchorMax = src.anchorMax;
            dst.pivot = src.pivot;
            dst.sizeDelta = src.sizeDelta;
            dst.anchoredPosition = src.anchoredPosition;
            dst.localScale = Vector3.one;
        }

        private static void StripLocalize(GameObject go)
        {
            MonoBehaviour[] behaviours = go.GetComponentsInChildren<MonoBehaviour>(true);
            for (int i = 0; i < behaviours.Length; i++)
            {
                MonoBehaviour behaviour = behaviours[i];
                if (behaviour == null)
                {
                    continue;
                }

                string typeName = behaviour.GetType().Name;
                if (typeName == "Localize" || typeName == "LocalizeDropdown")
                {
                    behaviour.enabled = false;
                }
            }
        }

        private static void SetAnyLabel(GameObject go, string label)
        {
            Text[] texts = go.GetComponentsInChildren<Text>(true);
            for (int i = 0; i < texts.Length; i++)
            {
                if (texts[i] != null && texts[i].name != "Placeholder")
                {
                    texts[i].text = label;
                }
            }

            MonoBehaviour[] behaviours = go.GetComponentsInChildren<MonoBehaviour>(true);
            for (int i = 0; i < behaviours.Length; i++)
            {
                MonoBehaviour behaviour = behaviours[i];
                if (behaviour == null)
                {
                    continue;
                }

                string typeName = behaviour.GetType().Name;
                if (typeName == "TextMeshProUGUI" || typeName == "TMP_Text")
                {
                    try
                    {
                        behaviour.GetType().GetProperty("text").SetValue(behaviour, label, null);
                    }
                    catch
                    {
                    }
                }
            }
        }

        private static Transform FindChild(Transform root, string name)
        {
            if (root == null)
            {
                return null;
            }

            if (root.name == name)
            {
                return root;
            }

            for (int i = 0; i < root.childCount; i++)
            {
                Transform found = FindChild(root.GetChild(i), name);
                if (found != null)
                {
                    return found;
                }
            }

            return null;
        }

        private static T GetPrivate<T>(object instance, string fieldName) where T : class
        {
            try
            {
                return AccessTools.Field(instance.GetType(), fieldName).GetValue(instance) as T;
            }
            catch (Exception ex)
            {
                AstralLog.Error("field " + fieldName + ": " + ex.Message);
                return null;
            }
        }
    }
}
