using UnityEngine;
using UnityEngine.UI;
using Wolf.Core;
using Wolf.Player;
using Wolf.Player.Killer;

namespace Wolf.UI
{
    /// <summary>Minimal in-match readout: health, node progress, stance/knives, match result banner.</summary>
    public class HUDController : MonoBehaviour
    {
        [SerializeField] private Text healthText;
        [SerializeField] private Text generatorText;
        [SerializeField] private Text resultBanner;
        [Tooltip("Optional: character name, knife stock (merc), and stance line.")]
        [SerializeField] private Text stanceText;

        private PlayerControllerBase _local;

        private void Start()
        {
            _local = PlayerControllerBase.LocalPlayer;

            if (GameManager.Instance != null)
            {
                GameManager.Instance.GeneratorProgressChanged += OnGeneratorProgress;
                GameManager.Instance.MatchEnded += OnMatchEnded;
                OnGeneratorProgress(GameManager.Instance.GeneratorsCompleted, GameManager.Instance.Settings.generatorsRequired);
            }

            if (resultBanner != null)
            {
                resultBanner.gameObject.SetActive(false);
            }
        }

        private void OnDestroy()
        {
            if (GameManager.Instance != null)
            {
                GameManager.Instance.GeneratorProgressChanged -= OnGeneratorProgress;
                GameManager.Instance.MatchEnded -= OnMatchEnded;
            }
        }

        private void Update()
        {
            if (_local == null)
            {
                _local = PlayerControllerBase.LocalPlayer;
            }

            if (_local != null && healthText != null)
            {
                healthText.text = $"Здоровье {Mathf.CeilToInt(_local.Health.CurrentHealth)}/{Mathf.CeilToInt(_local.Health.MaxHealth)}";
            }

            if (_local != null && stanceText != null)
            {
                stanceText.text = BuildStance(_local);
            }
        }

        private static string BuildStance(PlayerControllerBase local)
        {
            string line = local.CharacterName ?? string.Empty;

            if (local is KillerController killer)
            {
                line += (line.Length > 0 ? "  ·  " : string.Empty) + $"Ножи {killer.KnivesLeft}";
            }

            string stance = local.IsCrouching ? "присед" : (local.IsSprinting ? "бег" : string.Empty);
            if (stance.Length > 0)
            {
                line += (line.Length > 0 ? "  ·  " : string.Empty) + stance;
            }

            return line;
        }

        private void OnGeneratorProgress(int completed, int required)
        {
            if (generatorText != null)
            {
                generatorText.text = $"Узлы {completed}/{required}";
            }
        }

        private void OnMatchEnded(MatchState result)
        {
            if (resultBanner == null)
            {
                return;
            }

            resultBanner.gameObject.SetActive(true);
            resultBanner.text = FactionInfo.ResultText(result);
        }
    }
}
