using UnityEngine;
using Wolf.Core;
using Wolf.Player;
using Wolf.Utils;

namespace Wolf.Objectives
{
    /// <summary>
    /// One repair objective. Survivors interact once to start repairing, stay
    /// in range while it ticks up, and completing enough of these opens the
    /// exit gate (see MatchSettings.generatorsRequired).
    /// </summary>
    public class GeneratorObjective : MonoBehaviour, IInteractable
    {
        [SerializeField] private float repairDuration = 20f;
        [SerializeField] private float maxRepairDistance = 3f;

        public bool IsComplete { get; private set; }
        private PlayerControllerBase _activeRepairer;
        private float _progress;

        public string InteractionPrompt => IsComplete ? "Generator online"
            : _activeRepairer != null ? $"Repairing... {Mathf.RoundToInt(_progress / repairDuration * 100f)}%"
            : "Repair generator";

        public bool CanInteract(PlayerControllerBase interactor) => !IsComplete && interactor.Faction == FactionType.Survivor;

        public void Interact(PlayerControllerBase interactor)
        {
            if (IsComplete)
            {
                return;
            }

            _activeRepairer = _activeRepairer == interactor ? null : interactor;
        }

        private void Update()
        {
            if (IsComplete || _activeRepairer == null)
            {
                return;
            }

            float distance = Vector3.Distance(_activeRepairer.transform.position, transform.position);
            if (distance > maxRepairDistance)
            {
                _activeRepairer = null;
                return;
            }

            _progress += Time.deltaTime;
            if (_progress >= repairDuration)
            {
                IsComplete = true;
                _activeRepairer = null;
                GameManager.Instance?.ReportGeneratorCompleted();
            }
        }
    }
}
