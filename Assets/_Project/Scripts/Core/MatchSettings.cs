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

        [Header("Survivor objective")]
        [Tooltip("How many generators must be completed before the exit gate opens.")]
        public int generatorsRequired = 3;
        [Tooltip("How many survivors must reach the exit for Survivors to win.")]
        public int survivorsRequiredToEscape = 1;

        [Header("Cannibal ritual")]
        [Tooltip("Seconds a captured survivor has on the altar before being sacrificed.")]
        public float sacrificeTimer = 30f;
        [Tooltip("Seconds a downed survivor can be carried before auto-escaping a grab.")]
        public float carryStruggleTime = 15f;

        [Header("Killer hunt")]
        [Tooltip("Cult Leader max health — killers must burn this down to zero.")]
        public float cultLeaderHealth = 300f;
    }
}
