using UnityEngine;
using Wolf.Core;
using Wolf.Health;
using Wolf.Player.Cannibal;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// The mercenary: heavy melee, a block stance, throwing knives, and a
    /// stealth backstab. Hits a cyber-psycho from behind and it's a silent
    /// takedown (a heavy bonus on the Alpha rather than an instant kill).
    /// Only 3 of these exist per match by design.
    /// </summary>
    public class KillerController : PlayerControllerBase
    {
        [Header("Killer")]
        [SerializeField] private float attackRange = 2.5f;
        [SerializeField] private float attackDamage = 35f;
        [SerializeField] private float attackCooldown = 0.8f;
        [SerializeField] private float blockDamageMultiplier = 0.25f;
        [SerializeField] private float blockMoveMultiplier = 0.4f;

        [Header("Stealth takedown")]
        [Tooltip("Rear cone half-angle (deg) behind a psycho that counts as a backstab.")]
        [SerializeField] private float backstabHalfAngle = 60f;
        [Tooltip("Backstab damage multiplier against the Alpha (normal psychos die outright).")]
        [SerializeField] private float leaderBackstabMultiplier = 2.4f;

        [Header("Throwing knives")]
        [SerializeField] private ThrowingKnife knifePrefab;
        [SerializeField] private int startingKnives = 3;
        [SerializeField] private float throwCooldown = 0.55f;
        [SerializeField] private float knifeDamage = 75f;
        [SerializeField] private float knifeSpeed = 26f;
        [SerializeField] private float knifeRange = 24f;

        public override FactionType Faction => FactionType.Killer;
        public bool IsBlocking { get; private set; }
        public int KnivesLeft { get; private set; }

        private float _nextAttackTime;
        private float _nextThrowTime;
        private float _damageMultiplier = 1f;

        protected override void Awake()
        {
            base.Awake();
            KnivesLeft = startingKnives;
        }

        protected override void Update()
        {
            base.Update();

            IsBlocking = input.SecondaryHeld;

            if (input.PrimaryPressed && Time.time >= _nextAttackTime)
            {
                Attack();
            }
            else if (input.ThrowPressed && Time.time >= _nextThrowTime && KnivesLeft > 0)
            {
                ThrowKnife();
            }
        }

        protected override float ApplySpeedModifier(float baseSpeed) => IsBlocking ? baseSpeed * blockMoveMultiplier : baseSpeed;

        /// <summary>Read by attackers to scale down the damage they deal while this Killer is blocking.</summary>
        public float GetIncomingDamageMultiplier() => IsBlocking ? blockDamageMultiplier : 1f;

        protected override void ApplyArchetype(CharacterArchetype archetype)
        {
            base.ApplyArchetype(archetype);
            KnivesLeft += archetype.extraKnives;
            _damageMultiplier = archetype.damageMul;
            if (archetype.blockDamageMul >= 0f)
            {
                blockDamageMultiplier = archetype.blockDamageMul;
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

            float damage = attackDamage * _damageMultiplier;

            // Stealth takedown against a psycho hit from behind.
            if (hit.collider.TryGetComponent(out CannibalController psycho) && IsBehind(psycho.transform))
            {
                bool isLeader = psycho.GetComponent<CultLeaderMarker>() != null;
                damage = isLeader
                    ? attackDamage * _damageMultiplier * leaderBackstabMultiplier
                    : Mathf.Max(target.CurrentHealth, damage); // lethal on a normal psycho
            }

            target.TakeDamage(new DamageInfo(damage, gameObject, hit.point));
        }

        /// <summary>True when this killer is within the target's rear cone.</summary>
        private bool IsBehind(Transform targetTransform)
        {
            Vector3 toAttacker = transform.position - targetTransform.position;
            toAttacker.y = 0f;
            if (toAttacker.sqrMagnitude < 0.0001f)
            {
                return false;
            }

            // Behind = the direction to the attacker points against the target's facing.
            float dot = Vector3.Dot(targetTransform.forward, toAttacker.normalized);
            return dot < -Mathf.Cos(backstabHalfAngle * Mathf.Deg2Rad);
        }

        private void ThrowKnife()
        {
            _nextThrowTime = Time.time + throwCooldown;

            if (knifePrefab == null)
            {
                Debug.LogWarning("[KillerController] No knife prefab assigned — assign one to enable knife throws.");
                return;
            }

            KnivesLeft--;

            Transform aim = cameraPivot != null ? cameraPivot : transform;
            ThrowingKnife knife = Instantiate(knifePrefab, aim.position + aim.forward * 0.5f, aim.rotation);
            knife.Launch(gameObject, Faction, knifeDamage, knifeSpeed, knifeRange);
        }
    }
}
