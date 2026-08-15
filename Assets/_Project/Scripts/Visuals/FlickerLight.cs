using UnityEngine;
#if WOLF_HDRP
using UnityEngine.Rendering.HighDefinition;
#endif

namespace Wolf.Visuals
{
    /// <summary>
    /// Perlin-noise light flicker for barrel fires and dying neon. Works on the
    /// built-in pipeline via Light.intensity and on HDRP via
    /// HDAdditionalLightData (HDRP ignores the legacy intensity field).
    /// </summary>
    [RequireComponent(typeof(Light))]
    public class FlickerLight : MonoBehaviour
    {
        [Range(0f, 1f)]
        [SerializeField] private float flickerAmount = 0.35f;
        [SerializeField] private float speed = 9f;

        private Light _light;
        private float _baseIntensity;
        private float _seed;
#if WOLF_HDRP
        private HDAdditionalLightData _hd;
#endif

        private void Awake()
        {
            _light = GetComponent<Light>();
            _seed = (GetInstanceID() & 0xffff) * 0.013f;
#if WOLF_HDRP
            _hd = GetComponent<HDAdditionalLightData>();
            _baseIntensity = _hd != null ? _hd.intensity : _light.intensity;
#else
            _baseIntensity = _light.intensity;
#endif
        }

        private void Update()
        {
            float f = 1f + (Mathf.PerlinNoise(Time.time * speed, _seed) - 0.5f) * 2f * flickerAmount;
#if WOLF_HDRP
            if (_hd != null) { _hd.intensity = _baseIntensity * f; return; }
#endif
            _light.intensity = _baseIntensity * f;
        }
    }
}
