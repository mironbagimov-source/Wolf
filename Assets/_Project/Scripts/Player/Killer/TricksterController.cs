using UnityEngine;
using Wolf.Core;
using Wolf.Player.Guest;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// The circus act that nobody laughed at. Two blades, a rope hook, a pair
    /// of doubles wearing his mask — and a meter that fills with everything he
    /// spills. When it fills, he stops being careful.
    ///
    /// Knife: fast and cheap. Scythe: wide and slow. The hook shot is not a
    /// weapon, it's a leash — it drags someone back into knife range.
    /// </summary>
    public class TricksterController : KillerControllerBase
    {
        [Header("Scythe (RMB)")]
        [SerializeField] private float scytheRange = 3.2f;
        [SerializeField] private float scytheDamage = 52f;
        [SerializeField] private float scytheCooldown = 1.15f;
        [SerializeField] private float scytheArcDegrees = 105f;

        [Header("Hook shot (Q)")]
        [SerializeField] private float hookRange = 15f;
        [SerializeField] private float hookCooldown = 11f;
        [SerializeField] private float hookArcDegrees = 40f;
        [SerializeField] private float hookRootSeconds = 1.3f;
        [SerializeField] private float hookLandingDistance = 1.8f;

        [Header("Doubles (F)")]
        [SerializeField] private GameObject doublePrefab;
        [SerializeField] private int doubleCount = 2;
        [SerializeField] private float doubleCooldown = 26f;
        [SerializeField] private float doubleLifetime = 11f;

        [Header("Frenzy")]
        [Tooltip("Blood earned per hit. The meter runs 0–100.")]
        [SerializeField] private float bloodPerHit = 16f;
        [SerializeField] private float frenzySeconds = 12f;
        [SerializeField] private float frenzySpeedMultiplier = 1.34f;
        [SerializeField] private float frenzyDamageMultiplier = 1.55f;
        [SerializeField] private float frenzyCooldownMultiplier = 0.5f;

        public override KillerArchetype Archetype => KillerArchetype.Trickster;

        public float Blood { get; private set; }
        public bool IsFrenzied => _frenzyRemaining > 0f;
        public float FrenzyRemaining => _frenzyRemaining;

        private float _frenzyRemaining;

        protected override float DamageScale => IsFrenzied ? frenzyDamageMultiplier : 1f;
        protected override float CooldownScale => IsFrenzied ? frenzyCooldownMultiplier : 1f;
        protected override float SpeedScale => IsFrenzied ? frenzySpeedMultiplier : 1f;

        protected override void Update()
        {
            base.Update();

            if (_frenzyRemaining > 0f)
            {
                _frenzyRemaining = Mathf.Max(0f, _frenzyRemaining - Time.deltaTime);
            }
        }

        protected override void OnDealtDamage(GuestController guest, float damage)
        {
            if (IsFrenzied)
            {
                return;   // the meter is spent; it refills after
            }

            Blood = Mathf.Min(100f, Blood + bloodPerHit);
            if (Blood >= 100f)
            {
                Blood = 0f;
                _frenzyRemaining = frenzySeconds;
            }
        }

        protected override void UseSecondary()
        {
            nextSecondaryTime = Time.time + scytheCooldown * CooldownScale;

            GuestController target = FindGuestInCone(scytheRange, scytheArcDegrees, requireLineOfSight: false, includeDowned: false);
            if (target != null)
            {
                Strike(target, scytheDamage * DamageScale);
            }
        }

        protected override void UsePower1()
        {
            nextPower1Time = Time.time + hookCooldown * CooldownScale;

            GuestController target = FindGuestInCone(hookRange, hookArcDegrees, requireLineOfSight: true, includeDowned: false);
            if (target == null)
            {
                return;
            }

            Vector3 landing = transform.position + transform.forward * hookLandingDistance;
            target.Displace(new Vector3(landing.x, target.transform.position.y, landing.z));
            target.ApplyRoot(hookRootSeconds);
        }

        protected override void UsePower2()
        {
            nextPower2Time = Time.time + doubleCooldown;

            if (doublePrefab == null)
            {
                Debug.LogWarning("[Trickster] No double prefab assigned — the power does nothing.");
                return;
            }

            for (int i = 0; i < doubleCount; i++)
            {
                float spread = doubleCount > 1 ? Mathf.Lerp(-55f, 55f, i / (float)(doubleCount - 1)) : 0f;
                Quaternion rotation = transform.rotation * Quaternion.Euler(0f, spread, 0f);
                GameObject instance = Instantiate(doublePrefab, transform.position, rotation);

                if (instance.TryGetComponent(out TricksterDouble twin))
                {
                    twin.Live(doubleLifetime);
                }
                else
                {
                    Destroy(instance, doubleLifetime);
                }
            }
        }
    }
}
