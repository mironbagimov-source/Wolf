using UnityEngine;

namespace Wolf.Core
{
    /// <summary>Marks a transform in the scene as a valid spawn location for one faction. Placed by the level, read by MatchBootstrapper.</summary>
    public class SpawnPoint : MonoBehaviour
    {
        public FactionType faction;

        private void OnDrawGizmos()
        {
            Gizmos.color = faction switch
            {
                FactionType.Survivor => Color.green,
                FactionType.Cannibal => Color.red,
                FactionType.Killer => Color.cyan,
                _ => Color.white,
            };
            Gizmos.DrawWireSphere(transform.position, 0.5f);
        }
    }
}
