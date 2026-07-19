using UnityEngine;

namespace Wolf.Utils
{
    /// <summary>
    /// Everything a PlayerControllerBase needs this frame, regardless of
    /// whether it comes from hardware (human) or an AI brain (bot). This is
    /// what lets BotMatch reuse the exact same movement/attack/interact code
    /// as a human-controlled player.
    /// </summary>
    public interface IInputProvider
    {
        Vector2 Move { get; }      // x = strafe, y = forward, both in [-1, 1]
        Vector2 Look { get; }      // x = yaw delta, y = pitch delta, frame-rate independent
        bool Sprint { get; }
        bool Crouch { get; }
        bool InteractPressed { get; }
        bool PrimaryPressed { get; }   // attack
        bool SecondaryHeld { get; }    // block
        bool AbilityPressed { get; }   // faction special: Cannibal grab, etc.
        bool FlashlightPressed { get; }
    }
}
