using UnityEngine;
using Wolf.Health;
using Wolf.Player;
using Wolf.Player.Guest;
using Wolf.Player.Killer;
using Wolf.Utils;

namespace Wolf.Objectives
{
    /// <summary>
    /// The Witch's poisoned growth, filling a doorway. Solid to guests, thin
    /// air to killers — that asymmetry is the whole power, so it's enforced
    /// here with explicit collision ignores rather than by hoping the project
    /// has the right physics layers set up.
    ///
    /// A guest can still tear it open by hand. It takes time and it costs blood.
    /// </summary>
    [RequireComponent(typeof(BoxCollider))]
    public class ThicketBarrier : MonoBehaviour, IInteractable
    {
        [SerializeField] private float tearSeconds = 3.2f;
        [SerializeField] private float thornDamagePerSecond = 16f;
        [SerializeField] private float tearDamagePerSecond = 7f;

        private DoorwayMarker _doorway;
        private BoxCollider _solid;
        private BoxCollider _sting;
        private float _lifetime = 50f;
        private float _tearProgress;
        private GuestController _tearer;

        public string InteractionPrompt => $"Рвать заросли... {Mathf.RoundToInt(_tearProgress / tearSeconds * 100f)}%";

        public bool CanInteract(PlayerControllerBase interactor) =>
            interactor is GuestController guest && !guest.IsDowned;

        public void Interact(PlayerControllerBase interactor)
        {
            if (interactor is GuestController guest)
            {
                _tearer = _tearer == guest ? null : guest;
            }
        }

        private void Awake()
        {
            _solid = GetComponent<BoxCollider>();
            _solid.isTrigger = false;

            // A second, slightly larger trigger does the stinging. Two colliders
            // on one object is the cheapest way to be both a wall and a hazard.
            _sting = gameObject.AddComponent<BoxCollider>();
            _sting.isTrigger = true;
            _sting.size = _solid.size + new Vector3(0.6f, 0f, 0.6f);
            _sting.center = _solid.center;
        }

        /// <summary>Called by the Witch right after the prefab is instantiated.</summary>
        public void Grow(DoorwayMarker doorway, float lifetime)
        {
            _doorway = doorway;
            _lifetime = lifetime;
            doorway?.SetBlocked(true);

            if (_doorway != null)
            {
                Vector3 size = _solid.size;
                size.x = _doorway.width;
                _solid.size = size;
                _sting.size = size + new Vector3(0.6f, 0f, 0.6f);
            }

            IgnoreKillers();
        }

        /// <summary>Her own quarter doesn't grow shut in her face.</summary>
        private void IgnoreKillers()
        {
            foreach (KillerControllerBase killer in FindObjectsOfType<KillerControllerBase>())
            {
                if (killer.TryGetComponent(out CharacterController body))
                {
                    Physics.IgnoreCollision(_solid, body, true);
                }
            }
        }

        private void Update()
        {
            _lifetime -= Time.deltaTime;
            if (_lifetime <= 0f)
            {
                Wither();
                return;
            }

            TickTear(Time.deltaTime);
        }

        private void TickTear(float dt)
        {
            if (_tearer == null)
            {
                return;
            }

            bool stillTearing = _tearer.IsInPlay
                && !_tearer.IsDowned
                && _tearer.Intent.InteractHeld
                && Vector3.Distance(_tearer.transform.position, transform.position) <= 3f;

            if (!stillTearing)
            {
                _tearer = null;
                return;
            }

            _tearProgress += dt;
            _tearer.Health.TakeDamage(new DamageInfo(tearDamagePerSecond * dt, gameObject));

            if (_tearProgress >= tearSeconds)
            {
                Wither();
            }
        }

        private void OnTriggerStay(Collider other)
        {
            if (!other.TryGetComponent(out GuestController guest) || !guest.IsInPlay || guest.IsDowned)
            {
                return;
            }

            guest.Health.TakeDamage(new DamageInfo(thornDamagePerSecond * Time.deltaTime, gameObject));
        }

        private void Wither()
        {
            _doorway?.SetBlocked(false);
            Destroy(gameObject);
        }

        private void OnDestroy()
        {
            _doorway?.SetBlocked(false);
        }
    }
}
