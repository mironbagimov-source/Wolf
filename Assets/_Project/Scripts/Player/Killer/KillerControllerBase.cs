using UnityEngine;
using Wolf.Core;
using Wolf.Health;
using Wolf.Player.Guest;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// What all three hunters share: a swing, a shoulder to carry someone on,
    /// and the hooks. Everything that makes them different is in the
    /// subclasses — see TricksterController, WitchController, JollyRogerController.
    /// </summary>
    public abstract class KillerControllerBase : PlayerControllerBase, ICarrier
    {
        [Header("Killer — carry")]
        [SerializeField] protected Transform carryPoint;
        [SerializeField] protected float carrySpeedMultiplier = 0.82f;

        [Header("Killer — primary swing")]
        [SerializeField] protected float primaryRange = 2.6f;
        [SerializeField] protected float primaryDamage = 30f;
        [SerializeField] protected float primaryCooldown = 0.9f;
        [SerializeField] protected float primaryArcDegrees = 80f;

        public abstract KillerArchetype Archetype { get; }
        public override FactionType Faction => FactionType.Killer;

        /// <summary>The Witch doesn't carry anyone anywhere; the other two do.</summary>
        public virtual bool CanCarry => true;

        public GuestController CarriedGuest { get; private set; }
        public float PrimaryRange => primaryRange;

        protected float nextPrimaryTime;
        protected float nextSecondaryTime;
        protected float nextPower1Time;
        protected float nextPower2Time;

        /// <summary>Frenzy and the like scale every number the killer touches.</summary>
        protected virtual float DamageScale => 1f;
        protected virtual float CooldownScale => 1f;
        protected virtual float SpeedScale => 1f;

        protected override bool CanCrouch => false;

        protected override float ApplySpeedModifier(float baseSpeed)
        {
            float speed = baseSpeed * SpeedScale;
            return CarriedGuest != null ? speed * carrySpeedMultiplier : speed;
        }

        protected override void Update()
        {
            base.Update();

            if (Health.IsDead || IsInputLocked)
            {
                return;
            }

            if (Intent.DropPressed && CarriedGuest != null)
            {
                ReleaseCarriedGuest();
                return;
            }

            if (Intent.PrimaryPressed && Time.time >= nextPrimaryTime)
            {
                UsePrimary();
            }
            else if (Intent.SecondaryPressed && Time.time >= nextSecondaryTime)
            {
                UseSecondary();
            }
            else if (Intent.Power1Pressed && Time.time >= nextPower1Time)
            {
                UsePower1();
            }
            else if (Intent.Power2Pressed && Time.time >= nextPower2Time)
            {
                UsePower2();
            }
        }

        /// <summary>The basic swing. Every killer has one; only the numbers differ.</summary>
        protected virtual void UsePrimary()
        {
            nextPrimaryTime = Time.time + primaryCooldown * CooldownScale;

            GuestController target = FindGuestInCone(primaryRange, primaryArcDegrees, requireLineOfSight: false, includeDowned: false);
            if (target != null)
            {
                Strike(target, primaryDamage * DamageScale);
            }
        }

        protected abstract void UseSecondary();
        protected abstract void UsePower1();

        /// <summary>Only the Trickster has a fourth button.</summary>
        protected virtual void UsePower2() { }

        protected void Strike(GuestController guest, float damage)
        {
            guest.Health.TakeDamage(new DamageInfo(damage, gameObject, guest.transform.position));
            OnDealtDamage(guest, damage);
        }

        /// <summary>Hook for anything that feeds on hurting people — the Trickster's blood meter.</summary>
        protected virtual void OnDealtDamage(GuestController guest, float damage) { }

        /// <summary>
        /// The guest this killer is actually looking at, not merely the nearest
        /// one. Used by every swing and every ranged power.
        /// </summary>
        protected GuestController FindGuestInCone(float range, float arcDegrees, bool requireLineOfSight, bool includeDowned)
        {
            Collider[] hits = Physics.OverlapSphere(transform.position, range);
            GuestController best = null;
            float bestDistance = float.MaxValue;
            float halfArc = arcDegrees * 0.5f;

            foreach (Collider hit in hits)
            {
                if (!hit.TryGetComponent(out GuestController guest) || !guest.IsInPlay)
                {
                    continue;
                }
                if (guest.State == GuestController.GuestState.Carried || guest.State == GuestController.GuestState.Hooked)
                {
                    continue;
                }
                if (!includeDowned && guest.IsDowned)
                {
                    continue;
                }

                Vector3 toTarget = guest.transform.position - transform.position;
                float distance = toTarget.magnitude;
                if (distance > range || Vector3.Angle(transform.forward, toTarget) > halfArc)
                {
                    continue;
                }
                if (requireLineOfSight && !HasLineOfSight(guest))
                {
                    continue;
                }

                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    best = guest;
                }
            }

            return best;
        }

        protected bool HasLineOfSight(GuestController guest)
        {
            Vector3 eye = cameraPivot != null ? cameraPivot.position : transform.position + Vector3.up * 1.6f;
            Vector3 target = guest.transform.position + Vector3.up * 1f;
            return !Physics.Linecast(eye, target, out RaycastHit hit) || hit.collider.GetComponentInParent<GuestController>() == guest;
        }

        // --- carrying ---

        /// <summary>What happens when this killer reaches for a body on the ground.</summary>
        public virtual void OnDownedGuestInteract(GuestController guest)
        {
            PickUp(guest);
        }

        public void PickUp(GuestController guest)
        {
            if (!CanCarry || CarriedGuest != null || guest == null || !guest.IsInPlay)
            {
                return;
            }

            CarriedGuest = guest;
            guest.KillerCarrier = this;
            guest.OnPickedUp(carryPoint != null ? carryPoint : transform);
        }

        public void ReleaseCarriedGuest()
        {
            if (CarriedGuest == null)
            {
                return;
            }

            CarriedGuest.KillerCarrier = null;
            CarriedGuest.OnDropped();
            CarriedGuest = null;
        }

        /// <summary>Transfers the carried guest to a hook without handing control back.</summary>
        public GuestController HandOffCarriedGuest()
        {
            GuestController guest = CarriedGuest;
            if (guest != null)
            {
                guest.KillerCarrier = null;
            }
            CarriedGuest = null;
            return guest;
        }
    }
}
