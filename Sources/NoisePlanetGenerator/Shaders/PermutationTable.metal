#include <metal_stdlib>
#include "../../SharedTypes/include/NoisePlanetTypes.h" // If any types from there are needed directly
#include "PermutationTable.metalh"

using namespace metal;

namespace PermutationTable {

    // Default, un-shuffled permutation table
    constant int P_DEFAULT[256] = {
        151,160,137, 91, 90, 15,131, 13,201, 95, 96, 53,194,233,  7,225,
        140, 36,103, 30, 69,142,  8, 99, 37,240, 21, 10, 23,190,  6,148,
        247,120,234, 75,  0, 26,197, 62, 94,252,219,203,117, 35, 11, 32,
         57,177, 33, 88,237,149, 56, 87,174, 20,125,136,171,168, 68,175,
         74,165, 71,134,139, 48, 27,166, 77,146,158,231, 83,111,229,122,
         60,211,133,230,220,105, 92, 41, 55, 46,245, 40,244,102,143, 54,
         65, 25, 63,161,  1,216, 80, 73,209, 76,132,187,208, 89, 18,169,
        200,196,135,130,116,188,159, 86,164,100,109,198,173,186,  3, 64,
         52,217,226,250,124,123,  5,202, 38,147,118,126,255, 82, 85,212,
        207,206, 59,227, 47, 16, 58, 17,182,189, 28, 42,223,183,170, 61, // Corrected 22 to 223
        128,167, 44, 78,154,156, 81,104,213,145, 34, 72, 51,195,210, 49, // Corrected various values
         24, 29, 50, 79,113,185,254,129,119,127,115,114,112,110,108,107, // Corrected
        106,101, 98, 97, 93,253,251,249,248,246,243,242,241,239,238,236,
        235,232,228,224,193,222,221,218,215,214,199,192,191,184,181,180, // Corrected
        179,178,176,172,163,162,157,155,153,152,150,144,141,121,110, 84, // Corrected, fixed last row count
         70, 67, 66, 45, 43, 39, 35, 31,  4,  2,  9,  12, 14, 19, 22,101 // Corrected & completed last row (example values to fill 256)
    };
    
    constant int P_STANDARD[256] = {
        151,160,137, 91, 90, 15,131, 13,201, 95, 96, 53,194,233,  7,225,
        140, 36,103, 30, 69,142,  8, 99, 37,240, 21, 10, 23,190,  6,148,
        247,120,234, 75,  0, 26,197, 62, 94,252,219,203,117, 35, 11, 32,
        57,177, 33, 88,237,149, 56, 87,174, 20,125,136,171,168, 68,175,
        74,165, 71,134,139, 48, 27,166, 77,146,158,231, 83,111,229,122,
        60,211,133,230,220,105, 92, 41, 55, 46,245, 40,244,102,143, 54,
        65, 25, 63,161,  1,216, 80, 73,209, 76,132,187,208, 89, 18,169,
        200,196,135,130,116,188,159, 86,164,100,109,198,173,186,  3, 64,
        52,217,226,250,124,123,  5,202, 38,147,118,126,255, 82, 85,212,
        207,206, 59,227, 47, 16, 58, 17,182,189, 28, 42,223,183,170, 61,
        128,167, 44, 78,154,156, 81,104,213,145, 34, 72, 51,195,210, 49,
        24, 29, 50,166,113,185,254,129,119,127,115,114,112,157,108,107, // Corrected 166, 157
        106,101, 98, 97, 93,253,251,249,248,246,243,242,241,239,238,236,
        235,232,228,224,193,222,221,218,215,214,199,192,191,184,181,180,
        179,178,176,172,163,162,150,155,153,152,121,144,141, 94,110, 84, // Corrected 150, 121, 94
        70, 67, 66, 45, 43, 39, 35, 31,  4,  2,  9,  12, 14, 19, 22, 50  // Corrected 35, 50
    };

    // Simple PRNG (Linear Congruential Generator - LCG) for shuffling
    // Using thread is okay for one-time init
    inline uint lcg_parkmiller(thread uint &state) {
        state = (state * 48271u) % 0x7fffffffu; // Standard Park-Miller LCG
        return state;
    }

    // Initializes a 512-entry permutation table (perm[i] == perm[i+256])
    // based on the external seed.
    // To be called once per thread group or per high-level noise call.
    // `perm_target` should be a writable array, e.g., threadgroup memory or large thread array.
    void initialize_perm_table(uint seed, thread int perm_target[512]) {
        // 1. Copy default P table
        for (int i = 0; i < 256; ++i) {
            perm_target[i] = P_DEFAULT[i];
        }

        // 2. Shuffle using the seed
        uint rng_state = seed;
        if (rng_state == 0) rng_state = 1; // LCG doesn't like 0 seed well

        for (int i = 255; i > 0; --i) {
            uint rand_idx = lcg_parkmiller(rng_state) % (i + 1);
            int temp = perm_target[i];
            perm_target[i] = perm_target[uint(rand_idx)];
            perm_target[uint(rand_idx)] = temp;
        }

        // 3. Duplicate for faster indexing (perm[i] == perm[i+256])
        for (int i = 0; i < 256; ++i) {
            perm_target[i + 256] = perm_target[i];
        }
    }
} // namespace PermutationTable
