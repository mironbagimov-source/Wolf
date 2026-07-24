using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.UI;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Visuals;
#if WOLF_HDRP
using UnityEngine.Rendering.HighDefinition;
#endif

namespace Wolf.EditorTools
{
    /// <summary>
    /// Builds the photoreal night-district gameplay scene (saved as
    /// TourBase.unity so the Lobby loads it unchanged): wet-asphalt streets,
    /// neon-trimmed concrete blocks, a tower skyline, barrel fires, hack
    /// nodes / implant table / exit gate, spawn points, HUD, and — when HDRP
    /// is installed (see docs/unity-photoreal-setup.md) — volumetric fog,
    /// bloom, ACES tonemapping, auto-exposure, gradient night sky and
    /// reflection probes that sell the rain-slick look. Without HDRP the same
    /// scene builds with classic fog as a graceful fallback.
    /// </summary>
    internal static class NightDistrictBuilder
    {
        private const string SceneDir = "Assets/_Project/Scenes";
        private const string VolumeProfilePath = PhotorealForge.Dir + "/NightVolume.asset";

        [MenuItem("Tools/Wolf/Build Night District (Photoreal)")]
        public static void BuildNightDistrict()
        {
            PhotorealForge.GenerateAll();
            WolfProjectBuilder.BuildPrefabs();
            BuildScene();
        }

        internal static void BuildScene()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var rng = new System.Random(1337);

            BuildEnvironmentLighting();
            BuildGround();
            BuildTowerSkyline(rng);
            BuildInnerBlocks();
            BuildProps(rng);
            BuildReflectionProbes();
            BuildGameplay();
            BuildHud();

            EditorSceneManager.SaveScene(scene, $"{SceneDir}/TourBase.unity");
            Debug.Log("[Wolf] Night district built and saved over TourBase.unity — open the Lobby scene and press Play.");
        }

        // ------------------------------------------------------------------
        // lighting / atmosphere
        // ------------------------------------------------------------------

        private static void BuildEnvironmentLighting()
        {
            // Moonlight — cold, low, soft-shadowed.
            var moonGO = new GameObject("Moon");
            moonGO.transform.rotation = Quaternion.Euler(48f, -145f, 0f);
            Light moon = moonGO.AddComponent<Light>();
            moon.type = LightType.Directional;
            moon.color = new Color(0.62f, 0.71f, 0.88f);
            moon.shadows = LightShadows.Soft;
            moon.intensity = 0.35f;
#if WOLF_HDRP
            var hdMoon = moonGO.AddComponent<HDAdditionalLightData>();
            hdMoon.intensity = 1.5f; // lux (directional default unit)

            BuildHdrpVolume();
#else
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Exponential;
            RenderSettings.fogDensity = 0.022f;
            RenderSettings.fogColor = new Color(0.04f, 0.03f, 0.08f);
            RenderSettings.ambientMode = AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.05f, 0.07f, 0.12f);
#endif
        }

