#include <metal_stdlib>
#include "PerlinNoise3D.metalh"   // Include its own header
#include "MathUtils.metalh"       // For fade, lerp
#include "PermutationTable.metalh"// For perm_table type (though access is through param)

using namespace metal;

namespace PerlinNoise3D {

    // Gradient vectors for 3D Perlin noise
    constant float3 GRAD_3D[16] = {
        float3( 1, 1, 0), float3(-1, 1, 0), float3( 1,-1, 0), float3(-1,-1, 0),
        float3( 1, 0, 1), float3(-1, 0, 1), float3( 1, 0,-1), float3(-1, 0,-1),
        float3( 0, 1, 1), float3( 0,-1, 1), float3( 0, 1,-1), float3( 0,-1,-1),
        float3( 1, 1, 0), float3(-1, 1, 0), float3( 0,-1, 1), float3( 0,-1,-1)
    };

    // Dot product of gradient and fractional vector
    inline float grad_dot(int hash_val, float x, float y, float z) {
        return dot(GRAD_3D[hash_val & 15], float3(x, y, z));
    }

    // Perlin Noise 3D Implementation
    float perlin_noise_3d(
        float3 position,
        BaseNoiseSettings settings, // CHANGED
        thread const int perm_table[512]
    ) {
        float3 p = position * settings.frequency + settings.offset;

        int3 pi0 = int3(floor(p));
        float3 pf0 = p - float3(pi0);
        float3 pf1 = pf0 - 1.0f;

        int X = pi0.x & 255;
        int Y = pi0.y & 255;
        int Z = pi0.z & 255;

        int gi000 = perm_table[X + perm_table[Y + perm_table[Z]]];
        int gi001 = perm_table[X + perm_table[Y + perm_table[Z + 1]]];
        int gi010 = perm_table[X + perm_table[Y + 1 + perm_table[Z]]];
        int gi011 = perm_table[X + perm_table[Y + 1 + perm_table[Z + 1]]];
        int gi100 = perm_table[X + 1 + perm_table[Y + perm_table[Z]]];
        int gi101 = perm_table[X + 1 + perm_table[Y + perm_table[Z + 1]]];
        int gi110 = perm_table[X + 1 + perm_table[Y + 1 + perm_table[Z]]];
        int gi111 = perm_table[X + 1 + perm_table[Y + 1 + perm_table[Z + 1]]];

        float n000 = grad_dot(gi000, pf0.x, pf0.y, pf0.z);
        float n100 = grad_dot(gi100, pf1.x, pf0.y, pf0.z);
        float n010 = grad_dot(gi010, pf0.x, pf1.y, pf0.z);
        float n110 = grad_dot(gi110, pf1.x, pf1.y, pf0.z);
        float n001 = grad_dot(gi001, pf0.x, pf0.y, pf1.z);
        float n101 = grad_dot(gi101, pf1.x, pf0.y, pf1.z);
        float n011 = grad_dot(gi011, pf0.x, pf1.y, pf1.z);
        float n111 = grad_dot(gi111, pf1.x, pf1.y, pf1.z);

        float3 w = float3(MathUtils::fade(pf0.x), MathUtils::fade(pf0.y), MathUtils::fade(pf0.z)); // NEW

        float nx00 = MathUtils::lerp(n000, n100, w.x);
        float nx01 = MathUtils::lerp(n001, n101, w.x);
        float nx10 = MathUtils::lerp(n010, n110, w.x);
        float nx11 = MathUtils::lerp(n011, n111, w.x);
        
        float nxy0 = MathUtils::lerp(nx00, nx10, w.y);
        float nxy1 = MathUtils::lerp(nx01, nx11, w.y);

        float final_val = MathUtils::lerp(nxy0, nxy1, w.z);
        
        // Perlin noise output is typically in [-sqrt(N/4), sqrt(N/4)], for N=3, approx [-0.866, 0.866]
        // We scale by settings.amplitude. Normalization to [0,1] will happen later.
        return final_val * settings.amplitude;
    }

} // namespace PerlinNoise3D
