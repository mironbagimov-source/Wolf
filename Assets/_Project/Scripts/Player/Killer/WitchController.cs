using System.Collections.Generic;
using UnityEngine;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Player.Guest;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// The herbalist from the edge of the quarter. She doesn't chase and she
    /// doesn't carry — she closes the doorways, takes your legs out from under
    /// you, and kneels down to finish the job where you fell.
    ///
    /// Her thickets seal a doorway against guests but not against her, which is
    /// how she turns a loop into a dead end.
    /// </summary>
    public class WitchController : KillerControllerBase
    {
        [Header("Ivy (RMB)")]
        [SerializeField] private float ivyRange = 13f;
        [SerializeField] private float ivyCooldown = 9f;
        [SerializeField] private float ivyArcDegrees = 34f;
        [SerializeField] private float ivyRootSeconds = 3.2f;

        [Header("Thicket (Q)")]
        [SerializeField] private GameObject thicketPrefab;
        [SerializeField] private float thicketCooldown = 9f;
        [SerializeField] private float thicketPlantRange = 8f;
        [SerializeField] private float thicketLifetime = 50f;
        [SerializeField] private int maxThickets = 3;

        [Header("Execution (hold E on a downed guest)")]
        [SerializeField] private float executionSeconds = 3.4f;

        public override KillerArchetype Archetype => KillerArchetype.Witch;
        public override bool CanCarry => false;

        public float ExecutionProgress => _executionTarget != null ? _executionTimer / executionSeconds : 0f;
        public int ActiveThickets => _thickets.Count;

        private readonly List<ThicketBarrier> _thickets = new();
        private GuestController _executionTarget;
        private float _executionTimer;

        protected override void Update()
        {
            base.Update();
            TickExecution(Time.deltaTime);
            _thickets.RemoveAll(t => t == null);
        }

        protected override void UseSecondary()
        {
            nextSecondaryTime = Time.time + ivyCooldown;

            GuestController target = FindGuestInCone(ivyRange, ivyArcDegrees, requireLineOfSight: true, includeDowned: false);
            target?.ApplyRoot(ivyRootSeconds);
        }

        protected override void UsePower1()
        {
            if (thicketPrefab == null)
            {
                Debug.LogWarning("[Witch] No thicket prefab assigned — the power does nothing.");
                return;
            }

            if (_thickets.Count >= maxThickets)
            {
                return;
            }

            DoorwayMarker doorway = FindFreeDoorway();
            if (doorway == null)
            {
                return;   // nothing worth sealing nearby; the cooldown is not spent
            }

            nextPower1Time = Time.time + thicketCooldown;

            GameObject instance = Instantiate(thicketPrefab, doorway.transform.position, doorway.transform.rotation);
            if (instance.TryGetComponent(out ThicketBarrier barrier))
            {
                barrier.Grow(doorway, thicketLifetime);
                _thickets.Add(barrier);
            }
            else
            {
                Destroy(instance, thicketLifetime);
            }
        }

        private DoorwayMarker FindFreeDoorway()
        {
            DoorwayMarker best = null;
            float bestDistance = float.MaxValue;

            foreach (DoorwayMarker doorway in FindObjectsOfType<DoorwayMarker>())
            {
                if (doorway.IsBlocked)
                {
                    continue;
                }

                float distance = Vector3.Distance(transform.position, doorway.transform.position);
                if (distance <= thicketPlantRange && distance < bestDistance)
                {
                    bestDistance = distance;
                    best = doorway;
                }
            }

            return best;
        }

        // --- execution ---

        /// <summary>She has no shoulder to put you on. She has roots.</summary>
        public override void OnDownedGuestInteract(GuestController guest)
        {
            _executionTarget = guest;
            _executionTimer = 0f;
        }

        private void TickExecution(float dt)
        {
            if (_executionTarget == null)
            {
                return;
            }

            bool stillValid = _executionTarget.IsDowned
                && Intent.InteractHeld
                && Vector3.Distance(transform.position, _executionTarget.transform.position) <= interactRange + 0.5f;

            if (!stillValid)
            {
                _executionTarget = null;
                _executionTimer = 0f;
                return;
            }

            // The roots hold them still while she works — otherwise a crawling
            // guest would simply leave, and the power could never land.
            _executionTarget.ApplyRoot(0.3f);

            _executionTimer += dt;
            if (_executionTimer >= executionSeconds)
            {
                _executionTarget.Health.Kill(gameObject);
                _executionTarget = null;
                _executionTimer = 0f;
            }
        }
    }
}
