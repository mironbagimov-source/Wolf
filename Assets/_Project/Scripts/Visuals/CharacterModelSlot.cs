using UnityEngine;
using Wolf.Core;
using Wolf.Player;

namespace Wolf.Visuals
{
    /// <summary>
    /// Swaps the built-in mannequin visual for a real character model when one
    /// exists under a Resources path — drop any rigged/static model prefab into
    /// Assets/_Project/Resources/CharacterModels/ named after the faction
    /// (Survivor.prefab, Cannibal.prefab, Killer.prefab, CannibalLeader.prefab)
    /// and every spawn picks it up automatically, no scene wiring.
    /// With no model present the mannequin stays, and either way each instance
    /// gets a deterministic size jitter so a crowd of bots doesn't read as clones.
    /// </summary>
    public class CharacterModelSlot : MonoBehaviour
    {
        [Tooltip("Optional explicit Resources path; overrides the faction-based lookup.")]
        [SerializeField] private string overrideResourcePath = "";

        [Tooltip("Root of the built-in mannequin visual, hidden when a real model loads.")]
        [SerializeField] private GameObject mannequinRoot;

        private void Start()
        {
            PlayerControllerBase controller = GetComponent<PlayerControllerBase>();
            bool isLeader = GetComponent<CultLeaderMarker>() != null;

            string path = !string.IsNullOrEmpty(overrideResourcePath)
                ? overrideResourcePath
                : "CharacterModels/" + (isLeader ? "CannibalLeader"
                    : controller != null ? controller.Faction.ToString() : name);

            GameObject prefab = Resources.Load<GameObject>(path);
            if (prefab == null && isLeader)
            {
                prefab = Resources.Load<GameObject>("CharacterModels/Cannibal");
            }

            if (prefab != null)
            {
                if (mannequinRoot != null)
                {
                    mannequinRoot.SetActive(false);
                }
                MeshRenderer capsule = GetComponent<MeshRenderer>();
                if (capsule != null)
                {
                    capsule.enabled = false;
                }

                GameObject visual = Instantiate(prefab, transform);
                // The capsule's pivot sits at its centre; imported characters
                // stand on their feet, so drop the visual to ground level.
                visual.transform.localPosition = new Vector3(0f, -1f, 0f);
                visual.transform.localRotation = Quaternion.identity;
                Stylize(visual.transform, isLeader);
                return;
            }

            if (mannequinRoot != null)
            {
                Stylize(mannequinRoot.transform, isLeader);
            }
        }

        private void Stylize(Transform visual, bool isLeader)
        {
            // Deterministic per-instance jitter (seeded by instance id) + the
            // leader reads physically bigger than the pack.
            float jitter = 0.96f + (GetInstanceID() & 0xff) / 255f * 0.09f;
            visual.localScale *= jitter * (isLeader ? 1.14f : 1f);
        }
    }
}
