using System;
using UnityEngine;
using Wolf.Core;

namespace Wolf.Networking
{
    /// <summary>
    /// Everything gameplay code needs from "the network", regardless of whether
    /// that's Photon, a local bot match, or splitscreen. Gameplay scripts must
    /// never reference Photon (or any transport) directly — only this.
    /// </summary>
    public interface INetworkService
    {
        /// <summary>True once the service is ready to spawn players (connected to room, or immediately for offline).</summary>
        bool IsReady { get; }

        /// <summary>True if the local machine is authoritative for the given player instance (always true offline).</summary>
        bool IsMine(GameObject playerInstance);

        event Action Ready;

        void Connect(GameModeType mode, string sessionName);

        /// <summary>
        /// Spawns a player-controlled instance of the given prefab for the given faction.
        /// Offline: instantiates locally. Multiplayer: goes through Photon instantiate so
        /// every client sees it.
        /// </summary>
        GameObject SpawnPlayer(GameObject prefab, FactionType faction, Vector3 position, Quaternion rotation);
    }
}
