using UnityEngine;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Player.Guest;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// Six feet of canvas and anchor chain. Slow enough that you always see him
    /// coming, and it never once helps: he takes people off their feet in a
    /// single motion, and the wall you put between you isn't a wall to him.
    /// </summary>
    public class JollyRogerController : KillerControllerBase
    {
        [Header("Snatch (RMB)")]
        [SerializeField] private float snatchRange = 2.8f;
        [SerializeField] private float snatchCooldown = 7f;
        [SerializeField] private float snatchArcDegrees = 80f;

        [Header("Charge (Q)")]
        [SerializeField] private float chargeSpeed = 9.4f;
        [SerializeField] private float chargeCooldown = 9f;
        [SerializeField] private float chargeMaxSeconds = 2.4f;
        [SerializeField] private float chargeDamage = 46f;
        [SerializeField] private float chargeStunSeconds = 1.6f;
        [Tooltip("How fast he can still steer mid-charge, in degrees per second.")]
        [SerializeField] private float chargeTurnDegreesPerSecond = 75f;

        public override KillerArchetype Archetype => KillerArchetype.JollyRoger;

        public bool IsCharging => _chargeRemaining > 0f;
        public bool IsStunned => _stunRemaining > 0f;

        private float _chargeRemaining;
        private float _stunRemaining;

        protected override void Update()
        {
            if (_stunRemaining > 0f)
            {
                _stunRemaining -= Time.deltaTime;
                if (_stunRemaining <= 0f)
                {
                    SetInputLocked(false);
                }
                return;
            }

            if (IsCharging)
            {
                TickCharge(Time.deltaTime);
                return;
            }

            base.Update();
        }

        protected override void UseSecondary()
        {
            nextSecondaryTime = Time.time + snatchCooldown;

            // Unlike the other two he doesn't need you on the ground first —
            // he picks people up mid-stride.
            GuestController target = FindGuestInCone(snatchRange, snatchArcDegrees, requireLineOfSight: false, includeDowned: true);
            if (target == null || CarriedGuest != null)
            {
                return;
            }

            PickUp(target);
        }

        protected override void UsePower1()
        {
            nextPower1Time = Time.time + chargeCooldown;
            _chargeRemaining = chargeMaxSeconds;
        }

        private void TickCharge(float dt)
        {
            _chargeRemaining -= dt;
            if (_chargeRemaining <= 0f)
            {
                EndCharge();
                return;
            }

            // He steers with his shoulders, not his neck: the look input still
            // turns him, just far slower than a normal turn.
            float steer = Mathf.Clamp(Intent.Look.x, -1f, 1f) * chargeTurnDegreesPerSecond * dt;
            transform.Rotate(Vector3.up, steer);

            controller.Move((transform.forward * chargeSpeed + Vector3.up * gravity * 0.1f) * dt);
        }

        private void EndCharge()
        {
            _chargeRemaining = 0f;
        }

        private void OnControllerColliderHit(ControllerColliderHit hit)
        {
            if (!IsCharging)
            {
                return;
            }

            if (hit.collider.TryGetComponent(out GuestController guest) && guest.IsInPlay && !guest.IsDowned)
            {
                Strike(guest, chargeDamage);
                EndCharge();
                return;
            }

            BreakableWall wall = hit.collider.GetComponentInParent<BreakableWall>();
            if (wall != null)
            {
                wall.Shatter(gameObject);   // the wall was a door he hadn't opened yet
                return;
            }

            // Something that doesn't give. Neither does the wall of his own skull.
            _stunRemaining = chargeStunSeconds;
            SetInputLocked(true);
            EndCharge();
        }
    }
}
