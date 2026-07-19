namespace Wolf.Core
{
    /// <summary>The three playable sides. See docs/GDD.md for win conditions.</summary>
    public enum FactionType
    {
        Survivor,
        Cannibal,
        Killer,
    }

    /// <summary>How the match is being run — same gameplay code, different network layer.</summary>
    public enum GameModeType
    {
        BotMatch,
        Multiplayer,
        LocalSplitscreen,
    }

    public enum MatchState
    {
        Lobby,
        InProgress,
        SurvivorsWin,
        CannibalsWin,
        KillersWin,
    }
}
