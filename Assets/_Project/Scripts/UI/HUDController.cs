using UnityEngine;
using UnityEngine.UI;
using Wolf.Core;
using Wolf.Player;
using Wolf.Player.Guest;
using Wolf.Player.Killer;

namespace Wolf.UI
{
    /// <summary>
    /// In-match readout: what state you're in, how many breakers are live, how
    /// many guests are still in the quarter, and the rhyme line that lands each
    /// time one of them isn't.
    /// </summary>
    public class HUDController : MonoBehaviour
    {
        [SerializeField] private Text stateText;
        [SerializeField] private Text breakerText;
        [SerializeField] private Text rosterText;
        [SerializeField] private Text promptText;
        [SerializeField] private Text rhymeBanner;
        [SerializeField] private Text resultBanner;
        [SerializeField] private float rhymeSeconds = 5.5f;

        private PlayerControllerBase _local;
        private float _rhymeTimer;

        private void Start()
        {
            _local = PlayerControllerBase.LocalPlayer;

            if (GameManager.Instance != null)
            {
                GameManager.Instance.BreakerProgressChanged += OnBreakerProgress;
                GameManager.Instance.RhymeLineSpoken += OnRhymeLine;
                GameManager.Instance.MatchEnded += OnMatchEnded;
                OnBreakerProgress(GameManager.Instance.BreakersRepaired, GameManager.Instance.Settings.breakersRequired);
            }

            HideBanner(resultBanner);
            HideBanner(rhymeBanner);
        }

        private void OnDestroy()
        {
            if (GameManager.Instance == null)
            {
                return;
            }

            GameManager.Instance.BreakerProgressChanged -= OnBreakerProgress;
            GameManager.Instance.RhymeLineSpoken -= OnRhymeLine;
            GameManager.Instance.MatchEnded -= OnMatchEnded;
        }

        private void Update()
        {
            _local ??= PlayerControllerBase.LocalPlayer;

            if (_rhymeTimer > 0f)
            {
                _rhymeTimer -= Time.deltaTime;
                if (_rhymeTimer <= 0f)
                {
                    HideBanner(rhymeBanner);
                }
            }

            if (_local == null)
            {
                return;
            }

            if (stateText != null)
            {
                stateText.text = DescribeState(_local);
            }
            if (rosterText != null && GameManager.Instance != null)
            {
                rosterText.text = $"На ногах: {CountInPlay()}   Ушли: {GameManager.Instance.GuestsEscaped}";
            }
            if (promptText != null)
            {
                promptText.text = _local.ProbeInteractable()?.InteractionPrompt ?? string.Empty;
            }
        }

        private static string DescribeState(PlayerControllerBase local)
        {
            if (local is GuestController guest)
            {
                return guest.State switch
                {
                    GuestController.GuestState.Downed => $"На земле — {Mathf.CeilToInt(guest.BleedoutRemaining)}с",
                    GuestController.GuestState.Carried => $"Тебя несут — ПРОБЕЛ ({Mathf.RoundToInt(guest.StruggleProgress * 100f)}%)",
                    GuestController.GuestState.Hooked => "Крюк",
                    _ => guest.IsInjured ? "Ранен" : "Цел",
                };
            }

            if (local is TricksterController trickster)
            {
                return trickster.IsFrenzied
                    ? $"РЕЖИМ ПСИХА — {trickster.FrenzyRemaining:0.0}с"
                    : $"Кровь {Mathf.RoundToInt(trickster.Blood)}%";
            }

            if (local is WitchController witch)
            {
                return $"Поросль: {witch.ActiveThickets}";
            }

            if (local is JollyRogerController roger)
            {
                return roger.IsCharging ? "ТАРАН" : (roger.IsStunned ? "Оглушён" : "Охота");
            }

            return string.Empty;
        }

        private static int CountInPlay()
        {
            int count = 0;
            foreach (GuestController guest in GameManager.Instance.Guests)
            {
                if (guest != null && guest.IsInPlay)
                {
                    count++;
                }
            }
            return count;
        }

        private void OnBreakerProgress(int repaired, int required)
        {
            if (breakerText != null)
            {
                breakerText.text = $"Щиты {repaired}/{required}";
            }
        }

        private void OnRhymeLine(string line)
        {
            if (rhymeBanner == null)
            {
                return;
            }

            rhymeBanner.gameObject.SetActive(true);
            rhymeBanner.text = line;
            _rhymeTimer = rhymeSeconds;
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
                MatchState.GuestsWin => $"Кто-то вышел. Через пролом ушли: {GameManager.Instance.GuestsEscaped}.",
                MatchState.KillerWins => "Считалка сошлась. И не осталось никого.",
                _ => string.Empty,
            };
        }

        private static void HideBanner(Text banner)
        {
            if (banner != null)
            {
                banner.gameObject.SetActive(false);
            }
        }
    }
}
