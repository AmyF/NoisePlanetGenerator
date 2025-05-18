#include <metal_stdlib>
#include "CurlNoise3D.metalh"
#include "PerlinNoise3D.metalh"   // Potential base noise
#include "SimplexNoise3D.metalh"  // Potential base noise
#include "ValueNoise3D.metalh"    // Potential base noise
// MathUtils.metalh might be needed if base noise functions don't include all math.
// PermutationTable.metalh is included by the base noise .metal files.

using namespace metal;

namespace CurlNoise3D {

    // Helper function to sample the underlying scalar potential field component.
    // This is a dispatcher based on curlSettings.curlBaseNoiseType.
    // It uses a unique offset for each component (x, y, z) to ensure
    // the three scalar fields used for the vector potential are somewhat independent.
    inline float sample_potential_component(
        float3 p,
        NoiseType base_noise_type,
        float base_frequency,
        float base_amplitude, // Amplitude of the base noise component
        float3 component_offset, // Unique offset for this component's field
        thread const int perm_table[512]
    ) {
        BaseNoiseSettings settings;
        settings.frequency = base_frequency;
        settings.amplitude = base_amplitude; // Base noise functions scale by this
        settings.offset = component_offset;  // Apply component-specific offset

        // Important: The 'position' 'p' here is already the point at which we want
        // to evaluate the potential. The 'settings.offset' is an additional global
        // offset for this entire potential field component.
        
        float noise_val = 0.0f;

        // Simplified: Assuming curlBaseNoiseType in curlSettings will guide which one to use.
        // This structure is hard to do directly in MSL without function pointers or many if/elses.
        // For a cleaner MSL implementation, the PlanetTextureGenerator would select which
        // Curl noise variant to call (e.g., curl_using_perlin, curl_using_simplex).
        // Or, this function could have many if-else if branches.

        // For this example, let's assume the base_noise_type is passed and handled:
        // This is a conceptual simplification. In practice, you might have:
        // float3 potential_x_field_params, potential_y_field_params, etc.
        // For V1, we'll simplify: use the *same* base noise type and params for all 3 potential components,
        // but with different *offsets* to decorrelate them.

        if (base_noise_type == NoiseTypePerlin) {
            noise_val = PerlinNoise3D::perlin_noise_3d(p, settings, perm_table);
        } else if (base_noise_type == NoiseTypeSimplex) {
            noise_val = SimplexNoise3D::simplex_noise_3d(p, settings, perm_table);
        } else if (base_noise_type == NoiseTypeValue) {
            noise_val = ValueNoise3D::value_noise_3d(p, settings, perm_table);
        }
        // Add other base noise types if curl can use them

        return noise_val;
    }


    // Curl Noise 3D Implementation
    // Computes curl using finite differences.
    // curl(F) = (dFz/dy - dFy/dz, dFx/dz - dFz/dx, dFy/dx - dFx/dy)
    // where F = (Fx, Fy, Fz) is the vector potential field.
    // We generate Fx, Fy, Fz using three instances of a base scalar noise function,
    // typically with large offsets from each other to make them appear independent.
    float3 curl_noise_3d(
        float3 position,
        constant BaseNoiseSettings &overallBaseSettings, // For main position scaling/offset
        constant CurlNoiseSettings &curlSettings,
        thread const int perm_table[512]
    ) {
        float3 p = position * overallBaseSettings.frequency + overallBaseSettings.offset;
        float eps = curlSettings.curlStepSize; // Epsilon for finite differences

        // Define large offsets to decorrelate the three scalar fields
        // These could also be parameters or derived from the seedOffset.
        // For simplicity, using fixed large offsets.
        // The curlSeedOffset from curlSettings can be added to the component_offset
        // or used in the sample_potential_component's base noise seed if that was exposed.
        // Here, we'll add it to the component_offset passed to sample_potential_component.
        
        float3 offset_x = float3(0.0f, 123.456f, 789.012f) + float3(curlSettings.curlSeedOffset);
        float3 offset_y = float3(456.789f, 0.0f, 123.456f) + float3(curlSettings.curlSeedOffset);
        float3 offset_z = float3(789.012f, 456.789f, 0.0f) + float3(curlSettings.curlSeedOffset);

        // Sample the three components of the vector potential field F = (Fx, Fy, Fz)
        // Fx = Psi_x(p), Fy = Psi_y(p), Fz = Psi_z(p)
        // where Psi_x, Psi_y, Psi_z are three independent scalar noise fields.

        // For dFz/dy (used in curl_x)
        float pz_y_plus_eps  = sample_potential_component(p + float3(0, eps, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_z, perm_table);
        float pz_y_minus_eps = sample_potential_component(p - float3(0, eps, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_z, perm_table);
        // For dFy/dz (used in curl_x)
        float py_z_plus_eps  = sample_potential_component(p + float3(0, 0, eps), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_y, perm_table);
        float py_z_minus_eps = sample_potential_component(p - float3(0, 0, eps), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_y, perm_table);

        // For dFx/dz (used in curl_y)
        float px_z_plus_eps  = sample_potential_component(p + float3(0, 0, eps), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_x, perm_table);
        float px_z_minus_eps = sample_potential_component(p - float3(0, 0, eps), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_x, perm_table);
        // For dFz/dx (used in curl_y)
        float pz_x_plus_eps  = sample_potential_component(p + float3(eps, 0, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_z, perm_table);
        float pz_x_minus_eps = sample_potential_component(p - float3(eps, 0, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_z, perm_table);

        // For dFy/dx (used in curl_z)
        float py_x_plus_eps  = sample_potential_component(p + float3(eps, 0, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_y, perm_table);
        float py_x_minus_eps = sample_potential_component(p - float3(eps, 0, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_y, perm_table);
        // For dFx/dy (used in curl_z)
        float px_y_plus_eps  = sample_potential_component(p + float3(0, eps, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_x, perm_table);
        float px_y_minus_eps = sample_potential_component(p - float3(0, eps, 0), curlSettings.curlBaseNoiseType, curlSettings.curlBaseFrequency, curlSettings.curlBaseAmplitude, offset_x, perm_table);

        float two_eps = 2.0f * eps;

        float curl_x = (pz_y_plus_eps - pz_y_minus_eps) / two_eps - (py_z_plus_eps - py_z_minus_eps) / two_eps;
        float curl_y = (px_z_plus_eps - px_z_minus_eps) / two_eps - (pz_x_plus_eps - pz_x_minus_eps) / two_eps;
        float curl_z = (py_x_plus_eps - py_x_minus_eps) / two_eps - (px_y_plus_eps - px_y_minus_eps) / two_eps;
        
        // The curl vector does not get scaled by overallBaseSettings.amplitude here,
        // as its magnitude is determined by the derivatives of the potential field
        // (which itself is scaled by curlSettings.curlBaseAmplitude).
        // If overallBaseSettings.amplitude is meant to scale the *intensity* of the curl effect,
        // it should be applied in PlanetTextureGenerator when interpreting the curl.
        return float3(curl_x, curl_y, curl_z);
    }

} // namespace CurlNoise3D