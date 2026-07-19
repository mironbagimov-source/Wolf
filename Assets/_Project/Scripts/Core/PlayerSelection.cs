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
    }
}
