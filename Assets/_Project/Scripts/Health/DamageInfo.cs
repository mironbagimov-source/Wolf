using UnityEngine;

namespace Wolf.Health
{
    /// <summary>Immutable description of a single hit, passed into HealthComponent.TakeDamage.</summary>
    public readonly struct DamageInfo
    {
        public readonly float amount;
        public readonly GameObject source;
        public readonly Vector3 hitPoint;

        public DamageInfo(float amount, GameObject source, Vector3 hitPoint = default)
        {
            this.amount = amount;
            this.source = source;
            this.hitPoint = hitPoint;
        }
    }
}
