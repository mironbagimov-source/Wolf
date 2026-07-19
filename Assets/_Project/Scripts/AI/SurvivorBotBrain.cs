using UnityEngine;

namespace Wolf.AI
{
    /// <summary>Wanders randomly and pokes at whatever's directly ahead — good enough to test the generator/altar loop.</summary>
    public class SurvivorBotBrain : BotBrainBase
    {
        [SerializeField] private float interactInterval = 1f;

        private Vector3 _wanderDir = Vector3.forward;
        private float _wanderTimer;
        private float _interactTimer;

        protected override void Tick(float deltaTime)
        {
            InteractPressed = false;

            _wanderTimer -= deltaTime;
            if (_wanderTimer <= 0f)
            {
                float angle = Random.Range(0f, 360f);
                _wanderDir = Quaternion.Euler(0f, angle, 0f) * Vector3.forward;
                _wanderTimer = Random.Range(2f, 5f);
            }

            SteerTowards(_wanderDir);

            _interactTimer -= deltaTime;
            if (_interactTimer <= 0f)
            {
                InteractPressed = true;
                _interactTimer = interactInterval;
            }
        }
    }
}
