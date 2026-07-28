using System;
using UnityEngine;

namespace Wolf.Health
{
    /// <summary>
    /// Shared health/damage component. Networking authority is handled by the
    /// caller (only the owning client should call TakeDamage in multiplayer) —
    /// this component itself has no networking opinion.
    ///
    /// Guests do not die when the bar empties: they go down. So zero health and
    /// death are two separate events here, and <see cref="diesAtZero"/> decides
    /// whether one implies the other. Killers keep the default; GuestController
    /// turns it off and handles <see cref="Depleted"/> itself.
    /// </summary>
    public class HealthComponent : MonoBehaviour
    {
        [SerializeField] private float maxHealth = 100f;
        [SerializeField] private bool diesAtZero = true;

        public float MaxHealth => maxHealth;
        public float CurrentHealth { get; private set; }
        public bool IsDead { get; private set; }

        public bool DiesAtZero
        {
            get => diesAtZero;
            set => diesAtZero = value;
        }

        public event Action<DamageInfo> Damaged;
        public event Action<DamageInfo> Depleted;   // the bar hit zero
        public event Action<DamageInfo> Died;       // and that was the end of them

        private void Awake()
        {
            CurrentHealth = maxHealth;
        }

        public void TakeDamage(DamageInfo info)
        {
            if (IsDead || info.amount <= 0f)
            {
                return;
            }

            bool wasAboveZero = CurrentHealth > 0f;
            CurrentHealth = Mathf.Max(0f, CurrentHealth - info.amount);
            Damaged?.Invoke(info);

            if (CurrentHealth > 0f || !wasAboveZero)
            {
                return;
            }

            Depleted?.Invoke(info);
            if (diesAtZero)
            {
                IsDead = true;
                Died?.Invoke(info);
            }
        }

        public void Heal(float amount)
        {
            if (IsDead || amount <= 0f)
            {
                return;
            }

            CurrentHealth = Mathf.Min(maxHealth, CurrentHealth + amount);
        }

        /// <summary>Sets health outright — used when a guest is picked back up or taken off a hook.</summary>
        public void SetHealth(float value)
        {
            if (IsDead)
            {
                return;
            }

            CurrentHealth = Mathf.Clamp(value, 0f, maxHealth);
        }

        /// <summary>
        /// Ends it regardless of <see cref="diesAtZero"/> — the hook running out,
        /// bleeding out on the asphalt, or the Witch finishing her work.
        /// </summary>
        public void Kill(GameObject source)
        {
            if (IsDead)
            {
                return;
            }

            CurrentHealth = 0f;
            IsDead = true;
            Died?.Invoke(new DamageInfo(0f, source));
        }
    }
}
