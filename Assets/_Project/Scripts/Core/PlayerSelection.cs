namespace Wolf.Core
{
    /// <summary>
    /// Carries the player's lobby picks across the scene load from Lobby into
    /// the gameplay scene. Plain static class — simpler than DontDestroyOnLoad
    /// for three enum values.
    /// </summary>
    public static class PlayerSelection
    {
        public static FactionType ChosenFaction = FactionType.Guest;

        /// <summary>Which hunter, when the player picked the killer side.</summary>
        public static KillerArchetype ChosenKiller = KillerArchetype.Trickster;

        public static GameModeType ChosenMode = GameModeType.BotMatch;
    }
}
