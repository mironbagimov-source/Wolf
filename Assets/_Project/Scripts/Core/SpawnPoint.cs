using UnityEngine;

namespace Wolf.Core
{
    /// <summary>
    /// Marks a transform in the scene as a valid spawn location for one side.
    /// Placed by the level, read by MatchBootstrapper. Guests start together at
    /// the south end; the killer starts on the far side of the quarter, which
    /// is the only head start the guests get.
    /// </summary>
    public class SpawnPoint : MonoBehaviour
    {
        public FactionType faction;

        private void OnDrawGizmos()
        {
            Gizmos.color = faction == FactionType.Guest ? new Color(0.85f, 0.75f, 0.54f) : new Color(0.82f, 0.25f, 0.35f);
            Gizmos.DrawWireSphere(transform.position, 0.5f);
            Gizmos.DrawRay(transform.position, transform.forward);
        }
    }
}
