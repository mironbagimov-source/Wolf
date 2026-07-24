using UnityEngine;
using Wolf.Player;
using Wolf.Player.Cannibal;
using Wolf.Player.Killer;
using Wolf.Player.Survivor;

namespace Wolf.AI
{
    /// <summary>
    /// Chases the nearest prey it can sense and wanders when it senses none.
    /// Victims are the primary target; a mercenary who gets close or loud is
    /// worth turning on too, which is what makes crouch-sneaking matter. How far
    /// the psycho senses a given target is shrunk by crouching and swollen by
    /// sprinting or a lit torch (see <see cref="NoiseRadius"/>).
    /// </summary>
    [RequireComponent(typeof(CannibalController))]
    public class CannibalBotBrain : BotBrainBase
    {
        [SerializeField] private float senseRadius = 15f;
        [Tooltip("Base radius at which a mercenary is noticed (before noise modifiers).")]
        [SerializeField] private float killerAggroRadius = 6f;

        private CannibalController _cannibal;
        private Vector3 _wanderDir = Vector3.forward;
        private float _wanderTimer;

        protected override void Awake()
        {
            base.Awake();
            _cannibal = GetComponent<CannibalController>();
        }

        protected override void Tick(float deltaTime)
        {
            PrimaryPressed = false;
            AbilityPressed = false;
            Sprint = false;

            PlayerControllerBase prey = FindNearestPrey(out bool preyIsSurvivor, out float distance);
            if (prey == null)
            {
                Wander(deltaTime);
                return;
            }

            SteerTowards(prey.transform.position - transform.position);
            Sprint = true;

            // Only victims get grabbed and dragged to the table; mercs just get mauled.
            if (preyIsSurvivor && distance <= _cannibal.GrabRange)
            {
                AbilityPressed = true;
            }
            if (distance <= _cannibal.AttackRange)
            {
                PrimaryPressed = true;
            }
        }

        private void Wander(float deltaTime)
        {
            _wanderTimer -= deltaTime;
            if (_wanderTimer <= 0f)
            {
                float angle = Random.Range(0f, 360f);
                _wanderDir = Quaternion.Euler(0f, angle, 0f) * Vector3.forward;
                _wanderTimer = Random.Range(2f, 5f);
            }

            SteerTowards(_wanderDir);
        }

        private PlayerControllerBase FindNearestPrey(out bool isSurvivor, out float bestDistance)
        {
            isSurvivor = false;
            bestDistance = float.MaxValue;
            PlayerControllerBase best = null;

            // Overlap a generous radius; per-target noise decides what's actually sensed.
            float overlap = Mathf.Max(senseRadius, killerAggroRadius) + 6f;
            Collider[] hits = Physics.OverlapSphere(transform.position, overlap);

            foreach (Collider hit in hits)
            {
                if (hit.TryGetComponent(out SurvivorController survivor))
                {
                    if (survivor.Health.IsDead || survivor.IsGrabbed)
                    {
                        continue;
                    }

                    float distance = Vector3.Distance(transform.position, survivor.transform.position);
                    if (distance <= NoiseRadius(survivor, senseRadius) && distance < bestDistance)
                    {
                        bestDistance = distance;
                        best = survivor;
                        isSurvivor = true;
                    }
                }
                else if (hit.TryGetComponent(out KillerController killer))
                {
                    if (killer.Health.IsDead)
                    {
                        continue;
                    }

                    float distance = Vector3.Distance(transform.position, killer.transform.position);
                    if (distance <= NoiseRadius(killer, killerAggroRadius) && distance < bestDistance)
                    {
                        bestDistance = distance;
                        best = killer;
                        isSurvivor = false;
                    }
                }
            }

            return best;
        }

        private static float NoiseRadius(PlayerControllerBase target, float baseRadius)
        {
            float radius = baseRadius;
            if (target.IsCrouching)
            {
                radius *= 0.4f;
            }
            if (target.IsSprinting)
            {
                radius += 3f;
            }
            if (target is SurvivorController survivor && survivor.FlashlightOn)
            {
                radius += 4f;
            }
            return radius;
        }
    }
}
