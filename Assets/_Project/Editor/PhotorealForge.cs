using System.IO;
using UnityEditor;
using UnityEngine;

namespace Wolf.EditorTools
{
    /// <summary>
    /// Generates the district's PBR content offline, in-editor: procedural
    /// texture maps (albedo / normal / HDRP mask) for wet asphalt, concrete
    /// and metal, and the material assets that use them. Exists because this
    /// project is built from a headless environment where photogrammetry
    /// libraries can't be downloaded — the maps are noise-based but tuned for
    /// HDRP's lighting (puddle smoothness on asphalt is what sells the neon
    /// reflections at night). Idempotent: re-running overwrites in place and
    /// existing GUID references survive.
    /// </summary>
    internal static class PhotorealForge
    {
        internal const string Dir = "Assets/_Project/Art/Generated";
        private const int TexSize = 1024;

        // Material asset paths, used by the district builder and mannequins.
        internal static string AsphaltMat => Dir + "/M_Asphalt.mat";
        internal static string ConcreteMat => Dir + "/M_Concrete.mat";
        internal static string MetalMat => Dir + "/M_Metal.mat";
        internal static string DarkMetalMat => Dir + "/M_DarkMetal.mat";
        internal static string BodyClothMat => Dir + "/M_BodyCloth.mat";
        internal static string BodyArmorMat => Dir + "/M_BodyArmor.mat";
        internal static string BodyRustMat => Dir + "/M_BodyRust.mat";
        internal static string NeonCyanMat => Dir + "/M_NeonCyan.mat";
        internal static string NeonMagentaMat => Dir + "/M_NeonMagenta.mat";
        internal static string NeonYellowMat => Dir + "/M_NeonYellow.mat";
        internal static string NeonRedMat => Dir + "/M_NeonRed.mat";
        internal static string WindowWarmMat => Dir + "/M_WindowWarm.mat";