#if WOLF_HDRP
        private static void BuildHdrpVolume()
        {
            // Fresh profile each build so re-runs never stack duplicate overrides.
            AssetDatabase.DeleteAsset(VolumeProfilePath);
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            AssetDatabase.CreateAsset(profile, VolumeProfilePath);

            var env = profile.Add<VisualEnvironment>(true);
            env.skyType.Override((int)SkyType.Gradient);

            var sky = profile.Add<GradientSky>(true);
            sky.top.Override(new Color(0.020f, 0.027f, 0.059f));
            sky.middle.Override(new Color(0.051f, 0.039f, 0.102f));
            sky.bottom.Override(new Color(0.102f, 0.063f, 0.188f));

            var fog = profile.Add<Fog>(true);
            fog.enabled.Override(true);
            fog.enableVolumetricFog.Override(true);
            fog.meanFreePath.Override(38f);
            fog.baseHeight.Override(0f);
            fog.maximumHeight.Override(30f);
            fog.albedo.Override(new Color(0.54f, 0.48f, 0.72f));
            fog.anisotropy.Override(0.35f);

            var exposure = profile.Add<Exposure>(true);
            exposure.mode.Override(ExposureMode.Automatic);
            exposure.limitMin.Override(3.5f);
            exposure.limitMax.Override(8.5f);
            exposure.compensation.Override(0.3f);

            var bloom = profile.Add<Bloom>(true);
            bloom.intensity.Override(0.38f);
            bloom.scatter.Override(0.65f);

            var tone = profile.Add<Tonemapping>(true);
            tone.mode.Override(TonemappingMode.ACES);

            var vignette = profile.Add<Vignette>(true);
            vignette.intensity.Override(0.26f);

            // SSR / SSAO class names have shifted across HDRP majors, so these
            // are added reflectively and skipped silently when absent.
            TryAddReflective(profile, "ScreenSpaceReflection", ("enabled", (object)true));
            TryAddReflective(profile, "ScreenSpaceAmbientOcclusion", ("intensity", (object)1.2f));
            TryAddReflective(profile, "AmbientOcclusion", ("intensity", (object)1.2f));

            EditorUtility.SetDirty(profile);
            AssetDatabase.SaveAssets();

            var volumeGO = new GameObject("Sky and Fog Volume");
            var volume = volumeGO.AddComponent<Volume>();
            volume.isGlobal = true;
            volume.sharedProfile = profile;
        }

        private static void TryAddReflective(VolumeProfile profile, string shortName, params (string field, object value)[] settings)
        {
            var type = System.Type.GetType(
                $"UnityEngine.Rendering.HighDefinition.{shortName}, Unity.RenderPipelines.HighDefinition.Runtime");
            if (type == null || !typeof(VolumeComponent).IsAssignableFrom(type) || profile.Has(type))
            {
                return;
            }

            VolumeComponent component = profile.Add(type, true);
            foreach ((string field, object value) in settings)
            {
                var f = type.GetField(field);
                if (f == null) continue;
                object parameter = f.GetValue(component);
                if (parameter == null) continue;
                var overrideProp = parameter.GetType().GetProperty("overrideState");
                var valueProp = parameter.GetType().GetProperty("value");
                if (overrideProp == null || valueProp == null) continue;
                overrideProp.SetValue(parameter, true);
                valueProp.SetValue(parameter, value);
            }
        }
