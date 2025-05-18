#include <metal_stdlib>
#include "../../SharedTypes/include/NoisePlanetTypes.h" // All parameter structs and enums
#include "CoordinateUtils.metalh"
#include "PermutationTable.metalh"
#include "ValueNoise3D.metalh"
#include "PerlinNoise3D.metalh"
#include "SimplexNoise3D.metalh"
#include "WorleyNoise3D.metalh"
#include "FBM3D.metalh"
#include "RidgedNoise3D.metalh"
#include "CurlNoise3D.metalh"
#include "MathUtils.metalh" // For remap function

using namespace metal;

// Kernel function to generate the planet texture layer
kernel void generatePlanetTexture(
    texture2d<float, access::write> outputTexture [[texture(0)]], // V1: output float, user maps to color later
    constant PlanetSurfaceParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // 1. Initialize permutation table for this thread/threadgroup
    // For simplicity, let's assume each thread initializes its own copy if not using threadgroup memory.
    // If using threadgroup memory, one thread in group initializes.
    // For now, each thread will have its conceptual perm table derived from the seed.
    // A full 512 int array in thread memory might be large.
    // A better approach for the perm table is to pass it as a read-only buffer initialized on CPU
    // or a threadgroup-shared array initialized once per group.
    // For this example, let's assume the noise functions can take the seed and handle perm internally,
    // or that the perm_table argument to noise functions is correctly populated.
    // We'll make a thread-local copy for this example logic.
    // This is NOT efficient for real use, pass pre-shuffled perm table (e.g. in a buffer)
    // or use threadgroup shared memory.
    // For V1 simplicity and focusing on MSL structure:
    thread int perm_table[512]; // This will be large for thread memory.
    PermutationTable::initialize_perm_table(params.randomSeed, perm_table);


    // 2. Get texture dimensions (passed implicitly via outputTexture.get_width/height)
    uint width = outputTexture.get_width();
    uint height = outputTexture.get_height();

    if (gid.x >= width || gid.y >= height) {
        return; // Out of bounds thread
    }

    // 3. Convert grid ID (pixel coordinate) to normalized UV [0,1]
    float2 uv = float2(gid.x + 0.5f, gid.y + 0.5f) / float2(width, height); // Sample pixel centers

    // 4. Convert UV to 3D point on sphere surface
    float3 p_sphere = CoordinateUtils::equirectangular_uv_to_cartesian_on_sphere(uv, params.sphereRadius);

    // 5. Select and compute noise based on params.noiseTypeToGenerate
    float raw_noise_value = 0.0f;

    switch (params.noiseTypeToGenerate) {
        case NoiseTypePerlin:
            raw_noise_value = PerlinNoise3D::perlin_noise_3d(p_sphere, params.baseSettings, perm_table);
            break;
        case NoiseTypeSimplex:
            raw_noise_value = SimplexNoise3D::simplex_noise_3d(p_sphere, params.baseSettings, perm_table);
            break;
        case NoiseTypeValue:
            raw_noise_value = ValueNoise3D::value_noise_3d(p_sphere, params.baseSettings, perm_table);
            break;
        case NoiseTypeWorley_F2F1:
            raw_noise_value = WorleyNoise3D::worley_noise_3d(p_sphere, params.baseSettings, params.worleySettings, perm_table);
            break;
        case NoiseTypeFBM_Perlin:
            raw_noise_value = FBM3D::fbm_perlin_3d(p_sphere, params.baseSettings, params.fbmSettings, perm_table);
            break;
        case NoiseTypeFBM_Simplex:
            raw_noise_value = FBM3D::fbm_simplex_3d(p_sphere, params.baseSettings, params.fbmSettings, perm_table);
            break;
        case NoiseTypeFBM_Value:
            raw_noise_value = FBM3D::fbm_value_3d(p_sphere, params.baseSettings, params.fbmSettings, perm_table);
            break;
        case NoiseTypeRidged_FBM_Perlin:
            raw_noise_value = RidgedNoise3D::ridged_fbm_perlin_3d(p_sphere, params.baseSettings, params.fbmSettings, params.ridgedSettings, perm_table);
            break;
        case NoiseTypeRidged_FBM_Simplex:
            raw_noise_value = RidgedNoise3D::ridged_fbm_simplex_3d(p_sphere, params.baseSettings, params.fbmSettings, params.ridgedSettings, perm_table);
            break;
        case NoiseTypeRidged_FBM_Value:
            raw_noise_value = RidgedNoise3D::ridged_fbm_value_3d(p_sphere, params.baseSettings, params.fbmSettings, params.ridgedSettings, perm_table);
            break;
        case NoiseTypeCurl_Intensity:
            {
                float3 curl_vector = CurlNoise3D::curl_noise_3d(p_sphere, params.baseSettings, params.curlSettings, perm_table);
                raw_noise_value = length(curl_vector) * params.baseSettings.amplitude; // Apply overall amplitude to intensity
            }
            break;
        // default: // Optional: handle unknown type or do nothing
            // raw_noise_value = 0.0f;
            // break;
    }

    // 6. Normalize/Map the output value (Mandatory as per user request)
    float final_output_value = raw_noise_value;
    if (params.outputProcessing.normalizeOutput01) {
        final_output_value = MathUtils::remap(
            raw_noise_value,
            params.outputProcessing.expectedInputMin,
            params.outputProcessing.expectedInputMax,
            0.0f,
            1.0f
        );
        final_output_value = saturate(final_output_value); // Clamp to [0,1]
    }
    // If output texture is not float, and e.g. half4, convert final_output_value here.
    // For V1, we assume outputTexture is float.
    // float4 color_output = float4(final_output_value, final_output_value, final_output_value, 1.0f);

    // 7. Write to output texture
    outputTexture.write(final_output_value, gid);
}
