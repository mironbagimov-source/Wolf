using UnityEngine;
using Wolf.Core;
using Wolf.Player.Survivor;

namespace Wolf.Objectives
{
    /// <summary>Trigger volume at the exit — a living Survivor walking in while the gate is open escapes.</summary>
    [RequireComponent(typeof(Collider))]
    public class ExitGateTrigger : MonoBehaviour
    {
        private void OnTriggerEnter(Collider other)
        {
            if (GameManager.Instance == null || !GameManager.Instance.ExitGateOpen)
            {
                return;
            }

            if (other.TryGetComponent(out SurvivorController survivor) && !survivor.Health.IsDead && !survivor.IsGrabbed)
            {
                GameManager.Instance.ReportSurvivorEscaped(survivor.Health);
                survivor.gameObject.SetActive(false);
            }
        }
    }
}
