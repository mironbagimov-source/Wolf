using UnityEngine;
using Wolf.Player.Cannibal;
using Wolf.Player.Survivor;

namespace Wolf.AI
{
    /// <summary>Chases the nearest living, ungrabbed Survivor in range; wanders when none are sensed.</summary>
    [RequireComponent(typeof(CannibalController))]
    public class CannibalBotBrain : BotBrainBase
    {
        [SerializeField] private float senseRadius = 15f;

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

            SurvivorController target = FindNearestSurvivor();
            if (target == null)
            {
                Wander(deltaTime);
                return;
            }

            Vector3 toTarget = target.transform.position - transform.position;
            SteerTowards(toTarget);
            Sprint = true;

            float distance = toTarget.magnitude;
            if (distance <= _cannibal.GrabRange)
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

        private SurvivorController FindNearestSurvivor()
        {
            Collider[] hits = Physics.OverlapSphere(transform.position, senseRadius);
            SurvivorController nearest = null;
            float nearestDist = float.MaxValue;

            foreach (Collider hit in hits)
            {
                if (!hit.TryGetComponent(out SurvivorController survivor) || survivor.Health.IsDead || survivor.IsGrabbed)
                {
                    continue;
                }

                float distance = Vector3.Distance(transform.position, survivor.transform.position);
                if (distance < nearestDist)
                {
                    nearestDist = distance;
                    nearest = survivor;
                }
            }

            return nearest;
        }
    }
}
