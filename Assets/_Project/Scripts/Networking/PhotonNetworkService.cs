using System;
using UnityEngine;
using Wolf.Core;

#if PHOTON_UNITY_NETWORKING
using Photon.Pun;
using Photon.Realtime;
#endif

namespace Wolf.Networking
{
#if PHOTON_UNITY_NETWORKING
    /// <summary>
    /// Multiplayer implementation over Photon PUN2. Requires player prefabs to
    /// live under a Resources folder (Photon instantiates them by name).
    /// This is a first-pass scaffold — not yet exercised against a live Photon
    /// app, expect to iterate once Photon is actually installed in the project.
    /// </summary>
    public class PhotonNetworkService : INetworkService, IConnectionCallbacks, IMatchmakingCallbacks
    {
        public bool IsReady { get; private set; }
        public event Action Ready;

        public PhotonNetworkService()
        {
            PhotonNetwork.AddCallbackTarget(this);
        }

        public bool IsMine(GameObject playerInstance)
        {
            var view = playerInstance.GetComponent<PhotonView>();
            return view == null || view.IsMine;
        }

        public void Connect(GameModeType mode, string sessionName)
        {
            if (PhotonNetwork.IsConnected)
            {
                JoinRoom(sessionName);
                return;
            }

            PhotonNetwork.ConnectUsingSettings();
            _pendingRoomName = sessionName;
        }

        public GameObject SpawnPlayer(GameObject prefab, FactionType faction, Vector3 position, Quaternion rotation)
        {
            // Photon needs the prefab under Resources/ and instantiates it by name.
            return PhotonNetwork.Instantiate(prefab.name, position, rotation);
        }

        private string _pendingRoomName;

        public void OnConnectedToMaster()
        {
            JoinRoom(_pendingRoomName);
        }

        private void JoinRoom(string roomName)
        {
            PhotonNetwork.JoinOrCreateRoom(roomName, new RoomOptions { MaxPlayers = 10 }, TypedLobby.Default);
        }

        public void OnJoinedRoom()
        {
            IsReady = true;
            Ready?.Invoke();
        }

        public void OnConnected() { }
        public void OnDisconnected(DisconnectCause cause) => Debug.LogWarning($"[Photon] Disconnected: {cause}");
        public void OnRegionListReceived(RegionHandler regionHandler) { }
        public void OnCustomAuthenticationResponse(System.Collections.Generic.Dictionary<string, object> data) { }
        public void OnCustomAuthenticationFailed(string debugMessage) { }
        public void OnFriendListUpdate(System.Collections.Generic.List<FriendInfo> friendList) { }
        public void OnCreatedRoom() { }
        public void OnCreateRoomFailed(short returnCode, string message) => Debug.LogError($"[Photon] Create room failed: {message}");
        public void OnJoinRoomFailed(short returnCode, string message) => Debug.LogError($"[Photon] Join room failed: {message}");
        public void OnJoinRandomFailed(short returnCode, string message) { }
        public void OnLeftRoom() { }
    }
#else
    /// <summary>
    /// Stub used until the Photon PUN2 package is imported (it defines the
    /// PHOTON_UNITY_NETWORKING scripting symbol automatically on import).
    /// Selecting the Multiplayer mode before that will log an error instead
    /// of silently doing nothing.
    /// </summary>
    public class PhotonNetworkService : INetworkService
    {
        public bool IsReady => false;
        public event Action Ready { add { } remove { } }

        public bool IsMine(GameObject playerInstance) => true;

        public void Connect(GameModeType mode, string sessionName)
        {
            Debug.LogError("Photon PUN2 is not installed — see README for setup. Falling back is not possible for Multiplayer mode.");
        }

        public GameObject SpawnPlayer(GameObject prefab, FactionType faction, Vector3 position, Quaternion rotation)
        {
            throw new InvalidOperationException("Photon PUN2 is not installed — cannot spawn networked players.");
        }
    }
#endif
}
