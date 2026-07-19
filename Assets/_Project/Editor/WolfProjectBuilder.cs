using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using Wolf.AI;
using Wolf.Core;
using Wolf.Health;
using Wolf.Objectives;
using Wolf.Player.Cannibal;
using Wolf.Player.Killer;
using Wolf.Player.Survivor;

namespace Wolf.EditorTools
{
    /// <summary>
    /// One-click generation of everything that can't be hand-authored as text
    /// from outside the Editor: placeholder (capsule) prefabs, the Lobby
    /// scene, and a blockout TourBase scene wired up to press Play on.
    /// Run "Tools/Wolf/Build Everything" once after importing this project's
    /// scripts — see README.md. Safe to re-run; it overwrites its own output.
    /// </summary>
    public static class WolfProjectBuilder
    {
        private const string PrefabDir = "Assets/_Project/Prefabs";
        private const string SceneDir = "Assets/_Project/Scenes";
        private const string SettingsPath = "Assets/_Project/MatchSettings.asset";

        [MenuItem("Tools/Wolf/Build Everything")]
        public static void BuildEverything()
        {
            BuildPrefabs();
            BuildLobbyScene();
            BuildBootstrapScene();
            Debug.Log("[Wolf] Done — open Assets/_Project/Scenes/Lobby.unity and press Play.");
        }

        [MenuItem("Tools/Wolf/1 Build Placeholder Prefabs")]
        public static void BuildPrefabs()
        {
            EnsureFolder(PrefabDir);

            BuildHumanPrefab("Survivor_Human", typeof(SurvivorController), new Color(0.2f, 0.8f, 0.3f));
            BuildHumanPrefab("Cannibal_Human", typeof(CannibalController), new Color(0.8f, 0.2f, 0.2f));
            BuildHumanPrefab("Killer_Human", typeof(KillerController), new Color(0.2f, 0.5f, 0.9f));

            BuildBotPrefab("Survivor_Bot", typeof(SurvivorController), typeof(SurvivorBotBrain), new Color(0.4f, 0.9f, 0.5f));
            BuildBotPrefab("Cannibal_Bot", typeof(CannibalController), typeof(CannibalBotBrain), new Color(0.9f, 0.4f, 0.4f));

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log("[Wolf] Placeholder prefabs built under " + PrefabDir);
        }

        [MenuItem("Tools/Wolf/2 Build Lobby Scene")]
        public static void BuildLobbyScene()
        {
            EnsureFolder(SceneDir);
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            GameObject esGO = new GameObject("EventSystem");
            esGO.AddComponent<EventSystem>();
            esGO.AddComponent<StandaloneInputModule>();

            GameObject canvasGO = new GameObject("Canvas");
            Canvas canvas = canvasGO.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            CanvasScaler scaler = canvasGO.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            canvasGO.AddComponent<GraphicRaycaster>();

            // "LegacyRuntime.ttf" is Unity's built-in font resource since Arial.ttf
            // was deprecated as a direct lookup (it still exists, just warns).
            Font font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

            Text status = CreateLabel(canvasGO.transform, "StatusText", new Vector2(0f, 400f), font, "Mode: BotMatch   Faction: Survivor");

            Button botBtn = CreateButton(canvasGO.transform, "BotMatchButton", new Vector2(-300f, 250f), font, "Bot Match");
            Button mpBtn = CreateButton(canvasGO.transform, "MultiplayerButton", new Vector2(0f, 250f), font, "Multiplayer");
            Button ssBtn = CreateButton(canvasGO.transform, "SplitscreenButton", new Vector2(300f, 250f), font, "Splitscreen");

            Button survBtn = CreateButton(canvasGO.transform, "SurvivorButton", new Vector2(-300f, 150f), font, "Survivor");
            Button cannBtn = CreateButton(canvasGO.transform, "CannibalButton", new Vector2(0f, 150f), font, "Cannibal");
            Button killBtn = CreateButton(canvasGO.transform, "KillerButton", new Vector2(300f, 150f), font, "Killer");

            Button startBtn = CreateButton(canvasGO.transform, "StartButton", new Vector2(0f, 40f), font, "Start");

            GameObject lobbyGO = new GameObject("LobbyUI");
            var lobby = lobbyGO.AddComponent<Wolf.UI.LobbyUI>();

            var so = new SerializedObject(lobby);
            so.FindProperty("botMatchButton").objectReferenceValue = botBtn;
            so.FindProperty("multiplayerButton").objectReferenceValue = mpBtn;
            so.FindProperty("splitscreenButton").objectReferenceValue = ssBtn;
            so.FindProperty("survivorButton").objectReferenceValue = survBtn;
            so.FindProperty("cannibalButton").objectReferenceValue = cannBtn;
            so.FindProperty("killerButton").objectReferenceValue = killBtn;
            so.FindProperty("startButton").objectReferenceValue = startBtn;
            so.FindProperty("statusText").objectReferenceValue = status;
            so.FindProperty("gameplaySceneName").stringValue = "TourBase";
            so.ApplyModifiedProperties();

            EditorSceneManager.SaveScene(scene, $"{SceneDir}/Lobby.unity");
            Debug.Log("[Wolf] Lobby scene built.");
        }

