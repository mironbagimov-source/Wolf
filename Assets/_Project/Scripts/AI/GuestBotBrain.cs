using UnityEngine;
using Wolf.Core;
using Wolf.Objectives;
using Wolf.Player.Guest;
using Wolf.Player.Killer;

namespace Wolf.AI
{
    /// <summary>
    /// A guest with a to-do list and a survival instinct, in that order of
    /// interruption: run from whatever is close, take a friend off a hook,
    /// lift a friend off the ground, fix a breaker, then leave.
    /// </summary>
    [RequireComponent(typeof(GuestController))]
    public class GuestBotBrain : BotBrainBase
    {
        [SerializeField] private float fleeRadius = 13f;
        [SerializeField] private float interactDistance = 2.4f;
        [SerializeField] private float rescueAbandonDistance = 12f;

        private GuestController _guest;

        protected override void Awake()
        {
            base.Awake();
            _guest = GetComponent<GuestController>();
        }

        protected override void Tick(float deltaTime)
        {
            Sprint = false;
            InteractHeld = false;

            if (_guest.State == GuestController.GuestState.Carried || _guest.State == GuestController.GuestState.Hooked)
            {
                Stand();
                StrugglePressed = Random.value < 0.35f;   // bots wriggle too, just badly
                return;
            }

            KillerControllerBase killer = FindKiller();
            float killerDistance = killer != null
                ? Vector3.Distance(transform.position, killer.transform.position)
                : float.MaxValue;

            if (_guest.IsDowned)
            {
                Crawl(killer, killerDistance);
                return;
            }

            if (killer != null && killerDistance < fleeRadius)
            {
                SteerTowards(transform.position - killer.transform.position);
                Sprint = true;
                return;
            }

            if (TryRescueFromHook(killer)) return;
            if (TryLiftTeammate(killer)) return;
            if (TryRepairBreaker()) return;
            if (TryLeave()) return;

            Wander(deltaTime);
        }

        private void Crawl(KillerControllerBase killer, float killerDistance)
        {
            if (killer != null && killerDistance < 14f)
            {
                SteerTowards(transform.position - killer.transform.position);
            }
            else
            {
                Stand();
            }
        }

        private bool TryRescueFromHook(KillerControllerBase killer)
        {
            foreach (HookObjective hook in FindObjectsOfType<HookObjective>())
            {
                if (hook.Captive == null || hook.Captive == _guest)
                {
                    continue;
                }
                if (killer != null && Vector3.Distance(killer.transform.position, hook.transform.position) < rescueAbandonDistance)
                {
                    continue;   // walking into the killer's lap saves nobody
                }

                MoveTowards(hook.transform.position);
                Sprint = true;
                if (Vector3.Distance(transform.position, hook.transform.position) <= interactDistance)
                {
                    Stand();
                    InteractPressed = true;
                }
                return true;
            }

            return false;
        }

        private bool TryLiftTeammate(KillerControllerBase killer)
        {
            if (GameManager.Instance == null)
            {
                return false;
            }

            foreach (GuestController other in GameManager.Instance.Guests)
            {
                if (other == null || other == _guest || !other.IsDowned)
                {
                    continue;
                }
                if (killer != null && Vector3.Distance(killer.transform.position, other.transform.position) < 10f)
                {
                    continue;
                }

                MoveTowards(other.transform.position);
                Sprint = true;
                if (Vector3.Distance(transform.position, other.transform.position) <= interactDistance)
                {
                    Stand();
                    InteractPressed = true;
                    InteractHeld = true;
                }
                return true;
            }

            return false;
        }

        private bool TryRepairBreaker()
        {
            if (GameManager.Instance != null && GameManager.Instance.BreachOpen)
            {
                return false;
            }

            BreakerObjective best = null;
            float bestScore = float.MaxValue;

            foreach (BreakerObjective breaker in FindObjectsOfType<BreakerObjective>())
            {
                if (breaker.IsOnline)
                {
                    continue;
                }

                float score = Vector3.Distance(transform.position, breaker.transform.position);
                score -= breaker.Progress01 * 6f;   // finish what somebody started
                if (score < bestScore)
                {
                    bestScore = score;
                    best = breaker;
                }
            }

            if (best == null)
            {
                return false;
            }

            MoveTowards(best.transform.position);
            if (Vector3.Distance(transform.position, best.transform.position) <= interactDistance)
            {
                Stand();
                InteractPressed = true;
                InteractHeld = true;
            }
            else
            {
                Sprint = bestScore > 10f;
            }

            return true;
        }

        private bool TryLeave()
        {
            if (GameManager.Instance == null || !GameManager.Instance.BreachOpen)
            {
                return false;
            }

            BreachTrigger breach = FindObjectOfType<BreachTrigger>();
            if (breach == null)
            {
                return false;
            }

            MoveTowards(breach.transform.position);
            Sprint = true;
            return true;
        }

        private KillerControllerBase FindKiller()
        {
            KillerControllerBase[] killers = FindObjectsOfType<KillerControllerBase>();
            return killers.Length > 0 ? killers[0] : null;
        }
    }
}
