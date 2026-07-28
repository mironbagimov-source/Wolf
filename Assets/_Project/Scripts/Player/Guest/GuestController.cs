using UnityEngine;
using Wolf.Core;
using Wolf.Health;
using Wolf.Utils;

namespace Wolf.Player.Guest
{
    /// <summary>
    /// One of the four people locked in the quarter. No weapon, no fighting
    /// back: repair breakers, pick your teammates up, and get to the breach.
    ///
    /// Running out of health does not kill a guest — it puts them on the
    /// ground, where the match actually gets decided. From there they bleed
    /// out, get lifted by a teammate, or get carried to a hook.
    /// </summary>
    public class GuestController : PlayerControllerBase, IInteractable
    {
        public enum GuestState
        {
            Standing,
            Downed,
            Carried,
            Hooked,
            Escaped,
            Gone,
        }

        [Header("Guest")]
        [SerializeField] private Light flashlight;
        [SerializeField] private float staminaSeconds = 5f;
        [SerializeField] private float staminaRegenPerSecond = 0.7f;
        [SerializeField] private float crawlSpeed = 1.05f;
        [SerializeField] private float injuredHealthFraction = 0.5f;

        public override FactionType Faction => FactionType.Guest;

        public GuestState State { get; private set; } = GuestState.Standing;
        public bool IsInPlay => State != GuestState.Escaped && State != GuestState.Gone;
        public bool IsDowned => State == GuestState.Downed;
        public bool IsInjured => Health.CurrentHealth <= Health.MaxHealth * injuredHealthFraction;
        public bool FlashlightOn { get; private set; }
        public float Stamina { get; private set; }
        public float BleedoutRemaining { get; private set; }
        public float StruggleProgress { get; private set; }
        public string DisplayName => _identity != null ? _identity.guestName : name;

        private GuestIdentity _identity;
        private MatchSettings _settings;
        private PlayerControllerBase _reviver;
        private float _reviveProgress;
        private float _rootTimer;

        protected override void Awake()
        {
            base.Awake();
            _identity = GetComponent<GuestIdentity>();

            // Guests go down, they don't drop dead — see HealthComponent.
            Health.DiesAtZero = false;
            Health.Depleted += OnHealthDepleted;
            Health.Died += _ => EnterGone();
        }

        private void Start()
        {
            _settings = GameManager.Instance != null ? GameManager.Instance.Settings : null;
            Stamina = staminaSeconds;
            GameManager.Instance?.RegisterGuest(this);
        }

        protected override bool CanCrouch => State == GuestState.Standing;
        protected override bool CanSprint => State == GuestState.Standing && Stamina > 0f;

        protected override float ApplySpeedModifier(float baseSpeed)
        {
            return State == GuestState.Downed ? crawlSpeed : baseSpeed;
        }

        protected override void Update()
        {
            base.Update();

            TickStamina(Time.deltaTime);
            TickRoot(Time.deltaTime);
            TickBleedout(Time.deltaTime);
            TickRevive(Time.deltaTime);
            TickStruggle(Time.deltaTime);

            if (State == GuestState.Standing && Intent.FlashlightPressed)
            {
                ToggleFlashlight();
            }
        }

        private void TickStamina(float dt)
        {
            if (IsSprinting)
            {
                Stamina = Mathf.Max(0f, Stamina - dt);
            }
            else
            {
                Stamina = Mathf.Min(staminaSeconds, Stamina + staminaRegenPerSecond * dt);
            }
        }

        private void TickRoot(float dt)
        {
            if (_rootTimer <= 0f)
            {
                return;
            }

            _rootTimer -= dt;
            if (_rootTimer <= 0f && State != GuestState.Carried && State != GuestState.Hooked)
            {
                SetInputLocked(false);
            }
        }

        private void TickBleedout(float dt)
        {
            if (State != GuestState.Downed)
            {
                return;
            }

            BleedoutRemaining -= dt;
            if (BleedoutRemaining <= 0f)
            {
                Health.Kill(gameObject);
            }
        }

        private void TickRevive(float dt)
        {
            if (State != GuestState.Downed || _reviver == null)
            {
                return;
            }

            bool stillThere = !_reviver.Health.IsDead
                && _reviver.Intent.InteractHeld
                && Vector3.Distance(_reviver.transform.position, transform.position) <= interactRange + 0.5f;

            if (!stillThere)
            {
                _reviver = null;
                _reviveProgress = 0f;
                return;
            }

            _reviveProgress += dt;
            float needed = _settings != null ? _settings.reviveSeconds : 6f;
            if (_reviveProgress >= needed)
            {
                LiftBackUp(_settings != null ? _settings.reviveHealth : 45f);
            }
        }

        private void TickStruggle(float dt)
        {
            if (State != GuestState.Carried)
            {
                return;
            }

            float needed = _settings != null ? _settings.carryStruggleSeconds : 14f;
            if (Intent.StrugglePressed)
            {
                StruggleProgress += 1f / Mathf.Max(1f, needed) * 3f;   // each wriggle is worth ~3 seconds of the meter
            }
            StruggleProgress = Mathf.Max(0f, StruggleProgress - dt / Mathf.Max(1f, needed));

            if (StruggleProgress >= 1f)
            {
                BreakOutOfGrip();
            }
        }