#endif

        // ------------------------------------------------------------------
        // geometry
        // ------------------------------------------------------------------

        private static void BuildGround()
        {
            GameObject ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Street";
            ground.transform.localScale = new Vector3(7f, 1f, 5f); // 70 x 50 m
            SetMat(ground, PhotorealForge.AsphaltMat);
        }

        private static void BuildTowerSkyline(System.Random rng)
        {
            var parent = new GameObject("Skyline").transform;
            string[] neon = { PhotorealForge.NeonCyanMat, PhotorealForge.NeonMagentaMat, PhotorealForge.WindowWarmMat };

            for (int i = 0; i < 30; i++)
            {
                // Ring the playfield: pick an edge, then a slot along it.
                bool alongX = rng.NextDouble() < 0.55;
                float x = alongX ? Range(rng, -34f, 34f) : (rng.NextDouble() < 0.5 ? -1f : 1f) * Range(rng, 33f, 38f);
                float z = alongX ? (rng.NextDouble() < 0.5 ? -1f : 1f) * Range(rng, 24f, 29f) : Range(rng, -24f, 24f);
                if (Mathf.Abs(x) < 6f && z > 20f) continue; // keep the exit corridor clear

                float h = Range(rng, 16f, 42f);
                float w = Range(rng, 3f, 6f);
                GameObject slab = GameObject.CreatePrimitive(PrimitiveType.Cube);
                slab.name = "Tower";
                slab.transform.SetParent(parent, false);
                slab.transform.position = new Vector3(x, h / 2f, z);
                slab.transform.localScale = new Vector3(w, h, w);
                SetMat(slab, PhotorealForge.ConcreteMat);

                if (rng.NextDouble() < 0.55)
                {
                    GameObject strip = GameObject.CreatePrimitive(PrimitiveType.Cube);
                    strip.name = "WindowStrip";
                    strip.transform.SetParent(parent, false);
                    strip.transform.position = new Vector3(x + w * 0.45f, h * 0.55f, z + w * 0.45f);
                    strip.transform.localScale = new Vector3(0.14f, h * 0.7f, 0.14f);
                    Object.DestroyImmediate(strip.GetComponent<Collider>());
                    SetMat(strip, neon[rng.Next(neon.Length)]);
                }
            }

            // Corporate holo-billboard looming over the block.
            GameObject billboard = GameObject.CreatePrimitive(PrimitiveType.Cube);
            billboard.name = "HoloBillboard";
            billboard.transform.position = new Vector3(-26f, 22f, -20f);
            billboard.transform.localScale = new Vector3(7f, 4f, 0.2f);
            billboard.transform.rotation = Quaternion.LookRotation(new Vector3(26f, -14f, 20f));
            Object.DestroyImmediate(billboard.GetComponent<Collider>());
            SetMat(billboard, PhotorealForge.NeonMagentaMat);
        }

        private static void BuildInnerBlocks()
        {
            var parent = new GameObject("Blocks").transform;
            // (cx, cz, width, depth, height) — leaves a central plaza, two
            // avenues and alleys between blocks.
            float[][] blocks =
            {
                new[] { -15f, 8f, 12f, 8f, 7f },
                new[] { 15f, -8f, 12f, 8f, 9f },
                new[] { -17f, -11f, 8f, 6f, 6f },
                new[] { 17f, 11f, 8f, 6f, 8f },
                new[] { -6f, -14f, 8f, 5f, 5.5f },
                new[] { 8f, 14f, 9f, 5f, 6.5f },
            };

            for (int i = 0; i < blocks.Length; i++)
            {
                float cx = blocks[i][0], cz = blocks[i][1], w = blocks[i][2], d = blocks[i][3], h = blocks[i][4];
                string neonMat = i % 2 == 0 ? PhotorealForge.NeonMagentaMat : PhotorealForge.NeonCyanMat;
                Color neonColor = i % 2 == 0 ? new Color(1f, 0.18f, 0.58f) : new Color(0f, 0.9f, 1f);

                GameObject building = GameObject.CreatePrimitive(PrimitiveType.Cube);
                building.name = "Block";
                building.transform.SetParent(parent, false);
                building.transform.position = new Vector3(cx, h / 2f, cz);
                building.transform.localScale = new Vector3(w, h, d);
                SetMat(building, PhotorealForge.ConcreteMat);

                // Roofline neon band wrapping the block.
                GameObject trim = GameObject.CreatePrimitive(PrimitiveType.Cube);
                trim.name = "NeonTrim";
                trim.transform.SetParent(parent, false);
                trim.transform.position = new Vector3(cx, h - 0.5f, cz);
                trim.transform.localScale = new Vector3(w + 0.12f, 0.12f, d + 0.12f);
                Object.DestroyImmediate(trim.GetComponent<Collider>());
                SetMat(trim, neonMat);

                // Lit doorway on the plaza-facing side + a sign spot washing the wall.
                float face = cz < 0f ? 1f : -1f;
                GameObject door = GameObject.CreatePrimitive(PrimitiveType.Cube);
                door.name = "Doorway";
                door.transform.SetParent(parent, false);
                door.transform.position = new Vector3(cx, 1.0f, cz + face * (d / 2f + 0.04f));
                door.transform.localScale = new Vector3(0.7f, 2.0f, 0.06f);
                Object.DestroyImmediate(door.GetComponent<Collider>());
                SetMat(door, neonMat);

                var signGO = new GameObject("SignLight");
                signGO.transform.SetParent(parent, false);
                signGO.transform.position = new Vector3(cx, h - 0.6f, cz + face * (d / 2f + 1.1f));
                signGO.transform.rotation = Quaternion.LookRotation(new Vector3(0f, -1f, -face * 0.35f));
                Light sign = signGO.AddComponent<Light>();
                sign.type = LightType.Spot;
                sign.color = neonColor;
                sign.range = 14f;
                sign.spotAngle = 74f;
                sign.intensity = 2.6f;
#if WOLF_HDRP
                signGO.AddComponent<HDAdditionalLightData>().intensity = 6500f; // lumen
#endif
            }
        }

        private static void BuildProps(System.Random rng)
        {
            var parent = new GameObject("Props").transform;

            float[][] cratePos = { new[] { -9f, 3f }, new[] { 10f, 4f }, new[] { -3f, 17f }, new[] { 22f, -2f }, new[] { -22f, 2f }, new[] { 4f, -8f }, new[] { 12f, 18f }, new[] { -12f, -17f } };
            foreach (float[] p in cratePos)
            {
                float s = Range(rng, 0.7f, 1.2f);
                GameObject crate = GameObject.CreatePrimitive(PrimitiveType.Cube);
                crate.name = "Crate";
                crate.transform.SetParent(parent, false);
                crate.transform.position = new Vector3(p[0], s / 2f, p[1]);
                crate.transform.localScale = Vector3.one * s;
                crate.transform.rotation = Quaternion.Euler(0f, (float)rng.NextDouble() * 90f, 0f);
                SetMat(crate, PhotorealForge.ConcreteMat);
            }

            float[][] barrierPos = { new[] { -5f, 6f, 20f }, new[] { 6f, -3f, 70f }, new[] { 18f, 6f, 0f }, new[] { -19f, -4f, 90f } };
            foreach (float[] p in barrierPos)
            {
                GameObject barrier = GameObject.CreatePrimitive(PrimitiveType.Cube);
                barrier.name = "Barrier";
                barrier.transform.SetParent(parent, false);
                barrier.transform.position = new Vector3(p[0], 0.25f, p[1]);
                barrier.transform.localScale = new Vector3(1.6f, 0.5f, 0.4f);
                barrier.transform.rotation = Quaternion.Euler(0f, p[2], 0f);
                SetMat(barrier, PhotorealForge.ConcreteMat);
            }

            float[][] dumpsterPos = { new[] { -13f, 13f }, new[] { 14f, -13f } };
            foreach (float[] p in dumpsterPos)
            {
                GameObject dumpster = GameObject.CreatePrimitive(PrimitiveType.Cube);
                dumpster.name = "Dumpster";
                dumpster.transform.SetParent(parent, false);
                dumpster.transform.position = new Vector3(p[0], 0.45f, p[1]);
                dumpster.transform.localScale = new Vector3(1.8f, 0.9f, 1.0f);
                SetMat(dumpster, PhotorealForge.DarkMetalMat);
            }

            // Burning barrels — the warm anchors in the cold neon night.
            float[][] firePos = { new[] { -8f, 10f }, new[] { 6f, -11f }, new[] { 20f, 2f } };
            foreach (float[] p in firePos)
            {
                GameObject barrel = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                barrel.name = "FireBarrel";
                barrel.transform.SetParent(parent, false);
                barrel.transform.position = new Vector3(p[0], 0.55f, p[1]);
                barrel.transform.localScale = new Vector3(0.5f, 0.55f, 0.5f);
                SetMat(barrel, PhotorealForge.MetalMat);

                GameObject core = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
                core.name = "FireCore";
                Object.DestroyImmediate(core.GetComponent<Collider>());
                core.transform.SetParent(barrel.transform, false);
                core.transform.localPosition = new Vector3(0f, 1.05f, 0f);
                core.transform.localScale = new Vector3(0.75f, 0.12f, 0.75f);
                SetMat(core, PhotorealForge.NeonYellowMat);

                var fireGO = new GameObject("FireLight");
                fireGO.transform.SetParent(barrel.transform, false);
                fireGO.transform.localPosition = new Vector3(0f, 1.8f, 0f);
                Light fire = fireGO.AddComponent<Light>();
                fire.type = LightType.Point;
                fire.color = new Color(1f, 0.55f, 0.22f);
                fire.range = 11f;
                fire.intensity = 2.4f;
#if WOLF_HDRP
                fireGO.AddComponent<HDAdditionalLightData>().intensity = 4200f; // lumen
#endif
                fireGO.AddComponent<FlickerLight>();
            }
        }

        private static void BuildReflectionProbes()
        {
            var parent = new GameObject("ReflectionProbes").transform;
            float[][] probes = { new[] { 0f, 4f, 0f, 36f, 14f, 30f }, new[] { -18f, 4f, 0f, 20f, 12f, 40f }, new[] { 18f, 4f, 0f, 20f, 12f, 40f } };
            foreach (float[] p in probes)
            {
                var go = new GameObject("Probe");
                go.transform.SetParent(parent, false);
                go.transform.position = new Vector3(p[0], p[1], p[2]);
                var probe = go.AddComponent<ReflectionProbe>();
                probe.mode = ReflectionProbeMode.Realtime;
                probe.refreshMode = ReflectionProbeRefreshMode.OnAwake;
                probe.size = new Vector3(p[3], p[4], p[5]);
                probe.boxProjection = true;
#if WOLF_HDRP
                go.AddComponent<HDAdditionalReflectionData>();
#endif
            }
        }

        // ------------------------------------------------------------------
        // gameplay wiring
        // ------------------------------------------------------------------

        private static void BuildGameplay()
        {
            var gmGO = new GameObject("GameManager");
            GameManager gm = gmGO.AddComponent<GameManager>();
            var gmSo = new SerializedObject(gm);
            gmSo.FindProperty("settings").objectReferenceValue = WolfProjectBuilder.GetOrCreateMatchSettings();
            gmSo.ApplyModifiedProperties();

            var bootstrapGO = new GameObject("MatchBootstrapper");
            MatchBootstrapper bootstrapper = bootstrapGO.AddComponent<MatchBootstrapper>();
            WolfProjectBuilder.WireBootstrapperPrefabs(bootstrapper);

            SpawnPointAt("SurvivorSpawn_1", FactionType.Survivor, new Vector3(-26f, 1f, -8f));
            SpawnPointAt("SurvivorSpawn_2", FactionType.Survivor, new Vector3(-26f, 1f, 0f));
            SpawnPointAt("SurvivorSpawn_3", FactionType.Survivor, new Vector3(-26f, 1f, 8f));
            SpawnPointAt("CannibalSpawn_1", FactionType.Cannibal, new Vector3(26f, 1f, -8f));
            SpawnPointAt("CannibalSpawn_2", FactionType.Cannibal, new Vector3(26f, 1f, 0f));
            SpawnPointAt("CannibalSpawn_3", FactionType.Cannibal, new Vector3(26f, 1f, 8f));
            SpawnPointAt("KillerSpawn_1", FactionType.Killer, new Vector3(0f, 1f, -21f));
            SpawnPointAt("KillerSpawn_2", FactionType.Killer, new Vector3(-2.5f, 1f, -21f));
            SpawnPointAt("KillerSpawn_3", FactionType.Killer, new Vector3(2.5f, 1f, -21f));

            HackNodeAt(new Vector3(-20f, 0f, 14f));
            HackNodeAt(new Vector3(20f, 0f, -14f));
            HackNodeAt(new Vector3(0f, 0f, -17f));

            ImplantTableAt(Vector3.zero);
            ExitGateAt(new Vector3(0f, 1.6f, 23f));
        }

        private static void SpawnPointAt(string name, FactionType faction, Vector3 pos)
        {
            var go = new GameObject(name);
            go.transform.position = pos;
            go.transform.rotation = Quaternion.LookRotation(new Vector3(-pos.x, 0f, -pos.z).normalized);
            go.AddComponent<SpawnPoint>().faction = faction;
        }

        private static void HackNodeAt(Vector3 pos)
        {
            GameObject node = GameObject.CreatePrimitive(PrimitiveType.Cube);
            node.name = "HackNode";
            node.transform.position = pos + new Vector3(0f, 0.6f, 0f);
            node.transform.localScale = new Vector3(1.1f, 1.2f, 0.8f);
            SetMat(node, PhotorealForge.MetalMat);
            node.AddComponent<GeneratorObjective>();

            GameObject ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            ring.name = "NodeRing";
            Object.DestroyImmediate(ring.GetComponent<Collider>());
            ring.transform.SetParent(node.transform, false);
            // Counter the node's non-uniform scale so the ring stays round.
            ring.transform.localScale = new Vector3(1.8f / 1.1f, 0.04f / 1.2f, 1.8f / 0.8f);
            ring.transform.localPosition = new Vector3(0f, -0.47f, 0f);
            SetMat(ring, PhotorealForge.NeonCyanMat);

            var lightGO = new GameObject("NodeLight");
            lightGO.transform.SetParent(node.transform, false);
            lightGO.transform.localPosition = new Vector3(0f, 0.8f, 0f);
            Light l = lightGO.AddComponent<Light>();
            l.type = LightType.Point;
            l.color = new Color(0f, 0.9f, 1f);
            l.range = 6f;
            l.intensity = 1.6f;
#if WOLF_HDRP
            lightGO.AddComponent<HDAdditionalLightData>().intensity = 1400f;
#endif
        }

        private static void ImplantTableAt(Vector3 pos)
        {
            GameObject table = GameObject.CreatePrimitive(PrimitiveType.Cube);
            table.name = "ImplantTable";
            table.transform.position = pos + new Vector3(0f, 0.4f, 0f);
            table.transform.localScale = new Vector3(2.2f, 0.8f, 1.0f);
            SetMat(table, PhotorealForge.DarkMetalMat);

            var box = table.GetComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = new Vector3(1.5f, 4f, 2.6f); // generous catch volume for carriers walking in

            GameObject edge = GameObject.CreatePrimitive(PrimitiveType.Cube);
            edge.name = "TableGlow";
            Object.DestroyImmediate(edge.GetComponent<Collider>());
            edge.transform.SetParent(table.transform, false);
            edge.transform.localScale = new Vector3(1.05f, 0.08f, 1.12f);
            edge.transform.localPosition = new Vector3(0f, 0.55f, 0f);
            SetMat(edge, PhotorealForge.NeonRedMat);

            var lightGO = new GameObject("TableLight");
            lightGO.transform.SetParent(table.transform, false);
            lightGO.transform.localPosition = new Vector3(0f, 1.6f, 0f);
            Light l = lightGO.AddComponent<Light>();
            l.type = LightType.Point;
            l.color = new Color(1f, 0.15f, 0.2f);
            l.range = 8f;
            l.intensity = 1.8f;
#if WOLF_HDRP
            lightGO.AddComponent<HDAdditionalLightData>().intensity = 1900f;
#endif

            var sacrificePointGO = new GameObject("SacrificePoint");
            sacrificePointGO.transform.SetParent(table.transform, false);
            sacrificePointGO.transform.localPosition = new Vector3(0f, 1.1f, 0f);

            RitualAltarObjective altar = table.AddComponent<RitualAltarObjective>();
            var so = new SerializedObject(altar);
            so.FindProperty("sacrificePoint").objectReferenceValue = sacrificePointGO.transform;
            so.ApplyModifiedProperties();
        }

        private static void ExitGateAt(Vector3 pos)
        {
            GameObject gate = GameObject.CreatePrimitive(PrimitiveType.Cube);
            gate.name = "ExitGate";
            gate.transform.position = pos;
            gate.transform.localScale = new Vector3(6f, 3.2f, 1f);
            gate.GetComponent<Collider>().isTrigger = true;
            gate.GetComponent<MeshRenderer>().enabled = false; // pure trigger volume
            gate.AddComponent<ExitGateTrigger>();

            for (int side = -1; side <= 1; side += 2)
            {
                GameObject post = GameObject.CreatePrimitive(PrimitiveType.Cube);
                post.name = "GatePost";
                post.transform.position = pos + new Vector3(side * 3.4f, 0.1f, 0f);
                post.transform.localScale = new Vector3(0.3f, 3.4f, 0.3f);
                SetMat(post, PhotorealForge.NeonCyanMat);
            }
        }

        // ------------------------------------------------------------------
        // hud
        // ------------------------------------------------------------------

        private static void BuildHud()
        {
            var canvasGO = new GameObject("HUD");
            Canvas canvas = canvasGO.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            CanvasScaler scaler = canvasGO.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);

            Font font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            Text health = HudLabel(canvasGO.transform, "HealthText", font, 26, TextAnchor.UpperLeft,
                new Vector2(0f, 1f), new Vector2(24f, -20f), new Vector2(420f, 40f));
            Text stance = HudLabel(canvasGO.transform, "StanceText", font, 20, TextAnchor.UpperLeft,
                new Vector2(0f, 1f), new Vector2(24f, -58f), new Vector2(420f, 32f));
            stance.color = new Color(0f, 0.9f, 1f);
            Text nodes = HudLabel(canvasGO.transform, "NodesText", font, 26, TextAnchor.UpperRight,
                new Vector2(1f, 1f), new Vector2(-24f, -20f), new Vector2(420f, 40f));
            Text banner = HudLabel(canvasGO.transform, "ResultBanner", font, 52, TextAnchor.MiddleCenter,
                new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(1400f, 90f));

            var hud = canvasGO.AddComponent<Wolf.UI.HUDController>();
            var so = new SerializedObject(hud);
            so.FindProperty("healthText").objectReferenceValue = health;
            so.FindProperty("stanceText").objectReferenceValue = stance;
            so.FindProperty("generatorText").objectReferenceValue = nodes;
            so.FindProperty("resultBanner").objectReferenceValue = banner;
            so.ApplyModifiedProperties();
        }

        private static Text HudLabel(Transform parent, string name, Font font, int size, TextAnchor align, Vector2 anchor, Vector2 pos, Vector2 dims)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            var rt = go.GetComponent<RectTransform>();
            rt.anchorMin = anchor;
            rt.anchorMax = anchor;
            rt.pivot = anchor;
            rt.anchoredPosition = pos;
            rt.sizeDelta = dims;

            Text label = go.AddComponent<Text>();
            label.font = font;
            label.fontSize = size;
            label.alignment = align;
            label.color = new Color(0.86f, 0.93f, 1f);
            return label;
        }

        // ------------------------------------------------------------------
        // shared
        // ------------------------------------------------------------------

        private static void SetMat(GameObject go, string materialPath)
        {
            Material mat = PhotorealForge.Load(materialPath);
            if (mat != null)
            {
                go.GetComponent<Renderer>().sharedMaterial = mat;
            }
        }

        private static float Range(System.Random rng, float min, float max) => min + (float)rng.NextDouble() * (max - min);
    }
}
