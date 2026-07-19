using Wolf.Player;

namespace Wolf.Utils
{
    /// <summary>Anything a player can interact with via the interact raycast: generators, gates, altars, doors.</summary>
    public interface IInteractable
    {
        /// <summary>Short label shown by the HUD prompt, e.g. "Repair generator".</summary>
        string InteractionPrompt { get; }

        /// <summary>Whether interaction is currently possible (e.g. generator not already complete).</summary>
        bool CanInteract(PlayerControllerBase interactor);

        /// <summary>Called once per interact press. Long actions (repairing) should track their own progress via Update/Hold.</summary>
        void Interact(PlayerControllerBase interactor);
    }
}
