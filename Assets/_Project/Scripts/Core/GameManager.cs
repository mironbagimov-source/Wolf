using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using Wolf.Health;
using Wolf.Utils;

namespace Wolf.Core
{
    /// <summary>
    /// Central match state machine. Tracks the roster and objective progress
    /// and resolves the three-way win condition (see docs/GDD.md). Does not
    /// know about networking or input — those live in Networking/ and Player/.
    /// </summary>
    public class GameManager : Singleton<GameManager>
    {
        [SerializeField] private MatchSettings settings;
        [SerializeField] private GameModeType mode = GameModeType.BotMatch;

        public MatchSettings Settings => settings;
        public GameModeType Mode => mode;
        public MatchState CurrentState { get; private set; } = MatchState.Lobby;

        public int GeneratorsCompleted { get; private set; }
        public bool ExitGateOpen => GeneratorsCompleted >= settings.generatorsRequired;
        public int SurvivorsEscaped { get; private set; }

        public event Action<MatchState> MatchEnded;
        public event Action<int, int> GeneratorProgressChanged; // (completed, required)

        private readonly Dictionary<FactionType, List<HealthComponent>> _roster = new()
        {
            { FactionType.Survivor, new List<HealthComponent>() },
            { FactionType.Cannibal, new List<HealthComponent>() },
            { FactionType.Killer, new List<HealthComponent>() },
        };

        private HealthComponent _cultLeader;

        public void SetMode(GameModeType newMode) => mode = newMode;

        public void StartMatch()
        {
            CurrentState = MatchState.InProgress;
        }

        /// <summary>Call once per spawned player so the roster and win checks know about it.</summary>
        public void RegisterPlayer(FactionType faction, HealthComponent health, bool isCultLeader = false)
        {
            _roster[faction].Add(health);
            health.Died += _ => OnPlayerDied(faction, health);

            if (isCultLeader)
            {
                if (_cultLeader != null)
                {
                    Debug.LogWarning("[GameManager] A Cult Leader is already registered — ignoring the extra one.");
                    return;
                }
                _cultLeader = health;
            }
        }

        public IReadOnlyList<HealthComponent> GetRoster(FactionType faction) => _roster[faction];

        public void ReportGeneratorCompleted()
        {
            GeneratorsCompleted = Mathf.Min(GeneratorsCompleted + 1, settings.generatorsRequired);
            GeneratorProgressChanged?.Invoke(GeneratorsCompleted, settings.generatorsRequired);
        }

        /// <summary>Called by the exit gate trigger when a living survivor reaches it while it's open.</summary>
        public void ReportSurvivorEscaped(HealthComponent survivor)
        {
            if (CurrentState != MatchState.InProgress || !ExitGateOpen || survivor.IsDead)
            {
                return;
            }

            SurvivorsEscaped++;
            _roster[FactionType.Survivor].Remove(survivor);
            CheckWinConditions();
        }

        private void OnPlayerDied(FactionType faction, HealthComponent health)
        {
            if (faction == FactionType.Cannibal && health == _cultLeader)
            {
                ResolveMatch(MatchState.KillersWin);
                return;
            }

            CheckWinConditions();
        }

        private void CheckWinConditions()
        {
            if (CurrentState != MatchState.InProgress)
            {
                return;
            }

            if (SurvivorsEscaped >= settings.survivorsRequiredToEscape)
            {
                ResolveMatch(MatchState.SurvivorsWin);
                return;
            }

            bool anySurvivorAlive = _roster[FactionType.Survivor].Any(h => !h.IsDead);
            if (!anySurvivorAlive && SurvivorsEscaped < settings.survivorsRequiredToEscape)
            {
                ResolveMatch(MatchState.CannibalsWin);
            }
        }

        private void ResolveMatch(MatchState result)
        {
            CurrentState = result;
            MatchEnded?.Invoke(result);
        }
    }
}
