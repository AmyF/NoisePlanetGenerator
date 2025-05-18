#include <metal_stdlib>
#include "ValueNoise3D.metalh"    // Include its own header
#include "MathUtils.metalh"       // For fade, lerp, hash_to_float01
#include "PermutationTable.metalh"// For perm_table type, though direct access is through param

using namespace metal;

namespace ValueNoise3D {

    // Helper hash for Value Noise grid points using the permutation table
    // Ensures a consistent pseudo-random value for each integer grid point.
    inline uint hash_grid_point(int3 p_int, thread const int perm_table[512]) {
        int X = p_int.x & 255;
        int Y = p_int.y & 255;
        int Z = p_int.z & 255;
        // Classic hashing scheme using the permutation table
        return uint(perm_table[X + perm_table[Y + perm_table[Z]]]);
    }

    // Value Noise 3D Implementation
    float value_noise_3d(
        float3 position,
        BaseNoiseSettings settings,
        thread const int perm_table[512]
    ) {
        float3 p = position * settings.frequency + settings.offset;

        int3 pi0 = int3(floor(p));    // Integer part / cell coordinates
        float3 pf0 = p - float3(pi0); // Fractional part [0,1)

        // Quintic interpolation weights for smoother results
        float3 w = float3(MathUtils::fade(pf0.x), MathUtils::fade(pf0.y), MathUtils::fade(pf0.z)); // NEW

        // Hash coordinates of the 8 cube corners to get their pseudo-random values
        float v000 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(0,0,0), perm_table));
        float v100 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(1,0,0), perm_table));
        float v010 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(0,1,0), perm_table));
        float v110 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(1,1,0), perm_table));
        float v001 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(0,0,1), perm_table));
        float v101 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(1,0,1), perm_table));
        float v011 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(0,1,1), perm_table));
        float v111 = MathUtils::hash_to_float01(hash_grid_point(pi0 + int3(1,1,1), perm_table));
        
        // Trilinear interpolation (actually tricubic due to fade weights)
        float vx00 = MathUtils::lerp(v000, v100, w.x);
        float vx10 = MathUtils::lerp(v010, v110, w.x);
        float vx01 = MathUtils::lerp(v001, v101, w.x);
        float vx11 = MathUtils::lerp(v011, v111, w.x);

        float vxy0 = MathUtils::lerp(vx00, vx10, w.y);
        float vxy1 = MathUtils::lerp(vx01, vx11, w.y);

        float final_val = MathUtils::lerp(vxy0, vxy1, w.z);

        // Value noise (with hash_to_float01) is naturally in [0,1] before amplitude.
        return final_val * settings.amplitude;
    }

} // namespace ValueNoise3D
