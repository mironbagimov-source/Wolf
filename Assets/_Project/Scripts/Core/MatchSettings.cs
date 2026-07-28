using UnityEngine;

namespace Wolf.Core
{
    /// <summary>
    /// Match-level balance knobs, tunable in the Editor without touching code.
    /// Per-killer numbers (damage, cooldowns, power ranges) live on the killer
    /// controllers instead — those are character design, this is match design.
    /// Create one via Assets → Create → Wolf → Match Settings and assign it
    /// on the GameManager.
    /// </summary>
    [CreateAssetMenu(fileName = "MatchSettings", menuName = "Wolf/Match Settings")]
    public class MatchSettings : ScriptableObject
    {
        [Header("Roster")]
        [Tooltip("Guests per match. Four is the design — the rhyme has four lines.")]
        public int guestCount = 4;

        [Header("Objective")]
        [Tooltip("Breakers that must be repaired before the breach opens.")]
        public int breakersRequired = 4;
        [Tooltip("Seconds of solo work to bring one breaker back online.")]
        public float breakerRepairSeconds = 14f;

        [Header("Guest states")]
        [Tooltip("Seconds a downed guest has on the ground before they bleed out.")]
        public float bleedoutSeconds = 48f;
        [Tooltip("Seconds another guest needs to lift a downed one back up.")]
        public float reviveSeconds = 6f;
        [Tooltip("Health a revived guest gets back — enough to run, not enough to be safe.")]
        public float reviveHealth = 45f;
        [Tooltip("Health a guest gets when taken off a hook.")]
        public float unhookHealth = 40f;

        [Header("Hooks")]
        [Tooltip("Seconds on a hook before that guest is gone for good.")]
        public float hookSeconds = 26f;
        [Tooltip("Seconds of wiggling to break out of a killer's grip while carried.")]
        public float carryStruggleSeconds = 14f;

        [Header("The rhyme")]
        [Tooltip("One line lands each time a guest leaves the board, in order.")]
        [TextArea]
        public string[] rhymeLines =
        {
            "Четверо гостей вошли в пустой квартал. Один остался в подворотне — и стало трое.",
            "Трое гостей искали свет в окне. Один нашёл его слишком близко — и стало двое.",
            "Двое гостей бежали на пролом. Один не добежал — и остался один.",
            "Один гость стоял в тишине совсем один. И не осталось никого.",
        };
    }
}