        [MenuItem("Tools/Wolf/3 Build Bootstrap Scene (TourBase)")]
        public static void BuildBootstrapScene()
        {
            EnsureFolder(SceneDir);
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            GameObject lightGO = new GameObject("Directional Light");
            Light light = lightGO.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 0.4f; // it's meant to be night
            lightGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);

            GameObject ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Ground";
            ground.transform.localScale = new Vector3(10f, 1f, 10f);

            GameObject gmGO = new GameObject("GameManager");
            GameManager gm = gmGO.AddComponent<GameManager>();
            var gmSo = new SerializedObject(gm);
            gmSo.FindProperty("settings").objectReferenceValue = GetOrCreateMatchSettings();
            gmSo.ApplyModifiedProperties();

            GameObject bootstrapGO = new GameObject("MatchBootstrapper");
            MatchBootstrapper bootstrapper = bootstrapGO.AddComponent<MatchBootstrapper>();
            WireBootstrapperPrefabs(bootstrapper);

            CreateSpawnPoint("SurvivorSpawn_1", FactionType.Survivor, new Vector3(-8f, 1f, -5f));
            CreateSpawnPoint("SurvivorSpawn_2", FactionType.Survivor, new Vector3(-8f, 1f, 0f));
            CreateSpawnPoint("SurvivorSpawn_3", FactionType.Survivor, new Vector3(-8f, 1f, 5f));
            CreateSpawnPoint("SurvivorSpawn_4", FactionType.Survivor, new Vector3(-8f, 1f, 10f));
            CreateSpawnPoint("CannibalSpawn_1", FactionType.Cannibal, new Vector3(8f, 1f, -5f));
            CreateSpawnPoint("CannibalSpawn_2", FactionType.Cannibal, new Vector3(8f, 1f, 0f));
            CreateSpawnPoint("CannibalSpawn_3", FactionType.Cannibal, new Vector3(8f, 1f, 5f));
            CreateSpawnPoint("KillerSpawn_1", FactionType.Killer, new Vector3(0f, 1f, 15f));
            CreateSpawnPoint("KillerSpawn_2", FactionType.Killer, new Vector3(2f, 1f, 15f));
            CreateSpawnPoint("KillerSpawn_3", FactionType.Killer, new Vector3(-2f, 1f, 15f));

            CreateGenerator(new Vector3(-10f, 0.5f, -10f));
            CreateGenerator(new Vector3(10f, 0.5f, -10f));
            CreateGenerator(new Vector3(0f, 0.5f, -14f));

            CreateAltar(new Vector3(0f, 0.25f, 0f));
            CreateExitGate(new Vector3(0f, 1.5f, 20f));

            EditorSceneManager.SaveScene(scene, $"{SceneDir}/TourBase.unity");
            Debug.Log("[Wolf] TourBase blockout scene built.");
        }

        // --- prefabs ---

        private static void BuildHumanPrefab(string name, System.Type controllerType, Color color)
        {
            GameObject root = CreateBody(name, controllerType, color);

            GameObject pivotGO = new GameObject("CameraPivot");
            pivotGO.transform.SetParent(root.transform, false);
            pivotGO.transform.localPosition = new Vector3(0f, 0.6f, 0f);
            pivotGO.AddComponent<Camera>();
            pivotGO.AddComponent<AudioListener>();

            var so = new SerializedObject(root.GetComponent(controllerType));
            so.FindProperty("cameraPivot").objectReferenceValue = pivotGO.transform;

            if (controllerType == typeof(CannibalController))
            {
                GameObject carryPointGO = new GameObject("CarryPoint");
                carryPointGO.transform.SetParent(pivotGO.transform, false);
                carryPointGO.transform.localPosition = new Vector3(0f, -0.3f, 1f);
                so.FindProperty("carryPoint").objectReferenceValue = carryPointGO.transform;
            }

            so.ApplyModifiedProperties();
            SaveAsPrefab(root, name);
        }

        private static void BuildBotPrefab(string name, System.Type controllerType, System.Type brainType, Color color)
        {
            GameObject root = CreateBody(name, controllerType, color);
            root.AddComponent(brainType);
            SaveAsPrefab(root, name);
        }

        private static GameObject CreateBody(string name, System.Type controllerType, Color color)
        {
            GameObject root = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            root.name = name;
            Object.DestroyImmediate(root.GetComponent<CapsuleCollider>());
            root.AddComponent(controllerType); // RequireComponent cascades CharacterController + HealthComponent
            ApplyColor(root, color);
            return root;
        }

