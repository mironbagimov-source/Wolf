using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;
using Wolf.AI;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Player.Guest;
using Wolf.Player.Killer;

namespace Wolf.EditorTools
{
    /// <summary>
    /// One-click generation of everything that can't be hand-authored as text
    /// from outside the Editor: placeholder (capsule) prefabs, the Lobby scene,
    /// and a blockout of the quarter wired up to press Play on.
    ///
    /// Run "Tools/Wolf/Build Everything" once after importing this project's
    /// scripts — see README.md. Safe to re-run; it overwrites its own output.
    /// The blockout mirrors the browser prototype's layout (web-prototype/) so
    /// the two versions play roughly the same map.
    /// </summary>
    public static class WolfProjectBuilder
    {
        private const string PrefabDir = "Assets/_Project/Prefabs";
        private const string SceneDir = "Assets/_Project/Scenes";
        private const string SettingsPath = "Assets/_Project/MatchSettings.asset";

        private const float WallHeight = 3.3f;
        private const float WallThickness = 0.55f;
        private const float DoorHalfWidth = 1.35f;

        [MenuItem("Tools/Wolf/Build Everything")]
        public static void BuildEverything()
        {
            BuildPrefabs();
            BuildLobbyScene();
            BuildQuarterScene();
            Debug.Log("[Wolf] Done — open Assets/_Project/Scenes/Lobby.unity and press Play.");
        }

        [MenuItem("Tools/Wolf/1 Build Placeholder Prefabs")]
        public static void BuildPrefabs()
        {
            EnsureFolder(PrefabDir);

            BuildThicketPrefab();
            BuildDoublePrefab();

            BuildHumanPrefab("Guest_Human", typeof(GuestController), new Color(0.85f, 0.75f, 0.54f));
            BuildHumanPrefab("Trickster_Human", typeof(TricksterController), new Color(0.82f, 0.25f, 0.35f));
            BuildHumanPrefab("Witch_Human", typeof(WitchController), new Color(0.34f, 0.64f, 0.36f));
            BuildHumanPrefab("Roger_Human", typeof(JollyRogerController), new Color(0.56f, 0.6f, 0.65f));

            BuildBotPrefab("Guest_Bot", typeof(GuestController), typeof(GuestBotBrain), new Color(0.9f, 0.82f, 0.62f));
            BuildBotPrefab("Trickster_Bot", typeof(TricksterController), typeof(KillerBotBrain), new Color(0.9f, 0.35f, 0.45f));
            BuildBotPrefab("Witch_Bot", typeof(WitchController), typeof(KillerBotBrain), new Color(0.42f, 0.72f, 0.44f));
            BuildBotPrefab("Roger_Bot", typeof(JollyRogerController), typeof(KillerBotBrain), new Color(0.64f, 0.68f, 0.73f));

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

            CreateLabel(canvasGO.transform, "Title", new Vector2(0f, 420f), font, "СЧИТАЛКА");
            Text status = CreateLabel(canvasGO.transform, "StatusText", new Vector2(0f, 350f), font, "Режим: BotMatch   Сторона: Гость");

            Button botBtn = CreateButton(canvasGO.transform, "BotMatchButton", new Vector2(-300f, 230f), font, "Матч с ботами");
            Button mpBtn = CreateButton(canvasGO.transform, "MultiplayerButton", new Vector2(0f, 230f), font, "Мультиплеер");
            Button ssBtn = CreateButton(canvasGO.transform, "SplitscreenButton", new Vector2(300f, 230f), font, "Сплитскрин");

            Button guestBtn = CreateButton(canvasGO.transform, "GuestButton", new Vector2(-450f, 120f), font, "Гость");
            Button trickBtn = CreateButton(canvasGO.transform, "TricksterButton", new Vector2(-150f, 120f), font, "Трикстер");
            Button witchBtn = CreateButton(canvasGO.transform, "WitchButton", new Vector2(150f, 120f), font, "Ведьма");
            Button rogerBtn = CreateButton(canvasGO.transform, "RogerButton", new Vector2(450f, 120f), font, "Весёлый Роджер");

            Button startBtn = CreateButton(canvasGO.transform, "StartButton", new Vector2(0f, 10f), font, "В квартал");

            GameObject lobbyGO = new GameObject("LobbyUI");
            var lobby = lobbyGO.AddComponent<Wolf.UI.LobbyUI>();

            var so = new SerializedObject(lobby);
            so.FindProperty("botMatchButton").objectReferenceValue = botBtn;
            so.FindProperty("multiplayerButton").objectReferenceValue = mpBtn;
            so.FindProperty("splitscreenButton").objectReferenceValue = ssBtn;
            so.FindProperty("guestButton").objectReferenceValue = guestBtn;
            so.FindProperty("tricksterButton").objectReferenceValue = trickBtn;
            so.FindProperty("witchButton").objectReferenceValue = witchBtn;
            so.FindProperty("rogerButton").objectReferenceValue = rogerBtn;
            so.FindProperty("startButton").objectReferenceValue = startBtn;
            so.FindProperty("statusText").objectReferenceValue = status;
            so.FindProperty("gameplaySceneName").stringValue = "Quarter";
            so.ApplyModifiedProperties();

            EditorSceneManager.SaveScene(scene, $"{SceneDir}/Lobby.unity");
            Debug.Log("[Wolf] Lobby scene built.");
        }

