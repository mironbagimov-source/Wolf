using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using Wolf.Networking;

namespace Wolf.Core
{
    /// <summary>
    /// Entry point for the gameplay scene. Reads what the lobby put into
    /// PlayerSelection, brings up the right INetworkService, and spawns the
    /// local human plus (in BotMatch) an AI roster for the other side(s).
    ///
    /// Current limitation: no Killer bot brain exists yet (see AI/), so
    /// BotMatch never spawns Killers — that faction is multiplayer-only until
    /// one is written.
    /// </summary>
    public class MatchBootstrapper : MonoBehaviour
    {
        [Header("Human prefabs (camera + local input)")]
        [SerializeField] private GameObject survivorHumanPrefab;
        [SerializeField] private GameObject cannibalHumanPrefab;
        [SerializeField] private GameObject killerHumanPrefab;

        [Header("Bot prefabs (no camera, has BotBrainBase)")]
        [SerializeField] private GameObject survivorBotPrefab;
        [SerializeField] private GameObject cannibalBotPrefab;

        [Header("Bot roster size (BotMatch only)")]
        [SerializeField] private int botSurvivorCount = 3;
        [SerializeField] private int botCannibalCount = 2;

        [SerializeField] private string sessionName = "wolf-tourbase";

        private INetworkService _network;

        private void Start()
        {
            GameModeType mode = PlayerSelection.ChosenMode;
            GameManager.Instance.SetMode(mode);

            _network = mode == GameModeType.Multiplayer ? new PhotonNetworkService() : new OfflineNetworkService();
            _network.Ready += OnNetworkReady;
            _network.Connect(mode, sessionName);
        }

        private void OnNetworkReady()
        {
            FactionType chosen = PlayerSelection.ChosenFaction;
            SpawnHuman(chosen);

            if (GameManager.Instance.Mode == GameModeType.BotMatch)
            {
                SpawnBotRoster(chosen);
            }

            GameManager.Instance.StartMatch();
        }

        private void SpawnHuman(FactionType faction)
        {
            GameObject prefab = faction switch
            {
                FactionType.Survivor => survivorHumanPrefab,
                FactionType.Cannibal => cannibalHumanPrefab,
                FactionType.Killer => killerHumanPrefab,
                _ => null,
            };

            if (prefab == null)
            {
                Debug.LogError($"[MatchBootstrapper] No human prefab assigned for {faction}.");
                return;
            }

            Transform spawn = GetSpawnPoint(faction, 0);
            GameObject instance = _network.SpawnPlayer(prefab, faction, spawn.position, spawn.rotation);

            // Solo human Cannibal in a bot match plays as the boss by default.
            if (faction == FactionType.Cannibal && GameManager.Instance.Mode == GameModeType.BotMatch)
            {
                instance.AddComponent<CultLeaderMarker>();
            }
        }

        private void SpawnBotRoster(FactionType humanFaction)
        {
            if (humanFaction != FactionType.Survivor)
            {
                for (int i = 0; i < botSurvivorCount; i++)
                {
                    SpawnBot(FactionType.Survivor, survivorBotPrefab, i + 1);
                }
            }

            if (humanFaction != FactionType.Cannibal)
            {
                for (int i = 0; i < botCannibalCount; i++)
                {
                    GameObject bot = SpawnBot(FactionType.Cannibal, cannibalBotPrefab, i + 1);
                    if (i == 0 && bot != null)
                    {
                        bot.AddComponent<CultLeaderMarker>();
                    }
                }
            }
        }

        private GameObject SpawnBot(FactionType faction, GameObject prefab, int spawnIndex)
        {
            if (prefab == null)
            {
                Debug.LogError($"[MatchBootstrapper] No bot prefab assigned for {faction}.");
                return null;
            }

            Transform spawn = GetSpawnPoint(faction, spawnIndex);
            return _network.SpawnPlayer(prefab, faction, spawn.position, spawn.rotation);
        }

        private Transform GetSpawnPoint(FactionType faction, int index)
        {
            List<SpawnPoint> points = FindObjectsOfType<SpawnPoint>().Where(p => p.faction == faction).ToList();
            if (points.Count == 0)
            {
                Debug.LogError($"[MatchBootstrapper] No SpawnPoint tagged {faction} in the scene.");
                return transform;
            }

            return points[index % points.Count].transform;
        }
    }
}