        private void ToggleFlashlight()
        {
            FlashlightOn = !FlashlightOn;
            if (flashlight != null)
            {
                flashlight.enabled = FlashlightOn;
            }
        }

        // --- state transitions ---

        private void OnHealthDepleted(DamageInfo info)
        {
            if (State == GuestState.Standing)
            {
                EnterDowned();
            }
        }

        private void EnterDowned()
        {
            State = GuestState.Downed;
            BleedoutRemaining = _settings != null ? _settings.bleedoutSeconds : 48f;
            _reviveProgress = 0f;
            _reviver = null;
            if (FlashlightOn)
            {
                ToggleFlashlight();
            }
        }

        private void LiftBackUp(float health)
        {
            State = GuestState.Standing;
            _reviver = null;
            _reviveProgress = 0f;
            BleedoutRemaining = 0f;
            Health.SetHealth(health);
            SetInputLocked(false);
        }

        private void EnterGone()
        {
            ICarrier carrier = KillerCarrier;
            KillerCarrier = null;
            State = GuestState.Gone;
            SetInputLocked(true);
            transform.SetParent(null, worldPositionStays: true);

            // Whoever was holding this body doesn't get to keep carrying it.
            carrier?.ReleaseCarriedGuest();

            GameManager.Instance?.ReportGuestLost(this);
        }

        /// <summary>Ivy, or the Trickster's hook landing — you keep the camera, you lose your feet.</summary>
        public void ApplyRoot(float seconds)
        {
            if (!IsInPlay)
            {
                return;
            }

            _rootTimer = Mathf.Max(_rootTimer, seconds);
            SetInputLocked(true);
        }

        /// <summary>Yanked to a new spot by the Trickster's hook shot.</summary>
        public void Displace(Vector3 position)
        {
            controller.enabled = false;
            transform.position = position;
            controller.enabled = true;
        }

        /// <summary>Called by a killer when this guest goes over their shoulder.</summary>
        public void OnPickedUp(Transform carryPoint)
        {
            if (!IsInPlay)
            {
                return;
            }

            if (State == GuestState.Standing)
            {
                EnterDowned();   // Roger snatches people who are still on their feet
            }

            State = GuestState.Carried;
            StruggleProgress = 0f;
            SetInputLocked(true);
            controller.enabled = false;
            transform.SetParent(carryPoint, worldPositionStays: false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
        }

        /// <summary>Dropped on purpose, or wriggled free — either way, back on the ground.</summary>
        public void OnDropped()
        {
            if (State != GuestState.Carried)
            {
                return;
            }

            transform.SetParent(null, worldPositionStays: true);
            controller.enabled = true;
            State = GuestState.Downed;
            SetInputLocked(false);
        }

        private void BreakOutOfGrip()
        {
            KillerCarrier?.ReleaseCarriedGuest();
        }

        /// <summary>Set by whoever is carrying this guest, so a successful struggle can tell them.</summary>
        public ICarrier KillerCarrier { get; set; }

        /// <summary>Hung on a meat hook — the timer that ends the match starts here.</summary>
        public void OnHung(Transform anchor)
        {
            transform.SetParent(anchor, worldPositionStays: false);
            transform.localPosition = Vector3.zero;
            transform.localRotation = Quaternion.identity;
            controller.enabled = false;
            State = GuestState.Hooked;
            SetInputLocked(true);
        }

        public void OnUnhooked(float health)
        {
            transform.SetParent(null, worldPositionStays: true);
            controller.enabled = true;
            State = GuestState.Standing;
            Health.SetHealth(health);
            SetInputLocked(false);
        }

        public void OnEscaped()
        {
            State = GuestState.Escaped;
            SetInputLocked(true);
            GameManager.Instance?.ReportGuestEscaped(this);
            gameObject.SetActive(false);
        }

        // --- IInteractable: what other people can do to this body ---

        public string InteractionPrompt
        {
            get
            {
                if (State != GuestState.Downed)
                {
                    return string.Empty;
                }
                return _reviver != null
                    ? $"Поднимаем {DisplayName}... {Mathf.RoundToInt(_reviveProgress / Mathf.Max(0.01f, _settings != null ? _settings.reviveSeconds : 6f) * 100f)}%"
                    : $"Поднять {DisplayName}";
            }
        }

        public bool CanInteract(PlayerControllerBase interactor)
        {
            if (State != GuestState.Downed || interactor == this)
            {
                return false;
            }

            // Guests lift each other; killers do something else entirely, and
            // what that is depends on which killer it is.
            return true;
        }

        public void Interact(PlayerControllerBase interactor)
        {
            if (State != GuestState.Downed)
            {
                return;
            }

            if (interactor.Faction == FactionType.Guest)
            {
                _reviver = _reviver == interactor ? null : interactor;
                _reviveProgress = 0f;
                return;
            }

            if (interactor is ICarrier killer)
            {
                killer.OnDownedGuestInteract(this);
            }
        }
    }

    /// <summary>
    /// Implemented by killers. Keeps GuestController from having to know which
    /// killer archetype is standing over it — the Witch answers this differently
    /// from the two who carry.
    /// </summary>
    public interface ICarrier
    {
        void OnDownedGuestInteract(GuestController guest);
        void ReleaseCarriedGuest();
    }
}
