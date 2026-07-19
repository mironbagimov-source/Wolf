using UnityEngine;
using Wolf.Core;
using Wolf.Player;
using Wolf.Player.Cannibal;
using Wolf.Player.Survivor;
using Wolf.Utils;

namespace Wolf.Objectives
{
    /// <summary>
    /// Trigger volume Cannibals carry survivors into. Once placed, a captive
    /// survivor is sacrificed after MatchSettings.sacrificeTimer unless another
    /// survivor interacts with the altar to rescue them first.
    /// Requires a trigger Collider on this GameObject.
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class RitualAltarObjective : MonoBehaviour, IInteractable
    {
        [SerializeField] private Transform sacrificePoint;

        private SurvivorController _captive;
        private float _timer;

        public string InteractionPrompt => _captive != null ? "Rescue captive" : string.Empty;

        public bool CanInteract(PlayerControllerBase interactor) =>
            _captive != null && interactor.Faction == FactionType.Survivor && (SurvivorController)interactor != _captive;

        public void Interact(PlayerControllerBase interactor) => Rescue();

        private void OnTriggerEnter(Collider other)
        {
            if (_captive != null || !other.TryGetComponent(out CannibalController cannibal) || cannibal.CarriedSurvivor == null)
            {
                return;
            }

            _captive = cannibal.HandOffCarriedSurvivor();
            _timer = 0f;

            Transform anchor = sacrificePoint != null ? sacrificePoint : transform;
            _captive.OnPlacedOnAltar(anchor);
        }

        private void Update()
        {
            if (_captive == null)
            {
                return;
            }

            _timer += Time.deltaTime;
            float limit = GameManager.Instance != null ? GameManager.Instance.Settings.sacrificeTimer : 30f;
            if (_timer >= limit)
            {
                Sacrifice();
            }
        }

        private void Sacrifice()
        {
            _captive.Health.Kill(gameObject);
            _captive = null;
        }

        private void Rescue()
        {
            if (_captive == null)
            {
                return;
            }

            _captive.OnReleased();
            _captive = null;
        }
    }
}
