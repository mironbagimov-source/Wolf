using UnityEngine;

namespace Wolf.Utils
{
    /// <summary>
    /// Reads the legacy Input Manager (Unity's default unless the Input
    /// System package was picked at project creation). Used for every
    /// human-controlled player — local or networked.
    ///
    /// F is bound twice on purpose: it's the flashlight for a guest and the
    /// doubles for the Trickster. Only one of them is ever asking.
    /// </summary>
    public class HardwareInputProvider : IInputProvider
    {
        public Vector2 Move => new(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
        public Vector2 Look => new(Input.GetAxis("Mouse X"), Input.GetAxis("Mouse Y"));
        public bool Sprint => Input.GetKey(KeyCode.LeftShift);
        public bool Crouch => Input.GetKey(KeyCode.LeftControl);

        public bool InteractPressed => Input.GetKeyDown(KeyCode.E);
        public bool InteractHeld => Input.GetKey(KeyCode.E);

        public bool PrimaryPressed => Input.GetButtonDown("Fire1");
        public bool SecondaryPressed => Input.GetButtonDown("Fire2");
        public bool Power1Pressed => Input.GetKeyDown(KeyCode.Q);
        public bool Power2Pressed => Input.GetKeyDown(KeyCode.F);

        public bool DropPressed => Input.GetKeyDown(KeyCode.G);
        public bool StrugglePressed => Input.GetKeyDown(KeyCode.Space);
        public bool FlashlightPressed => Input.GetKeyDown(KeyCode.F);
    }
}
