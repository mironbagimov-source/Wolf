using UnityEngine;
using Wolf.Core;
using Wolf.Health;
using Wolf.Player.Killer;
using Wolf.Player.Survivor;

namespace Wolf.Player.Cannibal
{
    /// <summary>
    /// Melee attacker that can grab downed/cornered survivors and carry them
    /// to the ritual altar (see Objectives/RitualAltarObjective).
    /// </summary>
    public class CannibalController : PlayerControllerBase
    {
        [Header("Cannibal")]
        [SerializeField] private Transform carryPoint;
        [SerializeField] private float attackRange = 2f;
        [SerializeField] private float attackDamage = 20f;
        [SerializeField] private float attackCooldown = 1f;
        [SerializeField] private float grabRange = 2f;
        [SerializeField] private float grabCooldown = 4f;

        public override FactionType Faction => FactionType.Cannibal;
        public SurvivorController CarriedSurvivor { get; private set; }
        public float AttackRange => attackRange;
        public float GrabRange => grabRange;

        private float _nextAttackTime;
        private float _nextGrabTime;

        protected override void Update()
        {
            base.Update();

            if (input.PrimaryPressed && Time.time >= _nextAttackTime)
            {
                Attack();
            }
            else if (input.AbilityPressed && Time.time >= _nextGrabTime)
            {
                TryGrab();
            }
        }

        private void Attack()
        {
            _nextAttackTime = Time.time + attackCooldown;

            if (!Physics.Raycast(cameraPivot.position, cameraPivot.forward, out RaycastHit hit, attackRange))
            {
                return;
            }

            if (!hit.collider.TryGetComponent(out HealthComponent target) || target == Health)
            {
                return;
            }

            float multiplier = 1f;
            if (hit.collider.TryGetComponent(out KillerController killer))
            {
                multiplier = killer.GetIncomingDamageMultiplier();
            }

            target.TakeDamage(new DamageInfo(attackDamage * multiplier, gameObject, hit.point));
        }

        private void TryGrab()
        {
            if (CarriedSurvivor != null)
            {
                return;
            }

            if (!Physics.Raycast(cameraPivot.position, cameraPivot.forward, out RaycastHit hit, grabRange))
            {
                return;
            }

            if (!hit.collider.TryGetComponent(out SurvivorController survivor) || survivor.Health.IsDead || survivor.IsGrabbed)
            {
                return;
            }

            _nextGrabTime = Time.time + grabCooldown;
            CarriedSurvivor = survivor;
            survivor.OnGrabbed(carryPoint);
        }

        /// <summary>Releases whoever is currently being carried, if anyone, restoring their control.</summary>
        public void DropCarriedSurvivor()
        {
            if (CarriedSurvivor == null)
            {
                return;
            }

            CarriedSurvivor.OnReleased();
            CarriedSurvivor = null;
        }

        /// <summary>Transfers the carried survivor to a new owner (the altar) without giving them control back.</summary>
        public SurvivorController HandOffCarriedSurvivor()
        {
            SurvivorController survivor = CarriedSurvivor;
            CarriedSurvivor = null;
            return survivor;
        }
    }
}