        private static void ApplyColor(GameObject root, Color color)
        {
            Renderer renderer = root.GetComponent<Renderer>();
            if (renderer == null)
            {
                return;
            }

            Shader shader = Shader.Find("Universal Render Pipeline/Lit");
            if (shader == null)
            {
                shader = Shader.Find("Standard");
            }

            renderer.sharedMaterial = new Material(shader) { color = color };
        }

        private static void SaveAsPrefab(GameObject root, string name)
        {
            PrefabUtility.SaveAsPrefabAsset(root, $"{PrefabDir}/{name}.prefab");
            Object.DestroyImmediate(root);
        }

        // --- scene wiring ---

        private static void WireBootstrapperPrefabs(MatchBootstrapper bootstrapper)
        {
            var so = new SerializedObject(bootstrapper);
            AssignPrefab(so, "survivorHumanPrefab", "Survivor_Human");
            AssignPrefab(so, "cannibalHumanPrefab", "Cannibal_Human");
            AssignPrefab(so, "killerHumanPrefab", "Killer_Human");
            AssignPrefab(so, "survivorBotPrefab", "Survivor_Bot");
            AssignPrefab(so, "cannibalBotPrefab", "Cannibal_Bot");
            so.ApplyModifiedProperties();
        }

        private static void AssignPrefab(SerializedObject so, string fieldName, string prefabName)
        {
            GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>($"{PrefabDir}/{prefabName}.prefab");
            if (prefab == null)
            {
                Debug.LogWarning($"[Wolf] Prefab '{prefabName}' not found — run '1 Build Placeholder Prefabs' first.");
                return;
            }

            so.FindProperty(fieldName).objectReferenceValue = prefab;
        }

        private static void CreateSpawnPoint(string name, FactionType faction, Vector3 pos)
        {
            GameObject go = new GameObject(name) { transform = { position = pos } };
            SpawnPoint sp = go.AddComponent<SpawnPoint>();
            sp.faction = faction;
        }

        private static void CreateGenerator(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "Generator";
            go.transform.position = pos;
            go.transform.localScale = new Vector3(1.5f, 1f, 1f);
            go.AddComponent<GeneratorObjective>();
        }

        private static void CreateAltar(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = "RitualAltar";
            go.transform.position = pos;
            go.transform.localScale = new Vector3(2f, 0.25f, 2f);
            go.GetComponent<Collider>().isTrigger = true;

            GameObject sacrificePointGO = new GameObject("SacrificePoint");
            sacrificePointGO.transform.SetParent(go.transform, false);
            sacrificePointGO.transform.localPosition = new Vector3(0f, 4f, 0f);

            RitualAltarObjective altar = go.AddComponent<RitualAltarObjective>();
            var so = new SerializedObject(altar);
            so.FindProperty("sacrificePoint").objectReferenceValue = sacrificePointGO.transform;
            so.ApplyModifiedProperties();
        }

        private static void CreateExitGate(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "ExitGate";
            go.transform.position = pos;
            go.transform.localScale = new Vector3(4f, 3f, 1f);
            go.GetComponent<Collider>().isTrigger = true;
            go.AddComponent<ExitGateTrigger>();
        }

        // --- shared ---

        private static MatchSettings GetOrCreateMatchSettings()
        {
            MatchSettings settings = AssetDatabase.LoadAssetAtPath<MatchSettings>(SettingsPath);
            if (settings == null)
            {
                settings = ScriptableObject.CreateInstance<MatchSettings>();
                AssetDatabase.CreateAsset(settings, SettingsPath);
                AssetDatabase.SaveAssets();
            }
            return settings;
        }

        private static Text CreateLabel(Transform parent, string name, Vector2 anchoredPos, Font font, string text)
        {
            GameObject go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            RectTransform rt = go.GetComponent<RectTransform>();
            rt.sizeDelta = new Vector2(700f, 50f);
            rt.anchoredPosition = anchoredPos;

            Text label = go.AddComponent<Text>();
            label.font = font;
            label.fontSize = 28;
            label.alignment = TextAnchor.MiddleCenter;
            label.color = Color.white;
            label.text = text;
            return label;
        }

        private static Button CreateButton(Transform parent, string name, Vector2 anchoredPos, Font font, string label)
        {
            GameObject go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            RectTransform rt = go.GetComponent<RectTransform>();
            rt.sizeDelta = new Vector2(250f, 60f);
            rt.anchoredPosition = anchoredPos;

            Image image = go.AddComponent<Image>();
            image.color = new Color(0.15f, 0.15f, 0.15f, 0.9f);

            Button button = go.AddComponent<Button>();

            Text text = CreateLabel(go.transform, "Label", Vector2.zero, font, label);
            text.rectTransform.sizeDelta = rt.sizeDelta;

            return button;
        }

        private static void EnsureFolder(string path)
        {
            if (!AssetDatabase.IsValidFolder(path))
            {
                Directory.CreateDirectory(path);
                AssetDatabase.Refresh();
            }
        }
    }
}
