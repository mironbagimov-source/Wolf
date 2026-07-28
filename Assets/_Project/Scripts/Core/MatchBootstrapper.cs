using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using Wolf.Networking;

namespace Wolf.Core
{
    /// <summary>
    /// Entry point for the gameplay scene. Reads what the lobby put into
    /// PlayerSelection, brings up the right INetworkService, and spawns the
    /// local human plus (in BotMatch) the rest of the cast.
    ///
    /// Exactly one killer exists per match by design — whichever archetype was
    /// picked if the human is the killer, a random one otherwise, so a guest
    /// doesn't know what's coming until they hear it.
    /// </summary>
    public class MatchBootstrapper : MonoBehaviour
    {
        [System.Serializable]
        public struct GuestProfile
        {
            public string guestName;
            [TextArea] public string sin;
        }

        [Header("Human prefabs (camera + local input)")]
        [SerializeField] private GameObject guestHumanPrefab;
        [SerializeField] private GameObject tricksterHumanPrefab;
        [SerializeField] private GameObject witchHumanPrefab;
        [SerializeField] private GameObject rogerHumanPrefab;

        [Header("Bot prefabs (no camera, has BotBrainBase)")]
        [SerializeField] private GameObject guestBotPrefab;
        [SerializeField] private GameObject tricksterBotPrefab;
        [SerializeField] private GameObject witchBotPrefab;
        [SerializeField] private GameObject rogerBotPrefab;

        [Header("The cast")]
        [Tooltip("Names and sins, handed out in order. Guests beyond this list get a numbered fallback.")]
        [SerializeField]
        private GuestProfile[] guestRoster =
        {
            new() { guestName = "Марго Ланд", sin = "сдала своих, чтобы уйти от срока" },
            new() { guestName = "Костя Вьюн", sin = "подписал брата на чужой долг" },
            new() { guestName = "Илья Тарн", sin = "спрятал свою ошибку в чужой могиле" },
            new() { guestName = "Нина Верес", sin = "подожгла дом вместе с бумагами" },
        };

        [SerializeField] private string sessionName = "wolf-quarter";

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
            KillerArchetype archetype = chosen == FactionType.Killer
                ? PlayerSelection.ChosenKiller
                : RandomArchetype();

            int guestCount = GameManager.Instance.Settings != null ? GameManager.Instance.Settings.guestCount : 4;
            int guestIndex = 0;

            if (chosen == FactionType.Guest)
            {
                SpawnGuest(guestHumanPrefab, guestIndex++);
            }
            else
            {
                SpawnKiller(archetype, human: true);
            }

            if (GameManager.Instance.Mode == GameModeType.BotMatch)
            {
                for (; guestIndex < guestCount; guestIndex++)
                {
                    SpawnGuest(guestBotPrefab, guestIndex);
                }

                if (chosen == FactionType.Guest)
                {
                    SpawnKiller(archetype, human: false);
                }
            }

            GameManager.Instance.StartMatch();
        }

        private static KillerArchetype RandomArchetype()
        {
            var values = (KillerArchetype[])System.Enum.GetValues(typeof(KillerArchetype));
            return values[Random.Range(0, values.Length)];
        }

        private void SpawnGuest(GameObject prefab, int index)
        {
            if (prefab == null)
            {
                Debug.LogError("[MatchBootstrapper] No guest prefab assigned.");
                return;
            }

            Transform spawn = GetSpawnPoint(FactionType.Guest, index);
            GameObject instance = _network.SpawnPlayer(prefab, FactionType.Guest, spawn.position, spawn.rotation);
            if (instance == null)
            {
                return;
            }

            GuestIdentity identity = instance.GetComponent<GuestIdentity>();
            if (identity == null)
            {
                identity = instance.AddComponent<GuestIdentity>();
            }
            if (index < guestRoster.Length)
            {
                identity.guestName = guestRoster[index].guestName;
                identity.sin = guestRoster[index].sin;
            }
            else
            {
                identity.guestName = $"Гость {index + 1}";
            }
            identity.figurineIndex = index;
        }

        private void SpawnKiller(KillerArchetype archetype, bool human)
        {
            GameObject prefab = human
                ? archetype switch
                {
                    KillerArchetype.Trickster => tricksterHumanPrefab,
                    KillerArchetype.Witch => witchHumanPrefab,
                    KillerArchetype.JollyRoger => rogerHumanPrefab,
                    _ => null,
                }
                : archetype switch
                {
                    KillerArchetype.Trickster => tricksterBotPrefab,
                    KillerArchetype.Witch => witchBotPrefab,
                    KillerArchetype.JollyRoger => rogerBotPrefab,
                    _ => null,
                };

            if (prefab == null)
            {
                Debug.LogError($"[MatchBootstrapper] No {(human ? "human" : "bot")} prefab assigned for {archetype}.");
                return;
            }

            Transform spawn = GetSpawnPoint(FactionType.Killer, 0);
            _network.SpawnPlayer(prefab, FactionType.Killer, spawn.position, spawn.rotation);
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
