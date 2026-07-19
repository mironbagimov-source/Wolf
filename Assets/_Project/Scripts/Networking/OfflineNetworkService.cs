using System;
using UnityEngine;
using Wolf.Core;

namespace Wolf.Networking
{
    /// <summary>
    /// Used for BotMatch and LocalSplitscreen: no real transport, everything
    /// happens on the local machine and is instantiated immediately.
    /// </summary>
    public class OfflineNetworkService : INetworkService
    {
        public bool IsReady { get; private set; }
        public event Action Ready;

        public bool IsMine(GameObject playerInstance) => true;

        public void Connect(GameModeType mode, string sessionName)
        {
            // Nothing to connect to — ready on the same frame.
            IsReady = true;
            Ready?.Invoke();
        }

        public GameObject SpawnPlayer(GameObject prefab, FactionType faction, Vector3 position, Quaternion rotation)
        {
            return UnityEngine.Object.Instantiate(prefab, position, rotation);
        }
    }
}
