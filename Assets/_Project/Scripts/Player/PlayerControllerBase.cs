using UnityEngine;
using Wolf.AI;
using Wolf.Core;
using Wolf.Health;
using Wolf.Utils;

namespace Wolf.Player
{
    /// <summary>
    /// Shared first-person locomotion, look, and interaction for all three
    /// factions. Faction-specific abilities live in the subclasses
    /// (Survivor/Cannibal/Killer). Reads an IInputProvider rather than
    /// hardware input directly, so a BotBrainBase on the same GameObject can
    /// drive this exact same code in BotMatch — see Utils/IInputProvider.cs.
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    [RequireComponent(typeof(HealthComponent))]
    public abstract class PlayerControllerBase : MonoBehaviour
    {
        [Header("Movement")]
        [SerializeField] protected float walkSpeed = 3.5f;
        [SerializeField] protected float sprintSpeed = 6f;
        [SerializeField] protected float crouchSpeed = 1.5f;
        [SerializeField] protected float gravity = -20f;

        [Header("Look")]
        [SerializeField] protected Transform cameraPivot;
        [SerializeField] protected float mouseSensitivity = 2f;
        [SerializeField] protected float minPitch = -80f;
        [SerializeField] protected float maxPitch = 80f;

        [Header("Interaction")]
        [SerializeField] protected float interactRange = 2.5f;
        [SerializeField] protected LayerMask interactMask = ~0;

        /// <summary>Which side this instance belongs to — set by the concrete subclass.</summary>
        public abstract FactionType Faction { get; }

        public HealthComponent Health { get; private set; }
        public bool IsCrouching { get; private set; }
        public bool IsSprinting { get; private set; }

        /// <summary>Name of the chosen character archetype (local human only; null for bots).</summary>
        public string CharacterName { get; private set; }

        /// <summary>
        /// The one human-controlled instance on this machine — what the HUD
        /// reads from. Fine for BotMatch/Multiplayer (one human per client);
        /// LocalSplitscreen will need a per-instance HUD instead once built.
        /// </summary>
        public static PlayerControllerBase LocalPlayer { get; private set; }

        protected CharacterController controller;
        protected IInputProvider input;
        private float _pitch;
        private float _verticalVelocity;
        private bool _inputLocked;

        protected virtual void Awake()
        {
            controller = GetComponent<CharacterController>();
            Health = GetComponent<HealthComponent>();

            // A BotBrainBase on the same GameObject supplies synthetic input;
            // otherwise this is a human-controlled player reading hardware input.
            if (GetComponent<BotBrainBase>() is IInputProvider botInput)
            {
                input = botInput;
            }
            else
            {
                input = new HardwareInputProvider();
                LocalPlayer = this;
            }
        }

        protected virtual void Start()
        {
            bool isCultLeader = GetComponent<CultLeaderMarker>() != null;
            GameManager.Instance?.RegisterPlayer(Faction, Health, isCultLeader);

            // The local human applies their chosen character; bots keep prefab defaults.
            if (LocalPlayer == this)
            {
                ApplyArchetype(CharacterRoster.Get(Faction, PlayerSelection.ChosenCharacterIndex));
            }
        }

        /// <summary>
        /// Folds a chosen character's modifiers onto this instance. The base applies
        /// the universal ones (speed, max health); subclasses override to add their
        /// own (Killer knife stock and block, melee damage) and must call base first.
        /// </summary>
        protected virtual void ApplyArchetype(CharacterArchetype archetype)
        {
            CharacterName = archetype.name;
            walkSpeed *= archetype.speedMul;
            sprintSpeed *= archetype.speedMul;
            crouchSpeed *= archetype.speedMul;
            Health.ConfigureMaxHealth(Health.MaxHealth * archetype.hpMul);
        }

        protected virtual void Update()
        {
            if (_inputLocked || Health.IsDead)
            {
                return;
            }

            HandleLook();
            HandleMove();

            if (input.InteractPressed)
            {
                TryInteract();
            }
        }

        /// <summary>Disables movement/look/interact input — used while grabbed, on the altar, etc.</summary>
        public void SetInputLocked(bool locked) => _inputLocked = locked;

        private void HandleLook()
        {
            Vector2 look = input.Look * mouseSensitivity;

            transform.Rotate(Vector3.up * look.x);

            _pitch = Mathf.Clamp(_pitch - look.y, minPitch, maxPitch);
            if (cameraPivot != null)
            {
                cameraPivot.localEulerAngles = new Vector3(_pitch, 0f, 0f);
            }
        }

        private void HandleMove()
        {
            IsCrouching = input.Crouch;
            IsSprinting = !IsCrouching && input.Sprint;

            float speed = IsCrouching ? crouchSpeed : (IsSprinting ? sprintSpeed : walkSpeed);
            speed = ApplySpeedModifier(speed);

            Vector2 axis = input.Move;
            Vector3 move = transform.right * axis.x + transform.forward * axis.y;
            if (move.sqrMagnitude > 1f)
            {
                move.Normalize();
            }

            if (controller.isGrounded && _verticalVelocity < 0f)
            {
                _verticalVelocity = -1f;
            }
            _verticalVelocity += gravity * Time.deltaTime;

            Vector3 velocity = move * speed;
            velocity.y = _verticalVelocity;
            controller.Move(velocity * Time.deltaTime);
        }

        /// <summary>Hook for faction-specific speed buffs/debuffs (e.g. Cannibal sprint bonus).</summary>
        protected virtual float ApplySpeedModifier(float baseSpeed) => baseSpeed;

        private void TryInteract()
        {
            if (cameraPivot == null)
            {
                return;
            }

            if (Physics.Raycast(cameraPivot.position, cameraPivot.forward, out RaycastHit hit, interactRange, interactMask))
            {
                if (hit.collider.TryGetComponent(out IInteractable interactable) && interactable.CanInteract(this))
                {
                    interactable.Interact(this);
                }
            }
        }
    }
}
