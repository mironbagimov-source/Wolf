namespace Wolf.Core
{
    /// <summary>
    /// One selectable character within a faction — a light stat variant applied
    /// to the local human at spawn. Mirrors the browser prototype's roster; kept
    /// as plain code (not Editor assets) so the picks work with no scene setup.
    /// blockDamageMul below is negative when the archetype leaves the prefab's
    /// own block value alone.
    /// </summary>
    public readonly struct CharacterArchetype
    {
        public readonly string name;
        public readonly string tag;
        public readonly string description;
        public readonly float speedMul;
        public readonly float hpMul;
        public readonly float damageMul;
        public readonly int extraKnives;
        public readonly float blockDamageMul;

        public CharacterArchetype(string name, string tag, string description,
            float speedMul = 1f, float hpMul = 1f, float damageMul = 1f,
            int extraKnives = 0, float blockDamageMul = -1f)
        {
            this.name = name;
            this.tag = tag;
            this.description = description;
            this.speedMul = speedMul;
            this.hpMul = hpMul;
            this.damageMul = damageMul;
            this.extraKnives = extraKnives;
            this.blockDamageMul = blockDamageMul;
        }
    }

    /// <summary>The playable characters per side. Index into these via
    /// PlayerSelection.ChosenCharacterIndex.</summary>
    public static class CharacterRoster
    {
        private static readonly CharacterArchetype[] Survivors =
        {
            new CharacterArchetype("Курьер", "скорость", "Быстрый и хрупкий. Живёт только за счёт ног.", speedMul: 1.12f, hpMul: 0.85f),
            new CharacterArchetype("Медтех", "живучесть", "Медленнее, зато держится под погоней дольше.", speedMul: 0.95f, hpMul: 1.25f),
        };

        private static readonly CharacterArchetype[] Cannibals =
        {
            new CharacterArchetype("Мясник", "танк", "Ломится напролом, бьёт тяжело, но медленный.", speedMul: 0.92f, hpMul: 1.15f, damageMul: 1.15f),
            new CharacterArchetype("Богомол", "скорость", "Быстрый и хлёсткий, но хрупкий как стекло.", speedMul: 1.12f, hpMul: 0.85f),
        };

        private static readonly CharacterArchetype[] Killers =
        {
            new CharacterArchetype("Клинок", "стелс · ножи", "Скорость и лишние ножи. Ставка на добивания.", speedMul: 1.1f, hpMul: 0.85f, extraKnives: 2),
            new CharacterArchetype("Броня", "танк", "Медленный таран, держит удар и держит блок.", speedMul: 0.9f, hpMul: 1.25f, blockDamageMul: 0.15f),
        };

        public static CharacterArchetype[] For(FactionType faction) => faction switch
        {
            FactionType.Survivor => Survivors,
            FactionType.Cannibal => Cannibals,
            FactionType.Killer => Killers,
            _ => Survivors,
        };

        /// <summary>Wraps the index, so a lobby "cycle character" button can just increment forever.</summary>
        public static CharacterArchetype Get(FactionType faction, int index)
        {
            CharacterArchetype[] list = For(faction);
            if (list.Length == 0)
            {
                return new CharacterArchetype("—", string.Empty, string.Empty);
            }

            int wrapped = ((index % list.Length) + list.Length) % list.Length;
            return list[wrapped];
        }
    }
}
