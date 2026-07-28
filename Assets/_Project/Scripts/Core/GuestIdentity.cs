using UnityEngine;

namespace Wolf.Core
{
    /// <summary>
    /// Who this guest is and what they did. The match needs it for two things:
    /// the HUD (a name on the prompt when you lift someone off a hook) and the
    /// counting rhyme (each guest owns one figurine and one line).
    /// </summary>
    public class GuestIdentity : MonoBehaviour
    {
        public string guestName = "Гость";

        [Tooltip("The reason someone came for them. Shown on the end screen.")]
        [TextArea]
        public string sin = "";

        [Tooltip("Which figurine on the plinth — and which rhyme line — belongs to this guest.")]
        public int figurineIndex;
    }
}
