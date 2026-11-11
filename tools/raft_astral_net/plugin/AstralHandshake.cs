using System;
using System.Security.Cryptography;
using System.Text;

namespace AstralRaftNet
{
    /// <summary>
    /// HELLO v2 的密码证明：只传 nonce 与 SHA256(nonce || password)，
    /// 明文密码不再出现在链路上；比较用常量时间。纯逻辑，便于单测。
    /// </summary>
    internal static class AstralHandshake
    {
        public const byte Version2 = 2;
        public const int NonceSize = 16;
        public const int ProofSize = 32;

        public static byte[] NewNonce()
        {
            byte[] nonce = new byte[NonceSize];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(nonce);
            }

            return nonce;
        }

        public static byte[] ComputeProof(byte[] nonce, string password)
        {
            if (nonce == null)
            {
                throw new ArgumentNullException("nonce");
            }

            byte[] secret = Encoding.UTF8.GetBytes(password ?? string.Empty);
            byte[] material = new byte[nonce.Length + secret.Length];
            Buffer.BlockCopy(nonce, 0, material, 0, nonce.Length);
            Buffer.BlockCopy(secret, 0, material, nonce.Length, secret.Length);
            using (SHA256 sha = SHA256.Create())
            {
                return sha.ComputeHash(material);
            }
        }

        /// <summary>常量时间比较，避免按字节提前返回带来的计时侧信道。</summary>
        public static bool FixedTimeEquals(byte[] left, byte[] right)
        {
            if (left == null || right == null || left.Length != right.Length)
            {
                return false;
            }

            int diff = 0;
            for (int i = 0; i < left.Length; i++)
            {
                diff |= left[i] ^ right[i];
            }

            return diff == 0;
        }
    }
}
