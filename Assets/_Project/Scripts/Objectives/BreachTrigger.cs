using UnityEngine;
using Wolf.Core;
using Wolf.Player.Guest;

namespace Wolf.Objectives
{
    /// <summary>
    /// The hole in the north wall. A guest still on their feet who walks
    /// through it while the power is back on is out of the quarter for good.
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class BreachTrigger : MonoBehaviour
    {
        private void OnTriggerEnter(Collider other)
        {
            if (GameManager.Instance == null || !GameManager.Instance.BreachOpen)
            {
                return;
            }

            if (!other.TryGetComponent(out GuestController guest))
            {
                return;
            }

            if (guest.State != GuestController.GuestState.Standing)
            {
                return;   // nobody crawls out, and nobody leaves on a killer's shoulder
            }

            guest.OnEscaped();
        }
    }
}
