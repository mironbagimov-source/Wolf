using UnityEngine;

namespace Wolf.Utils
{
    /// <summary>
    /// Reads the legacy Input Manager (Unity's default unless the Input
    /// System package was picked at project creation). Used for every
    /// human-controlled player — local or networked.
    /// </summary>
    public class HardwareInputProvider : IInputProvider
    {
        public Vector2 Move => new(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
        public Vector2 Look => new(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y"));
        public bool Sprint => Input.GetKey(KeyCode.LeftShift);
        public bool Crouch => Input.GetKey(KeyCode.LeftControl);
        public bool InteractPressed => Input.GetKeyDown(KeyCode.E);
        public bool PrimaryPressed => Input.GetButtonDown("Fire1");
        public bool SecondaryHeld => Input.GetButton("Fire2");
        public bool AbilityPressed => Input.GetKeyDown(KeyCode.G);
        public bool ThrowPressed => Input.GetKeyDown(KeyCode.Q);
        public bool FlashlightPressed => Input.GetKeyDown(KeyCode.F);
    }
}
