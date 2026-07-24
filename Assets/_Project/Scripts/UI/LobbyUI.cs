using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;
using Wolf.Core;

namespace Wolf.UI
{
    /// <summary>
    /// Lobby screen: pick a mode, pick a faction, load the gameplay scene.
    /// Wire the buttons up in the Editor once a Canvas exists — this script
    /// only needs the references assigned, it builds no UI itself.
    /// </summary>
    public class LobbyUI : MonoBehaviour
    {
        [Header("Mode")]
        [SerializeField] private Button botMatchButton;
        [SerializeField] private Button multiplayerButton;
        [SerializeField] private Button splitscreenButton;

        [Header("Faction")]
        [SerializeField] private Button survivorButton;
        [SerializeField] private Button cannibalButton;
        [SerializeField] private Button killerButton;

        [Header("Character")]
        [Tooltip("Optional: cycles the chosen character within the picked faction.")]
        [SerializeField] private Button characterButton;

        [Header("Start")]
        [SerializeField] private Button startButton;
        [SerializeField] private Text statusText;
        [SerializeField] private string gameplaySceneName = "TourBase";

        private void Awake()
        {
            botMatchButton?.onClick.AddListener(() => SelectMode(GameModeType.BotMatch));
            multiplayerButton?.onClick.AddListener(() => SelectMode(GameModeType.Multiplayer));
            splitscreenButton?.onClick.AddListener(() => SelectMode(GameModeType.LocalSplitscreen));

            survivorButton?.onClick.AddListener(() => SelectFaction(FactionType.Survivor));
            cannibalButton?.onClick.AddListener(() => SelectFaction(FactionType.Cannibal));
            killerButton?.onClick.AddListener(() => SelectFaction(FactionType.Killer));

            characterButton?.onClick.AddListener(CycleCharacter);

            startButton?.onClick.AddListener(StartMatch);

            RefreshStatus();
        }

        private void SelectMode(GameModeType mode)
        {
            PlayerSelection.ChosenMode = mode;
            RefreshStatus();
        }

        private void SelectFaction(FactionType faction)
        {
            PlayerSelection.ChosenFaction = faction;
            PlayerSelection.ChosenCharacterIndex = 0; // reset to the first character of the new side
            RefreshStatus();
        }

        private void CycleCharacter()
        {
            PlayerSelection.ChosenCharacterIndex++; // CharacterRoster.Get wraps this
            RefreshStatus();
        }

        private void StartMatch()
        {
            SceneManager.LoadScene(gameplaySceneName);
        }

        private void RefreshStatus()
        {
            if (statusText != null)
            {
                CharacterArchetype character = CharacterRoster.Get(PlayerSelection.ChosenFaction, PlayerSelection.ChosenCharacterIndex);
                statusText.text =
                    $"Режим: {PlayerSelection.ChosenMode}   " +
                    $"Сторона: {FactionInfo.DisplayName(PlayerSelection.ChosenFaction)}   " +
                    $"Персонаж: {character.name}";
            }
        }
    }
}
