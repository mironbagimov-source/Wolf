using UnityEngine;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Player.Guest;
using Wolf.Player.Killer;

namespace Wolf.AI
{
    /// <summary>
    /// Hunts the nearest guest it can hear, and knows what to do with a body:
    /// carry it to a hook, or — if it's the Witch, who carries nobody — kneel
    /// down where it fell. Patrols the breakers when it senses nothing, because
    /// that's where the guests have to keep coming back to.
    /// </summary>
    [RequireComponent(typeof(KillerControllerBase))]
    public class KillerBotBrain : BotBrainBase
    {
        [SerializeField] private float senseRadius = 18f;
        [SerializeField] private float sprintNoiseBonus = 5f;
        [SerializeField] private float flashlightNoiseBonus = 6f;
        [SerializeField] private float crouchNoiseMalus = 7f;
        [SerializeField] private float downedSenseRadius = 26f;
        [SerializeField] private float patrolRepickSeconds = 12f;

        private KillerControllerBase _killer;
        private BreakerObjective _patrolTarget;
        private float _patrolTimer;

        protected override void Awake()
        {
            base.Awake();
            _killer = GetComponent<KillerControllerBase>();
        }

        protected override void Tick(float deltaTime)
        {
            Sprint = true;
            InteractHeld = false;

            if (_killer.CarriedGuest != null)
            {
                CarryToHook();
                return;
            }

            GuestController target = SenseGuest();
            if (target == null)
            {
                Patrol(deltaTime);
                return;
            }

            float distance = Vector3.Distance(transform.position, target.transform.position);
            MoveTowards(target.transform.position);

            if (target.IsDowned)
            {
                if (distance <= 2.3f)
                {
                    Stand();
                    InteractPressed = true;
                    InteractHeld = true;   // the Witch needs the hold; the others ignore it
                }
                return;
            }

            if (distance <= _killer.PrimaryRange * 0.95f)
            {
                PrimaryPressed = true;
            }

            UseArchetypePowers(distance);
        }

        /// <summary>The one place the bot has to know which killer it is driving.</summary>
        private void UseArchetypePowers(float distance)
        {
            switch (_killer.Archetype)
            {
                case KillerArchetype.Trickster:
                    if (distance > 3f && distance < 15f) Power1Pressed = true;    // leash them in
                    if (distance > 6f) Power2Pressed = true;                      // send the doubles ahead
                    if (distance <= 3f) SecondaryPressed = true;                  // scythe range
                    break;

                case KillerArchetype.Witch:
                    if (distance > 2.5f && distance < 13f) SecondaryPressed = true;  // ivy
                    if (distance > 7f) Power1Pressed = true;                          // seal a doorway behind them
                    break;

                case KillerArchetype.JollyRoger:
                    if (distance <= 2.6f) SecondaryPressed = true;                 // snatch
                    else if (distance > 6f && distance < 20f) Power1Pressed = true; // charge
                    break;
            }
        }

        private void CarryToHook()
        {
            HookObjective best = null;
            float bestDistance = float.MaxValue;

            foreach (HookObjective hook in FindObjectsOfType<HookObjective>())
            {
                if (!hook.IsFree)
                {
                    continue;
                }

                float distance = Vector3.Distance(transform.position, hook.transform.position);
                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    best = hook;
                }
            }

            if (best == null)
            {
                Wander(Time.deltaTime);
                return;
            }

            MoveTowards(best.transform.position);
            if (bestDistance <= 2.4f)
            {
                Stand();
                InteractPressed = true;
            }
        }

        private GuestController SenseGuest()
        {
            if (GameManager.Instance == null)
            {
                return null;
            }

            GuestController best = null;
            float bestScore = float.MaxValue;

            foreach (GuestController guest in GameManager.Instance.Guests)
            {
                if (guest == null || !guest.IsInPlay)
                {
                    continue;
                }
                if (guest.State == GuestController.GuestState.Carried || guest.State == GuestController.GuestState.Hooked)
                {
                    continue;
                }

                float radius = senseRadius + Noisiness(guest);
                if (guest.IsDowned)
                {
                    radius = Mathf.Max(radius, downedSenseRadius);
                }

                float distance = Vector3.Distance(transform.position, guest.transform.position);
                if (distance > radius)
                {
                    continue;
                }

                if (distance < bestScore)
                {
                    bestScore = distance;
                    best = guest;
                }
            }

            return best;
        }

        private float Noisiness(GuestController guest)
        {
            float bonus = 0f;
            if (guest.IsSprinting) bonus += sprintNoiseBonus;
            if (guest.FlashlightOn) bonus += flashlightNoiseBonus;
            if (guest.IsCrouching) bonus -= crouchNoiseMalus;
            if (guest.IsInjured) bonus += 2f;
            return bonus;
        }

        private void Patrol(float deltaTime)
        {
            _patrolTimer -= deltaTime;
            if (_patrolTarget == null || _patrolTarget.IsOnline || _patrolTimer <= 0f)
            {
                _patrolTarget = PickPatrolBreaker();
                _patrolTimer = patrolRepickSeconds;
            }

            if (_patrolTarget == null)
            {
                Wander(deltaTime);
                return;
            }

            MoveTowards(_patrolTarget.transform.position);
        }

        private BreakerObjective PickPatrolBreaker()
        {
            BreakerObjective[] all = FindObjectsOfType<BreakerObjective>();
            BreakerObjective best = null;
            int candidates = 0;

            foreach (BreakerObjective breaker in all)
            {
                if (breaker.IsOnline)
                {
                    continue;
                }

                candidates++;
                if (Random.Range(0, candidates) == 0)   // reservoir pick: one unlit breaker at random
                {
                    best = breaker;
                }
            }

            return best;
        }
    }
}
