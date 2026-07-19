using UnityEngine;
using UnityEngine.UI;
using Wolf.Core;
using Wolf.Player;

namespace Wolf.UI
{
    /// <summary>Minimal in-match readout: health, generator progress, match result banner.</summary>
    public class HUDController : MonoBehaviour
    {
        [SerializeField] private Text healthText;
        [SerializeField] private Text generatorText;
        [SerializeField] private Text resultBanner;

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
                healthText.text = $"HP {Mathf.CeilToInt(_local.Health.CurrentHealth)}/{Mathf.CeilToInt(_local.Health.MaxHealth)}";
            }
        }

        private void OnGeneratorProgress(int completed, int required)
        {
            if (generatorText != null)
            {
                generatorText.text = $"Generators {completed}/{required}";
            }
        }

        private void OnMatchEnded(MatchState result)
        {
            if (resultBanner == null)
            {
                return;
            }

            resultBanner.gameObject.SetActive(true);
            resultBanner.text = result switch
            {
                MatchState.SurvivorsWin => "Survivors escaped.",
                MatchState.CannibalsWin => "The cult claims the base.",
                MatchState.KillersWin => "The Cult Leader is dead.",
                _ => string.Empty,
            };
        }
    }
}
