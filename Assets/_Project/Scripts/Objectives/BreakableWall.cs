using UnityEngine;

namespace Wolf.Objectives
{
    /// <summary>
    /// A stretch of cracked brick. Roger goes through it at a run and leaves a
    /// permanent hole — a route that didn't exist when the chase started.
    ///
    /// Mark these visibly different in the level: a player has to be able to
    /// read which walls will give before committing to a charge.
    /// </summary>
    public class BreakableWall : MonoBehaviour
    {
        [SerializeField] private GameObject rubblePrefab;
        [SerializeField] private float rubbleLifetime = 0f;   // 0 = leave it lying there

        public bool IsBroken { get; private set; }

        public void Shatter(GameObject source)
        {
            if (IsBroken)
            {
                return;
            }

            IsBroken = true;

            if (rubblePrefab != null)
            {
                GameObject rubble = Instantiate(rubblePrefab, transform.position, transform.rotation);
                if (rubbleLifetime > 0f)
                {
                    Destroy(rubble, rubbleLifetime);
                }
            }

            // The hole is the point, so the wall stops existing for physics and
            // for the eye — but the GameObject stays, because the level (and a
            // future NavMesh rebuild) may still want to know it was here.
            foreach (Collider collider in GetComponentsInChildren<Collider>())
            {
                collider.enabled = false;
            }
            foreach (Renderer renderer in GetComponentsInChildren<Renderer>())
            {
                renderer.enabled = false;
            }
        }
    }
}
