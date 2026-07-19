using UnityEngine;

namespace Wolf.Core
{
    /// <summary>
    /// Add to exactly one Cannibal instance per match — usually the AI-run
    /// boss, but nothing stops a human player from taking the role. Its death
    /// is what the Killers are hunting for (see GameManager.OnPlayerDied).
    /// </summary>
    public class CultLeaderMarker : MonoBehaviour
    {
    }
}
