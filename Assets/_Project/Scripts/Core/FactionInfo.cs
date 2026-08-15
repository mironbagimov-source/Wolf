namespace Wolf.Core
{
    /// <summary>
    /// User-facing labels for the cyberpunk re-theme. The engine keeps the
    /// internal faction keys (Survivor/Cannibal/Killer) so spawns, AI, networking
    /// and win checks are untouched; only what the player reads changes here.
    /// </summary>
    public static class FactionInfo
    {
        public static string DisplayName(FactionType faction) => faction switch
        {
            FactionType.Survivor => "Жертва",
            FactionType.Cannibal => "Кибер-псих",
            FactionType.Killer => "Наёмник",
            _ => faction.ToString(),
        };

        /// <summary>Banner text for a resolved match (see docs/GDD.md win table).</summary>
        public static string ResultText(MatchState state) => state switch
        {
            MatchState.SurvivorsWin => "Жертвы ушли из квартала.",
            MatchState.CannibalsWin => "Из квартала не ушёл никто.",
            MatchState.KillersWin => "Альфа мёртв. Стая обезглавлена.",
            _ => string.Empty,
        };
    }
}
