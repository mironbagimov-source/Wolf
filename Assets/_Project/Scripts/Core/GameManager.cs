using System;
using System.Collections.Generic;
using UnityEngine;
using Wolf.Player.Guest;
using Wolf.Utils;

namespace Wolf.Core
{
    /// <summary>
    /// Central match state machine. Tracks the roster and objective progress
    /// and resolves the win condition (see docs/GDD.md). Knows nothing about
    /// networking or input — those live in Networking/ and Player/.
    ///
    /// The match ends when no guest is left standing in the quarter: if any of
    /// them got out through the breach the guests take it, otherwise the
    /// counting rhyme has run to its last line.
    /// </summary>
    public class GameManager : Singleton<GameManager>
    {
        [SerializeField] private MatchSettings settings;
        [SerializeField] private GameModeType mode = GameModeType.BotMatch;

        public MatchSettings Settings => settings;
        public GameModeType Mode => mode;
        public MatchState CurrentState { get; private set; } = MatchState.Lobby;

        public int BreakersRepaired { get; private set; }
        public bool BreachOpen => settings != null && BreakersRepaired >= settings.breakersRequired;
        public int GuestsEscaped { get; private set; }
        public int GuestsLost { get; private set; }

        public event Action<MatchState> MatchEnded;
        public event Action<int, int> BreakerProgressChanged;   // (repaired, required)
        public event Action<string> RhymeLineSpoken;            // one line per guest lost
        public event Action RosterChanged;

        private readonly List<GuestController> _guests = new();

        public IReadOnlyList<GuestController> Guests => _guests;

        public void SetMode(GameModeType newMode) => mode = newMode;

        public void StartMatch()
        {
            CurrentState = MatchState.InProgress;
        }

        /// <summary>Call once per spawned guest so the roster and win checks know about them.</summary>
        public void RegisterGuest(GuestController guest)
        {
            if (guest == null || _guests.Contains(guest))
            {
                return;
            }

            _guests.Add(guest);
            RosterChanged?.Invoke();
        }

        public void ReportBreakerRepaired()
        {
            if (settings == null)
            {
                return;
            }

            BreakersRepaired = Mathf.Min(BreakersRepaired + 1, settings.breakersRequired);
            BreakerProgressChanged?.Invoke(BreakersRepaired, settings.breakersRequired);
        }

        /// <summary>Called by the breach trigger when a guest walks out with the power back on.</summary>
        public void ReportGuestEscaped(GuestController guest)
        {
            if (CurrentState != MatchState.InProgress || !BreachOpen)
            {
                return;
            }

            GuestsEscaped++;
            RosterChanged?.Invoke();
            CheckWinConditions();
        }

        /// <summary>Called when a guest is finished off — bled out, hooked to the end, or grown through.</summary>
        public void ReportGuestLost(GuestController guest)
        {
            if (CurrentState != MatchState.InProgress)
            {
                return;
            }

            SpeakRhymeLine(GuestsLost);
            GuestsLost++;
            RosterChanged?.Invoke();
            CheckWinConditions();
        }

        private void SpeakRhymeLine(int index)
        {
            if (settings == null || settings.rhymeLines == null || index < 0 || index >= settings.rhymeLines.Length)
            {
                return;
            }

            RhymeLineSpoken?.Invoke(settings.rhymeLines[index]);
        }

        private void CheckWinConditions()
        {
            if (CurrentState != MatchState.InProgress)
            {
                return;
            }

            foreach (GuestController guest in _guests)
            {
                if (guest != null && guest.IsInPlay)
                {
                    return;   // the quarter still has someone in it
                }
            }

            ResolveMatch(GuestsEscaped > 0 ? MatchState.GuestsWin : MatchState.KillerWins);
        }

        private void ResolveMatch(MatchState result)
        {
            CurrentState = result;
            MatchEnded?.Invoke(result);
        }
    }
}
