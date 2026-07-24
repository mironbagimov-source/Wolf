namespace Wolf.Core
{
    /// <summary>
    /// Carries the player's lobby picks (faction + mode) across the scene
    /// load from Lobby into the gameplay scene. Plain static class — simpler
    /// than DontDestroyOnLoad for two enum values.
    /// </summary>
    public static class PlayerSelection
    {
        public static FactionType ChosenFaction = FactionType.Survivor;
        public static GameModeType ChosenMode = GameModeType.BotMatch;

        /// <summary>Index into CharacterRoster.For(ChosenFaction). Wrapped on read,
        /// so the lobby can just increment it to cycle characters.</summary>
        public static int ChosenCharacterIndex = 0;
    }
}
