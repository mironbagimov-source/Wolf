using UnityEngine;
using Wolf.Core;

namespace Wolf.Player.Survivor
{
    /// <summary>
    /// Stealth-only: no combat. Can be grabbed by a Cannibal, which locks
    /// input and rides along the carrier until dropped or rescued.
    /// </summary>
    public class SurvivorController : PlayerControllerBase
    {
        [Header("Survivor")]
        [SerializeField] private Light flashlight;

        public override FactionType Faction => FactionType.Survivor;
        public bool IsGrabbed { get; private set; }
        public bool FlashlightOn { get; private set; }

        protected override void Update()
        {
            base.Update();

            if (!IsGrabbed && input.FlashlightPressed)
            {
                ToggleFlashlight();
            }
        }

        private void ToggleFlashlight()
        {
            FlashlightOn = !FlashlightOn;
            if (flashlight != null)
            {
                flashlight.enabled = FlashlightOn;
            }
        }

        /// <summary>Called by a Cannibal when it successfully grabs this survivor.</summary>
        public void OnGrabbed(Transform carryPoint)
        {
            if (IsGrabbed || Health.IsDead)
            {
                return;
            }

            IsGrabbed = true;
            SetInputLocked(true);
            controller.enabled = false;
            transform.SetParent(carryPoint, worldPositionStays: false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
        }

        /// <summary>Called by the ritual altar once a Cannibal hands this survivor off to it.</summary>
        public void OnPlacedOnAltar(Transform altarPoint)
        {
            if (Health.IsDead)
            {
                return;
            }

            transform.SetParent(altarPoint, worldPositionStays: false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
        }

        /// <summary>Called on rescue, drop, or reaching the altar — returns control to the player.</summary>
        public void OnReleased()
        {
            if (!IsGrabbed)
            {
                return;
            }

            IsGrabbed = false;
            transform.SetParent(null, worldPositionStays: true);
            controller.enabled = true;
            SetInputLocked(false);
        }
    }
}
