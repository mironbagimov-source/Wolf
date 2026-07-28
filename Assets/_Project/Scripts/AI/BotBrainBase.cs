using UnityEngine;
using UnityEngine.AI;
using Wolf.Player;
using Wolf.Utils;

namespace Wolf.AI
{
    /// <summary>
    /// Drives a PlayerControllerBase by acting as its IInputProvider instead of
    /// reading hardware. Runs before PlayerControllerBase's Update via
    /// DefaultExecutionOrder so the input it computes this frame is already set
    /// when the controller reads it.
    ///
    /// Navigation: if a NavMeshAgent is present it is used for pathing only —
    /// the CharacterController still does the moving, so the agent is set to
    /// not update the transform and is kept in sync every frame. Without a
    /// baked NavMesh the brains fall back to straight-line steering, which is
    /// fine on open ground and visibly bad in a quarter full of doorways. Bake
    /// the NavMesh (an Editor-only step) before judging the bots.
    /// </summary>
    [DefaultExecutionOrder(-100)]
    public abstract class BotBrainBase : MonoBehaviour, IInputProvider
    {
        public Vector2 Move { get; protected set; }
        public Vector2 Look { get; protected set; }
        public bool Sprint { get; protected set; }
        public bool Crouch { get; protected set; }
        public bool InteractPressed { get; protected set; }
        public bool InteractHeld { get; protected set; }
        public bool PrimaryPressed { get; protected set; }
        public bool SecondaryPressed { get; protected set; }
        public bool Power1Pressed { get; protected set; }
        public bool Power2Pressed { get; protected set; }
        public bool DropPressed { get; protected set; }
        public bool StrugglePressed { get; protected set; }
        public bool FlashlightPressed { get; protected set; }

        protected PlayerControllerBase controller;
        protected NavMeshAgent agent;

        private Vector3 _wanderDirection = Vector3.forward;
        private float _wanderTimer;

        protected virtual void Awake()
        {
            controller = GetComponent<PlayerControllerBase>();

            agent = GetComponent<NavMeshAgent>();
            if (agent != null)
            {
                agent.updatePosition = false;
                agent.updateRotation = false;
            }
        }

        private void Update()
        {
            ClearOneShots();

            if (agent != null && agent.isOnNavMesh)
            {
                agent.nextPosition = transform.position;   // pathing only; the CharacterController drives
            }

            Tick(Time.deltaTime);
        }

        /// <summary>Presses are per-frame edges; a brain that forgets to clear them holds the button forever.</summary>
        private void ClearOneShots()
        {
            InteractPressed = false;
            PrimaryPressed = false;
            SecondaryPressed = false;
            Power1Pressed = false;
            Power2Pressed = false;
            DropPressed = false;
            StrugglePressed = false;
            FlashlightPressed = false;
        }

        protected abstract void Tick(float deltaTime);

        /// <summary>Head for a world position, around corners if there's a NavMesh to do it with.</summary>
        protected void MoveTowards(Vector3 worldTarget)
        {
            if (agent != null && agent.isOnNavMesh)
            {
                agent.SetDestination(worldTarget);
                Vector3 desired = agent.desiredVelocity;
                SteerTowards(desired.sqrMagnitude > 0.01f ? desired : worldTarget - transform.position);
                return;
            }

            SteerTowards(worldTarget - transform.position);
        }

        /// <summary>Turns a desired world-space direction into transform-relative Move/Look values.</summary>
        protected void SteerTowards(Vector3 worldDirection)
        {
            worldDirection.y = 0f;
            if (worldDirection.sqrMagnitude < 0.0001f)
            {
                Move = Vector2.zero;
                Look = Vector2.zero;
                return;
            }

            worldDirection.Normalize();
            float signedAngle = Vector3.SignedAngle(transform.forward, worldDirection, Vector3.up);

            Look = new Vector2(Mathf.Clamp(signedAngle, -90f, 90f) * 0.05f, 0f);
            Move = new Vector2(0f, Mathf.Clamp01(Vector3.Dot(transform.forward, worldDirection) + 0.5f));
        }

        protected void Wander(float deltaTime)
        {
            _wanderTimer -= deltaTime;
            if (_wanderTimer <= 0f)
            {
                _wanderDirection = Quaternion.Euler(0f, Random.Range(0f, 360f), 0f) * Vector3.forward;
                _wanderTimer = Random.Range(2f, 5f);
            }

            SteerTowards(_wanderDirection);
        }

        protected void Stand()
        {
            Move = Vector2.zero;
            Look = Vector2.zero;
        }
    }
}