        [MenuItem("Tools/Wolf/Photoreal/Regenerate Textures + Materials")]
        internal static void GenerateAll()
        {
            EnsureFolder();

            // --- asphalt: dark, fine grain, smooth puddle blobs in the mask alpha
            string asphaltAlbedo = SaveTexture("T_Asphalt_Albedo", true, false, (u, v) =>
            {
                float g = 0.045f + Fbm(u, v, 5, 26f, 11) * 0.05f + Fbm(u, v, 3, 5f, 12) * 0.02f;
                return new Color(g, g, g * 1.08f, 1f);
            });
            string asphaltNormal = SaveNormal("T_Asphalt_Normal", (u, v) => Fbm(u, v, 5, 40f, 21) * 0.6f);
            string asphaltMask = SaveTexture("T_Asphalt_Mask", false, false, (u, v) =>
            {
                float puddle = Mathf.SmoothStep(0.62f, 0.72f, Fbm(u, v, 3, 4.5f, 31));
                float ao = 0.75f + Fbm(u, v, 4, 22f, 41) * 0.25f;
                float smooth = Mathf.Lerp(0.3f, 0.94f, puddle);
                return new Color(0f, ao, 0.5f, smooth); // HDRP mask: R metal, G AO, B detail, A smoothness
            });

            // --- concrete: mid gray with vertical weather streaks
            string concreteAlbedo = SaveTexture("T_Concrete_Albedo", true, false, (u, v) =>
            {
                float g = 0.30f + Fbm(u, v, 5, 14f, 51) * 0.10f - Fbm(u, 0f, 3, 9f, 52) * v * 0.08f;
                return new Color(g, g * 0.99f, g * 0.96f, 1f);
            });
            string concreteNormal = SaveNormal("T_Concrete_Normal", (u, v) => Fbm(u, v, 5, 18f, 61) * 0.5f);
            string concreteMask = SaveTexture("T_Concrete_Mask", false, false, (u, v) =>
            {
                float ao = 0.7f + Fbm(u, v, 4, 16f, 71) * 0.3f;
                return new Color(0f, ao, 0.5f, 0.16f + Fbm(u, v, 3, 30f, 72) * 0.08f);
            });

            // --- metal panels: brushed, scratched, half-metallic mask
            string metalAlbedo = SaveTexture("T_Metal_Albedo", true, false, (u, v) =>
            {
                float g = 0.28f + Fbm(u * 6f, v, 4, 8f, 81) * 0.10f;
                return new Color(g * 0.95f, g, g * 1.1f, 1f);
            });
            string metalNormal = SaveNormal("T_Metal_Normal", (u, v) => Fbm(u * 6f, v, 4, 10f, 91) * 0.35f);
            string metalMask = SaveTexture("T_Metal_Mask", false, false, (u, v) =>
            {
                float scratches = Mathf.Clamp01(Fbm(u * 8f, v * 0.7f, 4, 12f, 95));
                return new Color(1f, 0.85f + scratches * 0.15f, 0.5f, 0.55f + scratches * 0.2f);
            });

            // --- surface materials
            LitMaterial(AsphaltMat, new Color(0.9f, 0.9f, 0.95f), asphaltAlbedo, asphaltNormal, asphaltMask, 0.55f, 0f, new Vector2(14f, 10f));
            LitMaterial(ConcreteMat, Color.white, concreteAlbedo, concreteNormal, concreteMask, 0.16f, 0f, new Vector2(2.5f, 2.5f));
            LitMaterial(MetalMat, Color.white, metalAlbedo, metalNormal, metalMask, 0.6f, 1f, new Vector2(1.5f, 1.5f));
            LitMaterial(DarkMetalMat, new Color(0.35f, 0.37f, 0.42f), metalAlbedo, metalNormal, metalMask, 0.5f, 1f, new Vector2(2f, 2f));

            // --- mannequin bodies (plain lit, tinted per faction at attach time)
            LitMaterial(BodyClothMat, new Color(0.16f, 0.19f, 0.22f), null, null, null, 0.3f, 0f, Vector2.one);
            LitMaterial(BodyArmorMat, new Color(0.16f, 0.22f, 0.18f), metalAlbedo, metalNormal, metalMask, 0.5f, 0.7f, Vector2.one);
            LitMaterial(BodyRustMat, new Color(0.30f, 0.16f, 0.14f), concreteAlbedo, concreteNormal, null, 0.35f, 0.2f, Vector2.one);

            // --- emissives (neon). HDRP takes nits; fallbacks take HDR color.
            EmissiveMaterial(NeonCyanMat, new Color(0f, 0.9f, 1f), 1600f);
            EmissiveMaterial(NeonMagentaMat, new Color(1f, 0.18f, 0.58f), 1600f);
            EmissiveMaterial(NeonYellowMat, new Color(0.96f, 0.88f, 0.3f), 1400f);
            EmissiveMaterial(NeonRedMat, new Color(1f, 0.13f, 0.13f), 1500f);
            EmissiveMaterial(WindowWarmMat, new Color(1f, 0.75f, 0.45f), 500f);

            AssetDatabase.SaveAssets();
            Debug.Log("[Wolf] Photoreal textures + materials generated under " + Dir);
        }

        internal static Material Load(string path) => AssetDatabase.LoadAssetAtPath<Material>(path);

        // ------------------------------------------------------------------
        // materials
        // ------------------------------------------------------------------

        private static Shader PickLitShader()
        {
            Shader s = Shader.Find("HDRP/Lit");
            if (s == null) s = Shader.Find("Universal Render Pipeline/Lit");
            if (s == null) s = Shader.Find("Standard");
            return s;
        }

        private static Material GetOrCreate(string path)
        {
            Material mat = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (mat == null)
            {
                mat = new Material(PickLitShader());
                AssetDatabase.CreateAsset(mat, path);
            }
            else
            {
                mat.shader = PickLitShader();
            }
            return mat;
        }

