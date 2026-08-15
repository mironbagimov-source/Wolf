using UnityEngine;

namespace Wolf.Core
{
    /// <summary>
    /// Balance knobs, tunable in the Editor without touching code.
    /// Create one via Assets → Create → Wolf → Match Settings and assign it
    /// on the GameManager.
    /// </summary>
    [CreateAssetMenu(fileName = "MatchSettings", menuName = "Wolf/Match Settings")]
    public class MatchSettings : ScriptableObject
    {
        [Header("Roster")]
        [Tooltip("Killers are always exactly this many by design (see GDD).")]
        public int killerCount = 3;
        public int minSurvivors = 1;
        public int maxSurvivors = 6;
        public int minCannibals = 1;
        public int maxCannibals = 6;

        [Header("Victim objective")]
        [Tooltip("How many nodes must be hacked before the exit from the block opens.")]
        public int generatorsRequired = 3;
        [Tooltip("How many victims must reach the exit for the Victims to win.")]
        public int survivorsRequiredToEscape = 1;

        [Header("Cyberpsycho harvest")]
        [Tooltip("Seconds a captured victim has on the implant table before being harvested.")]
        public float sacrificeTimer = 30f;
        [Tooltip("Seconds a downed victim can be carried before auto-escaping a grab.")]
        public float carryStruggleTime = 15f;

        [Header("Mercenary hunt")]
        [Tooltip("Alpha (cult leader) max health — mercenaries must burn this down to zero.")]
        public float cultLeaderHealth = 300f;
    }
}
