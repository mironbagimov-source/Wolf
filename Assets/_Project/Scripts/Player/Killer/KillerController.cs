using UnityEngine;
using Wolf.Core;
using Wolf.Health;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// Heavy melee combat: bigger hits than a Cannibal, plus a block stance
    /// that reduces incoming damage. Only 3 of these exist per match by design.
    /// </summary>
    public class KillerController : PlayerControllerBase
    {
        [Header("Killer")]
        [SerializeField] private float attackRange = 2.5f;
        [SerializeField] private float attackDamage = 35f;
        [SerializeField] private float attackCooldown = 0.8f;
        [SerializeField] private float blockDamageMultiplier = 0.25f;
        [SerializeField] private float blockMoveMultiplier = 0.4f;

        public override FactionType Faction => FactionType.Killer;
        public bool IsBlocking { get; private set; }

        private float _nextAttackTime;

        protected override void Update()
        {
            base.Update();

            IsBlocking = input.SecondaryHeld;

            if (input.PrimaryPressed && Time.time >= _nextAttackTime)
            {
                Attack();
            }
        }

        protected override float ApplySpeedModifier(float baseSpeed) => IsBlocking ? baseSpeed * blockMoveMultiplier : baseSpeed;

        /// <summary>Read by attackers to scale down the damage they deal while this Killer is blocking.</summary>
        public float GetIncomingDamageMultiplier() => IsBlocking ? blockDamageMultiplier : 1f;

        private void Attack()
        {
            _nextAttackTime = Time.time + attackCooldown;

            if (!Physics.Raycast(cameraPivot.position, cameraPivot.forward, out RaycastHit hit, attackRange))
            {
                return;
            }

            if (hit.collider.TryGetComponent(out HealthComponent target) && target != Health)
            {
                target.TakeDamage(new DamageInfo(attackDamage, gameObject, hit.point));
            }
        }
    }
}
