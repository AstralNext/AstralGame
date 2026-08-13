using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralSettings
    {
        private const string PrefLan = "AstralLanEnabled";
        private const string PrefAddress = "AstralLanAddress";
        private const string PrefPassword = "AstralLanPassword";

        public static bool EnableLan
        {
            get { return PlayerPrefs.GetInt(PrefLan, 1) != 0; }
            set
            {
                PlayerPrefs.SetInt(PrefLan, value ? 1 : 0);
                PlayerPrefs.Save();
            }
        }

        public static string Address
        {
            get { return PlayerPrefs.GetString(PrefAddress, string.Empty); }
            set
            {
                PlayerPrefs.SetString(PrefAddress, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }

        public static string Password
        {
            get { return PlayerPrefs.GetString(PrefPassword, string.Empty); }
            set
            {
                PlayerPrefs.SetString(PrefPassword, value ?? string.Empty);
                PlayerPrefs.Save();
            }
        }
    }
}
