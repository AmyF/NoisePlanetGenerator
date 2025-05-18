#include <metal_stdlib>
#include "WorleyNoise3D.metalh"
#include "MathUtils.metalh"
#include "PermutationTable.metalh" // For hashing cell indices

using namespace metal;

namespace WorleyNoise3D {

    // Generates a pseudo-random feature point within a given integer cell
    // using the permutation table for hashing.
    // The seedOffset from worleySettings is used to vary point sets.
    inline float3 get_feature_point_in_cell(int3 cell_coord,
                                            float jitter,
                                            uint primary_seed, // from perm_table initialization via global seed
                                            uint worley_seed_offset,
                                            thread const int perm_table[512])
    {
        // Combine primary_seed (implicitly in perm_table state) and worley_seed_offset
        // to create a unique hash for this cell and Worley instance.
        // A simple way is to add seedOffset to one of the components before hashing.
        uint h1 = PermutationTable::P_DEFAULT[(cell_coord.x + worley_seed_offset) & 255];
        uint h2 = PermutationTable::P_DEFAULT[(cell_coord.y + h1 + worley_seed_offset) & 255];
        uint h3 = PermutationTable::P_DEFAULT[(cell_coord.z + h2 + worley_seed_offset) & 255];
        
        // Use these hash values to generate offsets within the cell [0,1)
        // then scale by jitter.
        float r1 = MathUtils::hash_to_float01(h1); // val in [0,1)
        float r2 = MathUtils::hash_to_float01(h2);
        float r3 = MathUtils::hash_to_float01(h3);

        // Jitter: 0 = point at cell corner, 1 = point anywhere in cell
        // Offset from cell corner:
        float3 offset_in_cell = float3(r1, r2, r3) * jitter;
        
        // For jitter = 1, this is a point within [0,1)^3 inside the cell.
        // If jitter < 1, it's closer to the cell's origin.
        // To center jitter around 0.5 for jitter=1:
        // float3 offset_in_cell = (float3(r1, r2, r3) - 0.5f) * jitter + 0.5f;
        // Let's stick to simpler [0, jitter) for now, or just r*jitter
        
        return float3(cell_coord) + offset_in_cell; // point position in space of 'p'
    }


    WorleyDistances calculate_worley_distances_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,
        constant WorleyNoiseSettings &worleySettings,
        thread const int perm_table[512] // Permutation table already initialized with global seed
    ) {
        float3 p = position * baseSettings.frequency + baseSettings.offset;
        int3 cell_p = int3(floor(p)); // Integer coordinates of the cell 'p' is in

        WorleyDistances dists;
        dists.F1 = MAXFLOAT; // Using FLT_MAX from C, metal equivalent is MAXFLOAT
        dists.F2 = MAXFLOAT;

        // Search in a 3x3x3 cube of cells around cell_p
        for (int k = -1; k <= 1; ++k) {
            for (int j = -1; j <= 1; ++j) {
                for (int i = -1; i <= 1; ++i) {
                    int3 neighbor_cell = cell_p + int3(i, j, k);
                    
                    // Generate feature point for this neighbor cell
                    // The global seed is already incorporated into perm_table.
                    // worleySettings.seedOffset allows this Worley instance to differ from others.
                    float3 feature_point = get_feature_point_in_cell(
                        neighbor_cell,
                        worleySettings.jitter,
                        0, // main seed baked into perm_table
                        worleySettings.seedOffset,
                        perm_table
                    );

                    float d_sq; // squared distance
                    // if (worleySettings.useManhattanDistance) { // V1 simplified
                    //    d_sq = abs(p.x - feature_point.x) + abs(p.y - feature_point.y) + abs(p.z - feature_point.z);
                    // } else {
                        float3 diff = p - feature_point;
                        d_sq = dot(diff, diff);
                    // }
                    
                    // Using sqrt for actual distance comparison, common for Worley
                    float d = sqrt(d_sq);

                    if (d < dists.F1) {
                        dists.F2 = dists.F1;
                        dists.F1 = d;
                    } else if (d < dists.F2) {
                        dists.F2 = d;
                    }
                }
            }
        }
        return dists;
    }

    float worley_noise_3d(
        float3 position,
        constant BaseNoiseSettings &baseSettings,
        constant WorleyNoiseSettings &worleySettings,
        thread const int perm_table[512]
    ) {
        WorleyDistances dists = calculate_worley_distances_3d(position, baseSettings, worleySettings, perm_table);
        
        // As per user request, for NoiseTypeWorley_F2F1, output F2-F1
        float result = dists.F2 - dists.F1;
        
        return result * baseSettings.amplitude;
    }

} // namespace WorleyNoise3D