        [MenuItem("Tools/Wolf/3 Build Quarter Blockout Scene")]
        public static void BuildQuarterScene()
        {
            EnsureFolder(SceneDir);
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            GameObject lightGO = new GameObject("Moonlight");
            Light light = lightGO.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 0.35f;   // it's meant to be night
            light.color = new Color(0.55f, 0.62f, 0.78f);
            lightGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            RenderSettings.ambientLight = new Color(0.1f, 0.12f, 0.17f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogDensity = 0.03f;
            RenderSettings.fogColor = new Color(0.02f, 0.03f, 0.05f);

            GameObject ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Asphalt";
            ground.transform.localScale = new Vector3(9f, 1f, 7f);

            GameObject gmGO = new GameObject("GameManager");
            GameManager gm = gmGO.AddComponent<GameManager>();
            var gmSo = new SerializedObject(gm);
            gmSo.FindProperty("settings").objectReferenceValue = GetOrCreateMatchSettings();
            gmSo.ApplyModifiedProperties();

            GameObject bootstrapGO = new GameObject("MatchBootstrapper");
            WireBootstrapperPrefabs(bootstrapGO.AddComponent<MatchBootstrapper>());

            BuildQuarterBlockout();

            // Guests start together in the south, the killer starts far north —
            // the only head start the guests get.
            CreateSpawnPoint("GuestSpawn_1", FactionType.Guest, new Vector3(-16f, 1f, -23f));
            CreateSpawnPoint("GuestSpawn_2", FactionType.Guest, new Vector3(-9f, 1f, -23f));
            CreateSpawnPoint("GuestSpawn_3", FactionType.Guest, new Vector3(9f, 1f, -23f));
            CreateSpawnPoint("GuestSpawn_4", FactionType.Guest, new Vector3(16f, 1f, -23f));
            CreateSpawnPoint("KillerSpawn", FactionType.Killer, new Vector3(0f, 1f, 10f));

            foreach (Vector3 pos in new[]
            {
                new Vector3(-21f, 0f, -15f), new Vector3(20f, 0f, -15f),
                new Vector3(-20f, 0f, 17f), new Vector3(21f, 0f, 13f),
                new Vector3(0f, 0f, -8f),
            })
            {
                CreateBreaker(pos);
            }

            foreach (Vector3 pos in new[]
            {
                new Vector3(-13f, 0f, -6f), new Vector3(13f, 0f, -7f),
                new Vector3(-12f, 0f, 9f), new Vector3(12f, 0f, 10f),
                new Vector3(0f, 0f, 17f),
            })
            {
                CreateHook(pos);
            }

            CreateBreach(new Vector3(0f, 2f, 26f));

            EditorSceneManager.SaveScene(scene, $"{SceneDir}/Quarter.unity");
            Debug.Log("[Wolf] Quarter blockout built. Bake a NavMesh (Window → AI → Navigation) before judging the bots.");
        }

        // --- the quarter ---

        private static void BuildQuarterBlockout()
        {
            GameObject root = new GameObject("Quarter");

            // Perimeter, with a 7m breach in the north wall.
            AddWall(root, new Vector3(0f, 0f, -26f), 68f, horizontal: true, breakable: false, height: 5f);
            AddWall(root, new Vector3(-34f, 0f, 0f), 52f, horizontal: false, breakable: false, height: 5f);
            AddWall(root, new Vector3(34f, 0f, 0f), 52f, horizontal: false, breakable: false, height: 5f);
            AddWall(root, new Vector3(-18.75f, 0f, 26f), 30.5f, horizontal: true, breakable: false, height: 5f);
            AddWall(root, new Vector3(18.75f, 0f, 26f), 30.5f, horizontal: true, breakable: false, height: 5f);

            // Four ruined shells and a low outbuilding, each with doorways to
            // loop around — the chase geometry of the whole map.
            AddShell(root, new Vector3(-21f, 0f, -15f), 16f, 13f, northOpen: true);
            AddShell(root, new Vector3(20f, 0f, -15f), 15f, 13f, northOpen: false);
            AddShell(root, new Vector3(-20f, 0f, 13f), 16f, 14f, northOpen: false);
            AddShell(root, new Vector3(21f, 0f, 13f), 15f, 14f, northOpen: false);
            AddShell(root, new Vector3(0f, 0f, -21f), 12f, 6f, northOpen: true);

            // Free-standing fragments around the plaza.
            AddDooredRun(root, new Vector3(0f, 0f, 5f), 14f, horizontal: true, breakable: true);
            AddDooredRun(root, new Vector3(-8f, 0f, 2f), 10f, horizontal: false, breakable: false);
            AddDooredRun(root, new Vector3(8f, 0f, 2f), 10f, horizontal: false, breakable: true);
        }

        private static void AddShell(GameObject root, Vector3 centre, float width, float depth, bool northOpen)
        {
            if (!northOpen)
            {
                AddDooredRun(root, centre + new Vector3(0f, 0f, -depth / 2f), width, horizontal: true, breakable: false);
            }
            AddDooredRun(root, centre + new Vector3(0f, 0f, depth / 2f), width, horizontal: true, breakable: true);
            AddDooredRun(root, centre + new Vector3(-width / 2f, 0f, 0f), depth, horizontal: false, breakable: false);
            AddDooredRun(root, centre + new Vector3(width / 2f, 0f, 0f), depth, horizontal: false, breakable: false);
        }

        /// <summary>A wall with a gap in the middle, plus the DoorwayMarker the Witch needs to seal it.</summary>
        private static void AddDooredRun(GameObject root, Vector3 centre, float length, bool horizontal, bool breakable)
        {
            float segment = (length - DoorHalfWidth * 2f) / 2f;
            float offset = DoorHalfWidth + segment / 2f;

            Vector3 along = horizontal ? Vector3.right : Vector3.forward;
            AddWall(root, centre - along * offset, segment, horizontal, breakable, WallHeight);
            AddWall(root, centre + along * offset, segment, horizontal, breakable, WallHeight);

            GameObject doorway = new GameObject("Doorway") { transform = { position = centre } };
            doorway.transform.SetParent(root.transform);
            doorway.transform.rotation = horizontal ? Quaternion.identity : Quaternion.Euler(0f, 90f, 0f);
            doorway.AddComponent<DoorwayMarker>().width = DoorHalfWidth * 2f;
        }

        private static void AddWall(GameObject root, Vector3 centre, float length, bool horizontal, bool breakable, float height)
        {
            if (length <= 0.05f)
            {
                return;
            }

            GameObject wall = GameObject.CreatePrimitive(PrimitiveType.Cube);
            wall.name = breakable ? "Wall_Cracked" : "Wall";
            wall.transform.SetParent(root.transform);
            wall.transform.position = centre + Vector3.up * (height / 2f);
            wall.transform.localScale = horizontal
                ? new Vector3(length, height, WallThickness)
                : new Vector3(WallThickness, height, length);

            ApplyColor(wall, breakable ? new Color(0.23f, 0.19f, 0.16f) : new Color(0.17f, 0.17f, 0.19f));

            if (breakable)
            {
                wall.AddComponent<BreakableWall>();
            }
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
            WireControllerExtras(root, pivotGO, controllerType, so);
            so.ApplyModifiedProperties();

            SaveAsPrefab(root, name);
        }

        private static void BuildBotPrefab(string name, System.Type controllerType, System.Type brainType, Color color)
        {
            GameObject root = CreateBody(name, controllerType, color);
            root.AddComponent(brainType);

            var so = new SerializedObject(root.GetComponent(controllerType));
            WireControllerExtras(root, root, controllerType, so);
            so.ApplyModifiedProperties();

            SaveAsPrefab(root, name);
        }

        /// <summary>Per-role wiring: a shoulder to carry on, a torch, the power prefabs.</summary>
        private static void WireControllerExtras(GameObject root, GameObject pivot, System.Type controllerType, SerializedObject so)
        {
            if (controllerType == typeof(GuestController))
            {
                GameObject torchGO = new GameObject("Flashlight");
                torchGO.transform.SetParent(pivot.transform, false);
                Light torch = torchGO.AddComponent<Light>();
                torch.type = LightType.Spot;
                torch.range = 24f;
                torch.spotAngle = 40f;
                torch.intensity = 2.5f;
                torch.enabled = false;
                so.FindProperty("flashlight").objectReferenceValue = torch;
                return;
            }

            GameObject carryGO = new GameObject("CarryPoint");
            carryGO.transform.SetParent(root.transform, false);
            carryGO.transform.localPosition = new Vector3(0.2f, 1.1f, 0.1f);
            so.FindProperty("carryPoint").objectReferenceValue = carryGO.transform;

            if (controllerType == typeof(TricksterController))
            {
                so.FindProperty("doublePrefab").objectReferenceValue = LoadPrefab("Trickster_Double");
            }
            else if (controllerType == typeof(WitchController))
            {
                so.FindProperty("thicketPrefab").objectReferenceValue = LoadPrefab("Thicket");
            }
        }

        private static void BuildThicketPrefab()
        {
            GameObject root = GameObject.CreatePrimitive(PrimitiveType.Cube);
            root.name = "Thicket";
            root.transform.localScale = new Vector3(2.7f, 2.6f, 0.7f);
            ApplyColor(root, new Color(0.12f, 0.29f, 0.14f));
            root.AddComponent<ThicketBarrier>();
            SaveAsPrefab(root, "Thicket");
        }

        private static void BuildDoublePrefab()
        {
            GameObject root = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            root.name = "Trickster_Double";
            ApplyColor(root, new Color(0.82f, 0.25f, 0.35f));
            root.GetComponent<Collider>().isTrigger = true;   // it fools you, it doesn't block you
            root.AddComponent<TricksterDouble>();
            SaveAsPrefab(root, "Trickster_Double");
        }

        private static GameObject CreateBody(string name, System.Type controllerType, Color color)
        {
            GameObject root = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            root.name = name;
            Object.DestroyImmediate(root.GetComponent<CapsuleCollider>());
            root.AddComponent(controllerType); // RequireComponent cascades CharacterController + HealthComponent
            if (controllerType == typeof(GuestController))
            {
                root.AddComponent<GuestIdentity>();
            }
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
            AssetDatabase.SaveAssets();
        }

        private static GameObject LoadPrefab(string prefabName)
        {
            GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>($"{PrefabDir}/{prefabName}.prefab");
            if (prefab == null)
            {
                Debug.LogWarning($"[Wolf] Prefab '{prefabName}' not found — re-run '1 Build Placeholder Prefabs'.");
            }
            return prefab;
        }

        // --- scene wiring ---

        private static void WireBootstrapperPrefabs(MatchBootstrapper bootstrapper)
        {
            var so = new SerializedObject(bootstrapper);
            AssignPrefab(so, "guestHumanPrefab", "Guest_Human");
            AssignPrefab(so, "tricksterHumanPrefab", "Trickster_Human");
            AssignPrefab(so, "witchHumanPrefab", "Witch_Human");
            AssignPrefab(so, "rogerHumanPrefab", "Roger_Human");
            AssignPrefab(so, "guestBotPrefab", "Guest_Bot");
            AssignPrefab(so, "tricksterBotPrefab", "Trickster_Bot");
            AssignPrefab(so, "witchBotPrefab", "Witch_Bot");
            AssignPrefab(so, "rogerBotPrefab", "Roger_Bot");
            so.ApplyModifiedProperties();
        }

        private static void AssignPrefab(SerializedObject so, string fieldName, string prefabName)
        {
            GameObject prefab = LoadPrefab(prefabName);
            if (prefab != null)
            {
                so.FindProperty(fieldName).objectReferenceValue = prefab;
            }
        }

        private static void CreateSpawnPoint(string name, FactionType faction, Vector3 pos)
        {
            GameObject go = new GameObject(name) { transform = { position = pos } };
            go.AddComponent<SpawnPoint>().faction = faction;
        }

        private static void CreateBreaker(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "Breaker";
            go.transform.position = pos + Vector3.up * 1.1f;
            go.transform.localScale = new Vector3(0.9f, 1.2f, 0.5f);
            ApplyColor(go, new Color(0.18f, 0.19f, 0.22f));

            BreakerObjective breaker = go.AddComponent<BreakerObjective>();
            var so = new SerializedObject(breaker);
            so.FindProperty("statusRenderer").objectReferenceValue = go.GetComponent<Renderer>();
            so.ApplyModifiedProperties();
        }

        private static void CreateHook(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = "Hook";
            go.transform.position = pos + Vector3.up * 1.3f;
            go.transform.localScale = new Vector3(0.3f, 1.3f, 0.3f);
            ApplyColor(go, new Color(0.29f, 0.3f, 0.33f));

            GameObject hangGO = new GameObject("HangPoint");
            hangGO.transform.SetParent(go.transform, false);
            hangGO.transform.localPosition = new Vector3(0f, 0.4f, 1.8f);

            HookObjective hook = go.AddComponent<HookObjective>();
            var so = new SerializedObject(hook);
            so.FindProperty("hangPoint").objectReferenceValue = hangGO.transform;
            so.ApplyModifiedProperties();
        }

        private static void CreateBreach(Vector3 pos)
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = "Breach";
            go.transform.position = pos;
            go.transform.localScale = new Vector3(7f, 4f, 1.5f);
            go.GetComponent<Collider>().isTrigger = true;
            Object.DestroyImmediate(go.GetComponent<Renderer>());
            go.AddComponent<BreachTrigger>();
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
            rt.sizeDelta = new Vector2(900f, 60f);
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
            rt.sizeDelta = new Vector2(260f, 60f);
            rt.anchoredPosition = anchoredPos;

            Image image = go.AddComponent<Image>();
            image.color = new Color(0.1f, 0.1f, 0.12f, 0.92f);

            Button button = go.AddComponent<Button>();

            Text text = CreateLabel(go.transform, "Label", Vector2.zero, font, label);
            text.rectTransform.sizeDelta = rt.sizeDelta;
            text.fontSize = 22;

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
