using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using Wolf.Core;

namespace Wolf.UI
{
    /// <summary>
    /// Lobby screen: pick a mode, pick a side — and if it's the killer side,
    /// pick which of the three. Wire the buttons up in the Editor once a Canvas
    /// exists; this script only needs the references assigned, it builds no UI
    /// itself (Editor/WolfProjectBuilder does that).
    /// </summary>
    public class LobbyUI : MonoBehaviour
    {
        [Header("Mode")]
        [SerializeField] private Button botMatchButton;
        [SerializeField] private Button multiplayerButton;
        [SerializeField] private Button splitscreenButton;

        [Header("Side")]
        [SerializeField] private Button guestButton;
        [SerializeField] private Button tricksterButton;
        [SerializeField] private Button witchButton;
        [SerializeField] private Button rogerButton;

        [Header("Start")]
        [SerializeField] private Button startButton;
        [SerializeField] private Text statusText;
        [SerializeField] private string gameplaySceneName = "Quarter";

        private void Awake()
        {
            botMatchButton?.onClick.AddListener(() => SelectMode(GameModeType.BotMatch));
            multiplayerButton?.onClick.AddListener(() => SelectMode(GameModeType.Multiplayer));
            splitscreenButton?.onClick.AddListener(() => SelectMode(GameModeType.LocalSplitscreen));

            guestButton?.onClick.AddListener(SelectGuest);
            tricksterButton?.onClick.AddListener(() => SelectKiller(KillerArchetype.Trickster));
            witchButton?.onClick.AddListener(() => SelectKiller(KillerArchetype.Witch));
            rogerButton?.onClick.AddListener(() => SelectKiller(KillerArchetype.JollyRoger));

            startButton?.onClick.AddListener(StartMatch);

            RefreshStatus();
        }

        private void SelectMode(GameModeType mode)
        {
            PlayerSelection.ChosenMode = mode;
            RefreshStatus();
        }

        private void SelectGuest()
        {
            PlayerSelection.ChosenFaction = FactionType.Guest;
            RefreshStatus();
        }

        private void SelectKiller(KillerArchetype archetype)
        {
            PlayerSelection.ChosenFaction = FactionType.Killer;
            PlayerSelection.ChosenKiller = archetype;
            RefreshStatus();
        }

        private void StartMatch()
        {
            SceneManager.LoadScene(gameplaySceneName);
        }

        private void RefreshStatus()
        {
            if (statusText == null)
            {
                return;
            }

            string side = PlayerSelection.ChosenFaction == FactionType.Guest
                ? "Гость"
                : PlayerSelection.ChosenKiller switch
                {
                    KillerArchetype.Trickster => "Трикстер",
                    KillerArchetype.Witch => "Ведьма",
                    KillerArchetype.JollyRoger => "Весёлый Роджер",
                    _ => "?",
                };

            statusText.text = $"Режим: {PlayerSelection.ChosenMode}   Сторона: {side}";
        }
    }
}
