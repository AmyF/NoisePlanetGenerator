#include <metal_stdlib>
#include "SimplexNoise3D.metalh"
#include "MathUtils.metalh"       // For fade, lerp (though Simplex often doesn't use lerp directly like Perlin)
#include "PermutationTable.metalh" // For perm_table access (or its hash function for gradients)

using namespace metal;

// Simplex Noise implementation based on Stefan Gustavson's paper and various web sources.
// Reminder: Check patent status for your use case.
namespace SimplexNoise3D {

    // Skewing and unskewing factors for 3D
    constant float F3 = 1.0f / 3.0f;
    constant float G3 = 1.0f / 6.0f;

    // Gradients for 3D Simplex noise (12 aperiodic gradients)
    // These are the midpoints of the edges of a cube.
    constant int grad3_lut[12][3] = {
        {1,1,0}, {-1,1,0}, {1,-1,0}, {-1,-1,0},
        {1,0,1}, {-1,0,1}, {1,0,-1}, {-1,0,-1},
        {0,1,1}, {0,-1,1}, {0,1,-1}, {0,-1,-1}
    };
    
    // Helper to compute dot product of gradient and vector from simplex corner to point
    inline float grad_dot_simplex(int hash_val, float x, float y, float z) {
        int h = hash_val & 11; // Use only first 12 gradients
        return float(grad3_lut[h][0])*x + float(grad3_lut[h][1])*y + float(grad3_lut[h][2])*z;
    }
    
    float simplex_noise_3d(
        float3 position,
        BaseNoiseSettings settings,
        thread const int perm_table[512]
    ) {
        float3 p = position * settings.frequency + settings.offset;

        // Skew the input space to determine which simplex cell we're in
        float s = (p.x + p.y + p.z) * F3; // Hairy factor for 3D
        int i = fast::floor(p.x + s);
        int j = fast::floor(p.y + s);
        int k = fast::floor(p.z + s);

        float t = float(i + j + k) * G3;
        float X0 = float(i) - t; // Unskewed grid origin
        float Y0 = float(j) - t;
        float Z0 = float(k) - t;

        float x0 = p.x - X0; // The x,y,z distances from the cell origin
        float y0 = p.y - Y0;
        float z0 = p.z - Z0;

        // For the 3D case, the simplex shape is a tetrahedron.
        // Determine which simplex we are in.
        int i1, j1, k1; // Offsets for second corner of simplex in (i,j,k) coords
        int i2, j2, k2; // Offsets for third corner of simplex in (i,j,k) coords

        if (x0 >= y0) {
            if (y0 >= z0)      { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 1; k2 = 0; } // X Y Z order
            else if (x0 >= z0) { i1 = 1; j1 = 0; k1 = 0; i2 = 1; j2 = 0; k2 = 1; } // X Z Y order
            else               { i1 = 0; j1 = 0; k1 = 1; i2 = 1; j2 = 0; k2 = 1; } // Z X Y order
        } else { // x0 < y0
            if (y0 < z0)       { i1 = 0; j1 = 0; k1 = 1; i2 = 0; j2 = 1; k2 = 1; } // Z Y X order
            else if (x0 < z0)  { i1 = 0; j1 = 1; k1 = 0; i2 = 0; j2 = 1; k2 = 1; } // Y Z X order
            else               { i1 = 0; j1 = 1; k1 = 0; i2 = 1; j2 = 1; k2 = 0; } // Y X Z order
        }

        // A step of (1,0,0) in (i,j,k) means a step of (1-c,-c,-c) in (x,y,z),
        // c = 1/6.
        float x1 = x0 - float(i1) + G3; // Offsets for second corner in unskewed coords
        float y1 = y0 - float(j1) + G3;
        float z1 = z0 - float(k1) + G3;
        float x2 = x0 - float(i2) + 2.0f * G3; // Offsets for third corner in unskewed coords
        float y2 = y0 - float(j2) + 2.0f * G3;
        float z2 = z0 - float(k2) + 2.0f * G3;
        float x3 = x0 - 1.0f + 3.0f * G3; // Offsets for last corner in unskewed coords
        float y3 = y0 - 1.0f + 3.0f * G3;
        float z3 = z0 - 1.0f + 3.0f * G3;

        // Work out the hashed gradient indices of the four simplex corners
        int ii = i & 255;
        int jj = j & 255;
        int kk = k & 255;

        int gi0 = perm_table[ii + perm_table[jj + perm_table[kk]]];
        int gi1 = perm_table[ii + i1 + perm_table[jj + j1 + perm_table[kk + k1]]];
        int gi2 = perm_table[ii + i2 + perm_table[jj + j2 + perm_table[kk + k2]]];
        int gi3 = perm_table[ii + 1  + perm_table[jj + 1  + perm_table[kk + 1 ]]];

        // Calculate the contribution from the four corners
        float n0, n1, n2, n3; // Noise contributions from the four corners

        float t0 = 0.6f - x0*x0 - y0*y0 - z0*z0; // Radial falloff (0.6 instead of 0.5 for slightly better range)
        if (t0 < 0.0f) n0 = 0.0f;
        else {
            t0 *= t0;
            n0 = t0 * t0 * grad_dot_simplex(gi0, x0, y0, z0);
        }

        float t1 = 0.6f - x1*x1 - y1*y1 - z1*z1;
        if (t1 < 0.0f) n1 = 0.0f;
        else {
            t1 *= t1;
            n1 = t1 * t1 * grad_dot_simplex(gi1, x1, y1, z1);
        }

        float t2 = 0.6f - x2*x2 - y2*y2 - z2*z2;
        if (t2 < 0.0f) n2 = 0.0f;
        else {
            t2 *= t2;
            n2 = t2 * t2 * grad_dot_simplex(gi2, x2, y2, z2);
        }

        float t3 = 0.6f - x3*x3 - y3*y3 - z3*z3;
        if (t3 < 0.0f) n3 = 0.0f;
        else {
            t3 *= t3;
            n3 = t3 * t3 * grad_dot_simplex(gi3, x3, y3, z3);
        }

        // Add contributions from each corner to get the final noise value.
        // The result is usually scaled to return values in the range [-1,1].
        // The factor 32.0 (or sometimes 28-32) is empirical.
        float noise_val = 32.0f * (n0 + n1 + n2 + n3);
        
        return noise_val * settings.amplitude;
    }

} // namespace SimplexNoise3D
