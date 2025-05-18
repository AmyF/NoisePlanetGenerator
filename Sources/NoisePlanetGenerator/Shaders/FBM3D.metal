#include <metal_stdlib>
#include "FBM3D.metalh"
#include "PerlinNoise3D.metalh"   // For PerlinNoise3D::perlin_noise_3d
#include "SimplexNoise3D.metalh"  // For SimplexNoise3D::simplex_noise_3d
#include "ValueNoise3D.metalh"    // For ValueNoise3D::value_noise_3d
// PermutationTable.metalh is included by the individual noise files if they need it directly.
// BaseNoiseSettings and FBMNoiseSettings are from NoisePlanetTypes.h (included via FBM3D.metalh)

using namespace metal;

namespace FBM3D {

    // Generic FBM implementation template (conceptual, actual calls are specific)
    // Not directly callable, but shows the logic.
    /*
    template<typename NoiseFunc>
    float fbm_generic_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,
        constant FBMNoiseSettings &fbmSettings,
        thread const int perm_table[512],
        NoiseFunc noise_function // This is pseudo-code for passing the noise func
    ) {
        float total_value = 0.0f;
        float current_amplitude = baseSettings.amplitude;
        float current_frequency = baseSettings.frequency;
        float3 p = position; // Original position is not modified by baseSettings.offset here
                             // as offset is part of BaseNoiseSettings applied by noise_function

        for (int i = 0; i < fbmSettings.octaves; ++i) {
            // Create temporary BaseNoiseSettings for this octave
            BaseNoiseSettings octave_base_settings;
            octave_base_settings.frequency = current_frequency;
            octave_base_settings.amplitude = current_amplitude; // Noise functions usually apply this
            octave_base_settings.offset = baseSettings.offset;  // Pass original offset

            // Call the specific noise function (pseudo-code part)
            // float noise_val = noise_function(p, octave_base_settings, perm_table);
            // The noise_function itself will handle its own amplitude, so we sum normalized noise
            // and apply overall amplitude at the end, or ensure noise_function returns value scaled by its octave_amplitude.
            // Let's assume noise_function returns [-amp, amp] or [0, amp]
            // The common way: sum noise * current_amplitude
            
            // Standard FBM:
            // Noise functions (Perlin/Simplex) typically return roughly [-1,1] before amplitude.
            // Value noise typically [0,1] before amplitude.
            // We'll pass current_amplitude to the noise func's settings.
            
            // Re-thinking: baseSettings.amplitude is the amplitude of the *first octave*.
            // The per-octave amplitude is current_amplitude.
            // The per-octave frequency is current_frequency.
            // The noise functions themselves take a BaseNoiseSettings which has an amplitude.
            // We will scale their *output* by current_amplitude and sum it.
            // Or, more simply, the baseSettings struct passed to the noise function should have its amplitude set to current_amplitude.

            BaseNoiseSettings octave_settings = baseSettings; // copy general offset etc.
            octave_settings.frequency = current_frequency;
            // The individual noise functions will apply their own amplitude.
            // For FBM, the amplitude of the *base noise call* for the first octave is 1.0 (or baseSettings.amplitude),
            // and then subsequent octaves have their *contribution* scaled by persistence.
            // So the amplitude passed to the noise function should be 1.0, and we scale its output.
            // Or, the amplitude passed is baseSettings.amplitude, and then we scale by persistence.
            
            // Let's make the noise functions return a value in their "natural" range (e.g. Perlin ~[-1,1])
            // and apply the octave's amplitude here.
            
            // Example using Perlin for the generic template:
            // float raw_noise = PerlinNoise3D::perlin_noise_3d(p * current_frequency, baseSettings_with_offset_only, perm_table);
            // total_value += raw_noise * current_amplitude;
            
            // p gets scaled by frequency *inside* the noise function.
            // So we just update current_frequency and current_amplitude for the next loop.
            // The 'position' argument to noise should be the *original* position.
            // The noise function takes 'baseSettings' which contains frequency and offset.

            // Let's use a simpler structure where each noise function is called with modified settings.
            BaseNoiseSettings current_octave_settings = baseSettings; // inherits offset
            current_octave_settings.frequency = current_frequency;
            current_octave_settings.amplitude = current_amplitude; // This amplitude is for this octave's contribution

            // How noise_function is chosen is the key.
            // This generic template cannot be directly translated to MSL due to lack of function pointers/templates for this.
            // So we create specific versions.
        }
        return total_value; // This might need normalization depending on amplitude sum
    }
    */

