namespace Wolf.Core
{
    /// <summary>The two sides of a match. See docs/GDD.md for win conditions.</summary>
    public enum FactionType
    {
        Guest,
        Killer,
    }

    /// <summary>
    /// Which of the three hunters is in this match. One per match — they are
    /// not a team, they are three different games for the guests to lose.
    /// </summary>
    public enum KillerArchetype
    {
        Trickster,
        Witch,
        JollyRoger,
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
        GuestsWin,   // at least one guest made it out through the breach
        KillerWins,  // and then there were none
    }
}