        private static void LitMaterial(string path, Color tint, string albedoPath, string normalPath, string maskPath, float smoothness, float metallic, Vector2 tiling)
        {
            Material mat = GetOrCreate(path);
            Texture2D albedo = albedoPath != null ? AssetDatabase.LoadAssetAtPath<Texture2D>(albedoPath) : null;
            Texture2D normal = normalPath != null ? AssetDatabase.LoadAssetAtPath<Texture2D>(normalPath) : null;
            Texture2D mask = maskPath != null ? AssetDatabase.LoadAssetAtPath<Texture2D>(maskPath) : null;

            mat.color = tint; // maps to _BaseColor (HDRP/URP) or _Color (Standard) via [MainColor]
            mat.mainTextureScale = tiling;

            if (mat.HasProperty("_BaseColorMap")) // HDRP
            {
                mat.SetTexture("_BaseColorMap", albedo);
                mat.SetTexture("_NormalMap", normal);
                mat.SetTexture("_MaskMap", mask);
                mat.SetFloat("_Smoothness", smoothness);
                mat.SetFloat("_Metallic", metallic);
            }
            else if (mat.HasProperty("_BaseMap")) // URP
            {
                mat.SetTexture("_BaseMap", albedo);
                mat.SetTexture("_BumpMap", normal);
                mat.SetFloat("_Smoothness", smoothness);
                mat.SetFloat("_Metallic", metallic);
                if (normal != null) mat.EnableKeyword("_NORMALMAP");
            }
            else // Standard
            {
                mat.SetTexture("_MainTex", albedo);
                mat.SetTexture("_BumpMap", normal);
                mat.SetFloat("_Glossiness", smoothness);
                mat.SetFloat("_Metallic", metallic);
                if (normal != null) mat.EnableKeyword("_NORMALMAP");
            }

            Validate(mat);
            EditorUtility.SetDirty(mat);
        }

        private static void EmissiveMaterial(string path, Color color, float nits)
        {
            Material mat = GetOrCreate(path);
            mat.color = color;

            if (mat.HasProperty("_EmissiveColor")) // HDRP: emission in physical units
            {
                mat.SetColor("_EmissiveColor", color.linear * nits);
                mat.SetFloat("_Smoothness", 0.2f);
            }
            else // URP/Standard share the emission convention
            {
                mat.EnableKeyword("_EMISSION");
                mat.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                mat.SetColor("_EmissionColor", color * 3.2f);
            }

            Validate(mat);
            EditorUtility.SetDirty(mat);
        }

        private static void Validate(Material mat)
        {
#if WOLF_HDRP
            // Fixes HDRP keyword state after raw property writes.
            UnityEditor.Rendering.HighDefinition.HDMaterial.ValidateMaterial(mat);
#endif
        }

        // ------------------------------------------------------------------
        // procedural textures
        // ------------------------------------------------------------------

        private static float Fbm(float u, float v, int octaves, float scale, int seed)
        {
            float sum = 0f, amp = 0.5f, freq = scale;
            for (int i = 0; i < octaves; i++)
            {
                sum += Mathf.PerlinNoise(u * freq + seed * 17.31f, v * freq + seed * 9.77f) * amp;
                amp *= 0.5f;
                freq *= 2.02f;
            }
            return sum;
        }

        private static string SaveTexture(string name, bool sRGB, bool asNormal, System.Func<float, float, Color> shade)
        {
            var px = new Color[TexSize * TexSize];
            for (int y = 0; y < TexSize; y++)
            {
                float v = (float)y / TexSize;
                for (int x = 0; x < TexSize; x++)
                {
                    px[y * TexSize + x] = shade((float)x / TexSize, v);
                }
            }

            var tex = new Texture2D(TexSize, TexSize, TextureFormat.RGBA32, false);
            tex.SetPixels(px);
            tex.Apply();
            byte[] bytes = tex.EncodeToPNG();
            Object.DestroyImmediate(tex);

            string path = $"{Dir}/{name}.png";
            File.WriteAllBytes(path, bytes);
            AssetDatabase.ImportAsset(path);

            var importer = (TextureImporter)AssetImporter.GetAtPath(path);
            importer.sRGBTexture = sRGB;
            importer.wrapMode = TextureWrapMode.Repeat;
            if (asNormal) importer.textureType = TextureImporterType.NormalMap;
            importer.SaveAndReimport();
            return path;
        }

        /// <summary>Sobel-derives a tangent normal map from a heightfield lambda.</summary>
        private static string SaveNormal(string name, System.Func<float, float, float> height)
        {
            const float step = 1f / TexSize;
            return SaveTexture(name, false, true, (u, v) =>
            {
                float hx = height(u + step, v) - height(u - step, v);
                float hy = height(u, v + step) - height(u, v - step);
                Vector3 n = new Vector3(-hx * 6f, -hy * 6f, 1f).normalized;
                return new Color(n.x * 0.5f + 0.5f, n.y * 0.5f + 0.5f, n.z * 0.5f + 0.5f, 1f);
            });
        }

        private static void EnsureFolder()
        {
            if (!AssetDatabase.IsValidFolder(Dir))
            {
                Directory.CreateDirectory(Dir);
                AssetDatabase.Refresh();
            }
        }
    }
}
