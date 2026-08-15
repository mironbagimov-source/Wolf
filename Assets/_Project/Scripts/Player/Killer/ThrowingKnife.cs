using UnityEngine;
using Wolf.Core;
using Wolf.Health;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// A thrown knife: flies straight along the direction it was launched,
    /// damaging the first enemy HealthComponent it reaches, then despawns. It
    /// self-propels and raycasts each frame, so the prefab only needs this
    /// component plus a visual mesh — no Rigidbody or collider setup required.
    /// The thrower sets range/speed/damage via <see cref="Launch"/>.
    /// </summary>
    public class ThrowingKnife : MonoBehaviour
    {
        [SerializeField] private float spinSpeed = 1080f; // deg/sec, purely cosmetic

        private GameObject _owner;
        private FactionType _ownerFaction;
        private float _damage;
        private float _speed;
        private float _remainingRange;
        private bool _spent;

        /// <summary>Arm the knife. Call right after Instantiate, before it moves.</summary>
        public void Launch(GameObject owner, FactionType ownerFaction, float damage, float speed, float range)
        {
            _owner = owner;
            _ownerFaction = ownerFaction;
            _damage = damage;
            _speed = speed;
            _remainingRange = range;
        }

        private void Update()
        {
            if (_spent)
            {
                return;
            }

            float step = _speed * Time.deltaTime;

            if (Physics.Raycast(transform.position, transform.forward, out RaycastHit hit, step))
            {
                TryHit(hit);
                if (_spent)
                {
                    return;
                }
            }

            transform.position += transform.forward * step;
            transform.Rotate(Vector3.forward * spinSpeed * Time.deltaTime, Space.Self);

            _remainingRange -= step;
            if (_remainingRange <= 0f)
            {
                Destroy(gameObject);
            }
        }

        private void TryHit(RaycastHit hit)
        {
            // Never hit the thrower themselves.
            if (_owner != null && (hit.collider.gameObject == _owner || hit.collider.transform.IsChildOf(_owner.transform)))
            {
                return;
            }

            if (hit.collider.TryGetComponent(out HealthComponent target))
            {
                // Don't knife your own side.
                if (hit.collider.TryGetComponent(out PlayerControllerBase pc) && pc.Faction == _ownerFaction)
                {
                    return;
                }

                float damage = _damage;
                if (hit.collider.TryGetComponent(out KillerController blocker))
                {
                    damage *= blocker.GetIncomingDamageMultiplier();
                }

                target.TakeDamage(new DamageInfo(damage, _owner, hit.point));
            }

            // Whatever it struck — enemy, wall, or prop — the knife is spent.
            _spent = true;
            Destroy(gameObject);
        }
    }
}
