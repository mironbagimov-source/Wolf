using UnityEngine;

namespace Wolf.Player.Killer
{
    /// <summary>
    /// A copy of the Trickster that walks off in its own direction and dies
    /// quietly. It deals no damage and never catches anyone — its whole job is
    /// that a guest cannot tell which one is real until it's too late.
    /// </summary>
    public class TricksterDouble : MonoBehaviour
    {
        [SerializeField] private float walkSpeed = 3.2f;
        [SerializeField] private float turnOnBlockDegrees = 110f;
        [SerializeField] private float probeDistance = 0.8f;

        private float _remaining = 11f;

        public void Live(float seconds)
        {
            _remaining = seconds;
        }

        private void Update()
        {
            _remaining -= Time.deltaTime;
            if (_remaining <= 0f)
            {
                Destroy(gameObject);
                return;
            }

            Vector3 origin = transform.position + Vector3.up;
            if (Physics.Raycast(origin, transform.forward, probeDistance))
            {
                transform.Rotate(Vector3.up, turnOnBlockDegrees + Random.Range(-25f, 25f));
                return;
            }

            transform.position += transform.forward * walkSpeed * Time.deltaTime;
        }
    }
}
