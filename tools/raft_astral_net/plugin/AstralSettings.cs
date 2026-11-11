using UnityEngine;

namespace AstralRaftNet
{
    internal static class AstralSettings
    {
        private const string PrefAddress = "AstralLanAddress";
        private const string PrefPassword = "AstralLanPassword";

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
