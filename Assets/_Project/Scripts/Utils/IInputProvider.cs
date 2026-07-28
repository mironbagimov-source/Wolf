using UnityEngine;

namespace Wolf.Utils
{
    /// <summary>
    /// Everything a PlayerControllerBase needs this frame, regardless of
    /// whether it comes from hardware (human) or an AI brain (bot). This is
    /// what lets BotMatch reuse the exact same movement/attack/interact code
    /// as a human-controlled player.
    ///
    /// The verbs are deliberately generic — Primary/Secondary/Power1/Power2 —
    /// because what they mean is the difference between the three killers, and
    /// that belongs in their controllers, not in the input layer.
    /// </summary>
    public interface IInputProvider
    {
        Vector2 Move { get; }      // x = strafe, y = forward, both in [-1, 1]
        Vector2 Look { get; }      // x = yaw delta, y = pitch delta, frame-rate independent
        bool Sprint { get; }
        bool Crouch { get; }

        bool InteractPressed { get; }   // E, tapped
        bool InteractHeld { get; }      // E, held — repairing, lifting, growing

        bool PrimaryPressed { get; }    // LMB: knife / lash / maul
        bool SecondaryPressed { get; }  // RMB: scythe / ivy / snatch
        bool Power1Pressed { get; }     // Q: hook shot / thicket / charge
        bool Power2Pressed { get; }     // F: doubles (Trickster only)

        bool DropPressed { get; }       // G: put the carried guest down
        bool StrugglePressed { get; }   // Space: wriggle out of a grip
        bool FlashlightPressed { get; } // F, guest side
    }
}
