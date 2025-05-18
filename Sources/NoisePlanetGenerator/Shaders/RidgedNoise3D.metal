#include <metal_stdlib>
#include "RidgedNoise3D.metalh"
#include "FBM3D.metalh"           // For the FBM implementations
#include "MathUtils.metalh"       // For pow if needed for exponent

// BaseNoiseSettings, FBMNoiseSettings, RidgedNoiseSettings from NoisePlanetTypes.h

using namespace metal;

namespace RidgedNoise3D {

    // Helper function to apply the ridged transformation
    // `signal` is expected to be somewhat centered around 0 (e.g., output of Perlin/Simplex FBM)
    inline float apply_ridged_transform(float signal, float exponent, float offset, float weight) {
        signal = offset - abs(signal);   // Invert and offset; forms ridges at original 0-crossings
        signal = pow(clamp(signal, 0.0f, 1.0f), exponent); // Sharpen ridges, clamp to avoid issues with pow
                                                           // Clamping to [0,1] before pow ensures result is also [0,1]
        return signal * weight;
    }


    float ridged_fbm_perlin_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,    // Used by FBM
        constant FBMNoiseSettings &fbmSettings,      // Used by FBM
        constant RidgedNoiseSettings &ridgedSettings, // Ridged specific params
        thread const int perm_table[512]
    ) {
        // 1. Calculate FBM using Perlin
        // The amplitude in baseSettings for FBM is the initial amplitude of FBM.
        // The FBM output will be roughly in [-SumOfAmplitudes, SumOfAmplitudes]
        // For Ridged, we often want the FBM to be normalized to [-1,1] first or have a known range.
        // Let's assume FBM output is not pre-normalized here.
        // The `baseSettings.amplitude` will scale the FBM result.
        float fbm_signal = FBM3D::fbm_perlin_3d(position, baseSettings, fbmSettings, perm_table);

        // 2. Apply ridged transformation
        // The fbm_signal already includes baseSettings.amplitude.
        // If baseSettings.amplitude is 1, and FBM sums to ~2, signal is ~[-2, 2].
        // We need to consider the range of fbm_signal for apply_ridged_transform.
        // Let's assume apply_ridged_transform expects signal in roughly [-1, 1] for best results with offset=1.
        // For now, let's pass it directly, user may need to tune amplitudes.
        // Alternatively, we can try to estimate max possible FBM value and normalize.
        // Or, we can make the FBM functions return a more predictable [-1,1] or [0,1] range.
        
        // A common approach for Ridged FBM is to modify the FBM accumulation loop:
        // signal = 0.0;
        // weight = 1.0;
        // loop octaves:
        //   n = base_noise(...);
        //   n = offset - abs(n);
        //   n = pow(n, exponent);
        //   signal += n * weight * amplitude_for_this_octave;
        //   weight = n * gain; // feedback loop, gain typically < 1
        // This is more complex. For V1, simple post-FBM transform:

        return apply_ridged_transform(fbm_signal / baseSettings.amplitude, // Normalize FBM by its initial amplitude
                                      ridgedSettings.ridgeExponent,
                                      ridgedSettings.ridgeOffset,
                                      ridgedSettings.ridgeWeight) * baseSettings.amplitude; // Re-apply overall amplitude
    }

    float ridged_fbm_simplex_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,
        constant FBMNoiseSettings &fbmSettings,
        constant RidgedNoiseSettings &ridgedSettings,
        thread const int perm_table[512]
    ) {
        float fbm_signal = FBM3D::fbm_simplex_3d(position, baseSettings, fbmSettings, perm_table);
        // Normalize by initial amplitude before applying ridged transform for consistency
        float normalized_fbm = (baseSettings.amplitude == 0.0f) ? 0.0f : (fbm_signal / baseSettings.amplitude);

        return apply_ridged_transform(normalized_fbm,
                                      ridgedSettings.ridgeExponent,
                                      ridgedSettings.ridgeOffset,
                                      ridgedSettings.ridgeWeight) * baseSettings.amplitude;
    }
    
    float ridged_fbm_value_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,
        constant FBMNoiseSettings &fbmSettings,
        constant RidgedNoiseSettings &ridgedSettings,
        thread const int perm_table[512]
    ) {
        float fbm_signal = FBM3D::fbm_value_3d(position, baseSettings, fbmSettings, perm_table);
        // Value FBM is already mostly positive, [0, SumOfAmps].
        // To make it work with `offset - abs(signal)`, we might need to shift it to be centered around 0.
        // e.g., fbm_signal_centered = (fbm_signal / MaxPossibleFBMValueForValue) * 2.0 - 1.0;
        // This is getting complicated for V1 with Value noise as base for ridged.
        // A simpler approach for Value-based Ridged might be different.
        // For now, apply the same transform, user must be aware of Value FBM's range.
        float normalized_fbm = (baseSettings.amplitude == 0.0f) ? 0.0f : (fbm_signal / baseSettings.amplitude);
        // If Value FBM is [0, SumOfAmps], normalized_fbm with amplitude=1 is [0, SumOfPersistences]
        // This might not give typical ridged results if normalized_fbm is always positive.
        // A quick hack: treat positive Value FBM as if it were centered, for similar transform:
        // float signal_for_ridged = normalized_fbm - ridgedSettings.ridgeOffset; // Shift it down so abs works
        
        // Sticking to the simple formula:
        return apply_ridged_transform(normalized_fbm, // This will likely not look like typical ridged if FBM is always >0
                                      ridgedSettings.ridgeExponent,
                                      ridgedSettings.ridgeOffset,
                                      ridgedSettings.ridgeWeight) * baseSettings.amplitude;
        // TODO: Consider a more suitable ridged transform if base noise is unipolar (like Value noise).
        // For V1, this might mean `ridged_fbm_value_3d` may need careful parameter tuning or
        // users should prefer Perlin/Simplex as base for standard ridged effects.
    }

} // namespace RidgedNoise3D