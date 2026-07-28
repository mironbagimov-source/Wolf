using UnityEngine;
using Wolf.Core;
using Wolf.Player;
using Wolf.Player.Guest;
using Wolf.Player.Killer;
using Wolf.Utils;

namespace Wolf.Objectives
{
    /// <summary>
    /// A rusted meat hook on a concrete stump. The Trickster hangs people on
    /// it; Roger calls it an anchor and does the same thing. Either way it
    /// starts a timer, and the timer is the match.
    ///
    /// One interact from a killer carrying someone hangs them; one interact
    /// from another guest takes them down. Both are a single press — this is
    /// the moment of the match, and it should be a decision, not a hold.
    /// </summary>
    public class HookObjective : MonoBehaviour, IInteractable
    {
        [SerializeField] private Transform hangPoint;

        public GuestController Captive { get; private set; }
        public bool IsFree => Captive == null;
        public float TimeRemaining => Captive != null ? Mathf.Max(0f, HookSeconds - _timer) : 0f;

        private float _timer;

        private float HookSeconds => GameManager.Instance != null ? GameManager.Instance.Settings.hookSeconds : 26f;
        private float UnhookHealth => GameManager.Instance != null ? GameManager.Instance.Settings.unhookHealth : 40f;

        public string InteractionPrompt => Captive != null
            ? $"Снять с крюка ({Mathf.CeilToInt(TimeRemaining)}с)"
            : "Вздёрнуть на крюк";

        public bool CanInteract(PlayerControllerBase interactor)
        {
            if (interactor is KillerControllerBase killer)
            {
                return IsFree && killer.CarriedGuest != null;
            }

            return Captive != null && interactor is GuestController guest && !guest.IsDowned && guest != Captive;
        }

        public void Interact(PlayerControllerBase interactor)
        {
            if (interactor is KillerControllerBase killer)
            {
                Hang(killer);
                return;
            }

            Unhook();
        }

        private void Hang(KillerControllerBase killer)
        {
            if (!IsFree || killer.CarriedGuest == null)
            {
                return;
            }

            Captive = killer.HandOffCarriedGuest();
            _timer = 0f;
            Captive.OnHung(hangPoint != null ? hangPoint : transform);
        }

        private void Unhook()
        {
            if (Captive == null)
            {
                return;
            }

            Captive.OnUnhooked(UnhookHealth);
            Captive = null;
            _timer = 0f;
        }

        private void Update()
        {
            if (Captive == null)
            {
                return;
            }

            if (!Captive.IsInPlay)
            {
                Captive = null;   // finished elsewhere — bled out mid-air, or the match ended
                _timer = 0f;
                return;
            }

            _timer += Time.deltaTime;
            if (_timer >= HookSeconds)
            {
                GuestController doomed = Captive;
                Captive = null;
                _timer = 0f;
                doomed.Health.Kill(gameObject);
            }
        }
    }
}
