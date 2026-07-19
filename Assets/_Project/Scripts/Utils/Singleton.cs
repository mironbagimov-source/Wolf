using UnityEngine;

namespace Wolf.Utils
{
    /// <summary>
    /// Plain scene singleton (not DontDestroyOnLoad) — one instance is expected
    /// to be present per gameplay scene, wired via the bootstrap scene.
    /// </summary>
    public abstract class Singleton<T> : MonoBehaviour where T : Singleton<T>
    {
        public static T Instance { get; private set; }

        protected virtual void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Debug.LogWarning($"[{typeof(T).Name}] Duplicate instance on '{gameObject.name}', destroying it.");
                Destroy(gameObject);
                return;
            }

            Instance = (T)this;
        }

        protected virtual void OnDestroy()
        {
            if (Instance == this)
            {
                Instance = null;
            }
        }
    }
}
