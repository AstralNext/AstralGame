// 共享模板：由两个插件项目通过 Link 方式引用
// 在 Raft 项目定义 ASTRAL_RAFT，Valheim 项目定义 ASTRAL_VALHEIM
#if ASTRAL_RAFT
namespace AstralRaftNet
#elif ASTRAL_VALHEIM
namespace AstralValheimNet
#endif
{
    using System;
    using System.IO;
    using System.Reflection;

    public static class Loader
    {
        private static readonly string[] LogPaths =
        {
#if ASTRAL_RAFT
            Path.Combine(Path.GetTempPath(), "astral_raft_net.log")
#elif ASTRAL_VALHEIM
            Path.Combine(Path.GetTempPath(), "astral_valheim_net.log")
#endif
        };

#if ASTRAL_RAFT
        private const string BootstrapTypeName = "AstralRaftNet.HarmonyBootstrap, AstralRaftNet";
#elif ASTRAL_VALHEIM
        private const string BootstrapTypeName = "AstralValheimNet.HarmonyBootstrap, AstralValheimNet";
#endif

        static Loader()
        {
            AppDomain.CurrentDomain.AssemblyResolve += ResolveEmbedded;
            Log("cctor");
        }

        public static void Init()
        {
            try
            {
                Log("init start");
                LoadEmbeddedHarmony();
                Type type = Type.GetType(BootstrapTypeName, true);
                Log("type " + type.FullName);
                type.GetMethod("Apply", BindingFlags.Public | BindingFlags.Static).Invoke(null, null);
                Log("init ok");
            }
            catch (Exception ex)
            {
                Log(ex.ToString());
            }
        }

        public static void Unload()
        {
            try
            {
                Type type = Type.GetType(BootstrapTypeName, false);
                if (type != null)
                {
                    type.GetMethod("Remove", BindingFlags.Public | BindingFlags.Static).Invoke(null, null);
                }

                Log("unload ok");
            }
            catch (Exception ex)
            {
                Log(ex.ToString());
            }
        }

        private static void LoadEmbeddedHarmony()
        {
            foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                if (assembly.GetName().Name == "0Harmony")
                {
                    return;
                }
            }

            using (Stream stream = typeof(Loader).Assembly.GetManifestResourceStream("0Harmony.dll"))
            {
                if (stream == null)
                {
                    throw new FileNotFoundException("embedded 0Harmony.dll missing");
                }

                byte[] buffer = new byte[stream.Length];
                stream.Read(buffer, 0, buffer.Length);
                Assembly.Load(buffer);
                Log("Assembly.Load 0Harmony " + buffer.Length);
            }
        }

        private static void Log(string message)
        {
            string line = DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine;
            foreach (string path in LogPaths)
            {
                try
                {
                    File.AppendAllText(path, line);
                }
                catch
                {
                }
            }
        }

        private static Assembly ResolveEmbedded(object sender, ResolveEventArgs args)
        {
            string name = new AssemblyName(args.Name).Name;
            if (name != "0Harmony")
            {
                return null;
            }

            foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
            {
                if (assembly.GetName().Name == "0Harmony")
                {
                    return assembly;
                }
            }

            using (Stream stream = typeof(Loader).Assembly.GetManifestResourceStream("0Harmony.dll"))
            {
                if (stream == null)
                {
                    return null;
                }

                byte[] buffer = new byte[stream.Length];
                stream.Read(buffer, 0, buffer.Length);
                return Assembly.Load(buffer);
            }
        }
    }
}
