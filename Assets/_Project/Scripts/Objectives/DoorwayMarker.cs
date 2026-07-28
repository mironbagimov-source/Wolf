using UnityEngine;

namespace Wolf.Objectives
{
    /// <summary>
    /// A gap the Witch can seal. Placed by the level in every doorway wide
    /// enough to run through and narrow enough to close — the breach itself
    /// deliberately has none, or she could lock the match.
    /// </summary>
    public class DoorwayMarker : MonoBehaviour
    {
        [Tooltip("Width of the gap, used to size the thicket that grows here.")]
        public float width = 2.7f;

        public bool IsBlocked { get; private set; }

        public void SetBlocked(bool blocked) => IsBlocked = blocked;

        private void OnDrawGizmos()
        {
            Gizmos.color = IsBlocked ? new Color(0.2f, 0.7f, 0.3f) : new Color(0.8f, 0.7f, 0.3f);
            Gizmos.matrix = transform.localToWorldMatrix;
            Gizmos.DrawWireCube(Vector3.up * 1.3f, new Vector3(width, 2.6f, 0.4f));
        }
    }
}
