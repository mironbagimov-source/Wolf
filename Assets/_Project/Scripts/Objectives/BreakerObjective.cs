using UnityEngine;
using Wolf.Core;
using Wolf.Player;
using Wolf.Player.Guest;
using Wolf.Utils;

namespace Wolf.Objectives
{
    /// <summary>
    /// One breaker box. Guests hold interact to bring it back online; enough of
    /// them lit and the breach in the north wall opens
    /// (see MatchSettings.breakersRequired).
    ///
    /// Progress is kept when the repairer walks away, which is the point: the
    /// killer has to keep coming back to the same five boxes.
    /// </summary>
    public class BreakerObjective : MonoBehaviour, IInteractable
    {
        [SerializeField] private float maxWorkDistance = 3f;
        [SerializeField] private Renderer statusRenderer;
        [SerializeField] private Color idleColor = new(0.18f, 0.19f, 0.22f);
        [SerializeField] private Color liveColor = new(0.36f, 0.76f, 0.41f);

        public bool IsOnline { get; private set; }
        public float Progress01 => _repairSeconds / RepairSecondsNeeded;

        private GuestController _worker;
        private float _repairSeconds;

        private float RepairSecondsNeeded =>
            GameManager.Instance != null ? GameManager.Instance.Settings.breakerRepairSeconds : 14f;

        public string InteractionPrompt => IsOnline
            ? "Щит под напряжением"
            : _worker != null
                ? $"Чиним... {Mathf.RoundToInt(Progress01 * 100f)}%"
                : "Чинить щит";

        public bool CanInteract(PlayerControllerBase interactor) =>
            !IsOnline && interactor is GuestController guest && !guest.IsDowned;

        public void Interact(PlayerControllerBase interactor)
        {
            if (IsOnline || interactor is not GuestController guest)
            {
                return;
            }

            _worker = _worker == guest ? null : guest;
        }

        private void Update()
        {
            if (IsOnline || _worker == null)
            {
                return;
            }

            bool stillWorking = _worker.IsInPlay
                && !_worker.IsDowned
                && _worker.Intent.InteractHeld
                && Vector3.Distance(_worker.transform.position, transform.position) <= maxWorkDistance;

            if (!stillWorking)
            {
                _worker = null;
                return;
            }

            _repairSeconds += Time.deltaTime;
            if (_repairSeconds >= RepairSecondsNeeded)
            {
                BringOnline();
            }
        }

        private void BringOnline()
        {
            IsOnline = true;
            _worker = null;
            if (statusRenderer != null)
            {
                statusRenderer.material.color = liveColor;
            }
            GameManager.Instance?.ReportBreakerRepaired();
        }

        private void Awake()
        {
            if (statusRenderer != null)
            {
                statusRenderer.material.color = idleColor;
            }
        }
    }
}