    // FBM for Perlin base noise
    float fbm_perlin_3d(
        float3 position,
        constant BaseNoiseSettings &initialBaseSettings, // Overall settings (offset, initial amp/freq)
        constant FBMNoiseSettings &fbmSettings,
        thread const int perm_table[512]
    ) {
        float total_value = 0.0f;
        float current_amplitude = initialBaseSettings.amplitude; // Amplitude of the first octave
        float current_frequency = initialBaseSettings.frequency; // Frequency of the first octave

        for (int i = 0; i < fbmSettings.octaves; ++i) {
            if (current_amplitude == 0.0f) break; // Optimization

            BaseNoiseSettings octave_settings;
            octave_settings.frequency = current_frequency;
            octave_settings.amplitude = 1.0f; // Perlin noise returns roughly [-1,1], we scale by current_amplitude
            octave_settings.offset    = initialBaseSettings.offset; // Use the global offset

            float noise_val = PerlinNoise3D::perlin_noise_3d(position, octave_settings, perm_table);
            total_value += noise_val * current_amplitude;

            current_frequency *= fbmSettings.lacunarity;
            current_amplitude *= fbmSettings.persistence;
        }
        return total_value; // Output range depends on sum of amplitudes.
                            // If initial amplitude = 1, persistence = 0.5, octaves=many, sum is approx 2.
                            // So this returns roughly [-2*A, 2*A] if Perlin is [-A,A]
                            // Given Perlin is ~[-1,1] * octave_settings.amplitude (which is 1),
                            // result is sum of ([-1,1] * current_amplitude_for_octave).
    }

    // FBM for Simplex base noise
    float fbm_simplex_3d(
        float3 position,
        constant BaseNoiseSettings &initialBaseSettings,
        constant FBMNoiseSettings &fbmSettings,
        thread const int perm_table[512]
    ) {
        float total_value = 0.0f;
        float current_amplitude = initialBaseSettings.amplitude;
        float current_frequency = initialBaseSettings.frequency;

        for (int i = 0; i < fbmSettings.octaves; ++i) {
            if (current_amplitude == 0.0f) break;

            BaseNoiseSettings octave_settings;
            octave_settings.frequency = current_frequency;
            octave_settings.amplitude = 1.0f; // Simplex noise returns roughly [-1,1]
            octave_settings.offset    = initialBaseSettings.offset;

            float noise_val = SimplexNoise3D::simplex_noise_3d(position, octave_settings, perm_table);
            total_value += noise_val * current_amplitude;

            current_frequency *= fbmSettings.lacunarity;
            current_amplitude *= fbmSettings.persistence;
        }
        return total_value;
    }

    // FBM for Value base noise
    float fbm_value_3d(
        float3 position,
        constant BaseNoiseSettings &initialBaseSettings,
        constant FBMNoiseSettings &fbmSettings,
        thread const int perm_table[512]
    ) {
        float total_value = 0.0f;
        float current_amplitude = initialBaseSettings.amplitude;
        float current_frequency = initialBaseSettings.frequency;

        for (int i = 0; i < fbmSettings.octaves; ++i) {
            if (current_amplitude == 0.0f) break;

            BaseNoiseSettings octave_settings;
            octave_settings.frequency = current_frequency;
            octave_settings.amplitude = 1.0f; // Value noise returns [0,1]
            octave_settings.offset    = initialBaseSettings.offset;

            float noise_val = ValueNoise3D::value_noise_3d(position, octave_settings, perm_table);
            // Value noise is [0,1], if we want FBM to oscillate around 0, subtract 0.5
            // Or, accept that Value FBM is mostly positive. User can remap later.
            // For now, standard sum:
            total_value += noise_val * current_amplitude;

            current_frequency *= fbmSettings.lacunarity;
            current_amplitude *= fbmSettings.persistence;
        }
        // If Value noise is [0,1]*amp, then sum is [0, sum_amps].
        // Example: initial_amp=1, persist=0.5. Sum_amps approx 2. Range [0, 2].
        return total_value;
    }

} // namespace FBM3D