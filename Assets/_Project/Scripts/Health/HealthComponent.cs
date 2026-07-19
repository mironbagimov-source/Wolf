using System;
using UnityEngine;

namespace Wolf.Health
{
    /// <summary>
    /// Shared health/damage component for any faction. Networking authority is
    /// handled by the caller (only the owning client should call TakeDamage in
    /// multiplayer) — this component itself has no networking opinion.
    /// </summary>
    public class HealthComponent : MonoBehaviour
    {
        [SerializeField] private float maxHealth = 100f;

        public float MaxHealth => maxHealth;
        public float CurrentHealth { get; private set; }
        public bool IsDead { get; private set; }

        public event Action<DamageInfo> Damaged;
        public event Action<DamageInfo> Died;

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

            CurrentHealth = Mathf.Max(0f, CurrentHealth - info.amount);
            Damaged?.Invoke(info);

            if (CurrentHealth <= 0f)
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

        /// <summary>Used by the ritual altar to kill a survivor outright on sacrifice.</summary>
        public void Kill(GameObject source)
        {
            TakeDamage(new DamageInfo(CurrentHealth <= 0f ? 1f : CurrentHealth, source));
        }
    }
}
