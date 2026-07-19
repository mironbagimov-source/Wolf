using UnityEngine;
using Wolf.Player;
using Wolf.Utils;

namespace Wolf.AI
{
    /// <summary>
    /// Drives a PlayerControllerBase by acting as its IInputProvider instead
    /// of reading hardware. Runs before PlayerControllerBase's Update via
    /// DefaultExecutionOrder so the input it computes this frame is already
    /// set when the controller reads it.
    ///
    /// Movement here is a placeholder "sense and steer" brain, not real
    /// pathfinding — swap the wander logic for NavMeshAgent-based navigation
    /// once the tour-base scene has a baked NavMesh (an Editor-only step).
    /// </summary>
    [DefaultExecutionOrder(-100)]
    public abstract class BotBrainBase : MonoBehaviour, IInputProvider
    {
        public Vector2 Move { get; protected set; }
        public Vector2 Look { get; protected set; }
        public bool Sprint { get; protected set; }
        public bool Crouch { get; protected set; }
        public bool InteractPressed { get; protected set; }
        public bool PrimaryPressed { get; protected set; }
        public bool SecondaryHeld { get; protected set; }
        public bool AbilityPressed { get; protected set; }
        public bool FlashlightPressed { get; protected set; }

        protected PlayerControllerBase controller;

        protected virtual void Awake()
        {
            controller = GetComponent<PlayerControllerBase>();
        }

        private void Update()
        {
            Tick(Time.deltaTime);
        }

        protected abstract void Tick(float deltaTime);

        /// <summary>Turns a desired world-space direction into transform-relative Move/Look values.</summary>
        protected void SteerTowards(Vector3 worldDirection)
        {
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
    }
}
