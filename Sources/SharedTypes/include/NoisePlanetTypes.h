#ifndef NoisePlanetTypes_h
#define NoisePlanetTypes_h

// Define types based on compilation environment (MSL vs C/Swift)
#ifdef __METAL_VERSION__
    #include <metal_stdlib>
    using namespace metal;

    // For MSL, use its native types
    #define NOISE_PLANET_ENUM_UNDERLYING_TYPE ushort
    #define PORTABLE_FLOAT3 float3
    #define PORTABLE_UINT   uint   // MSL's uint is 32-bit
    #define PORTABLE_BOOL   bool   // MSL's bool
    #define PORTABLE_INT    int    // MSL's int is 32-bit

#else // For C/C++/Objective-C interoperability with Swift
    #include <stdint.h>    // For C's fixed-width integers (uint16_t, uint32_t, int32_t)
    #include <stdbool.h>   // For C99 bool
    #include <simd/simd.h> // For C's SIMD vector types (vector_float3)

    // For C/Swift, use C standard types that bridge well to Swift
    typedef uint16_t NoisePlanetEnumUnderlyingType_CSwift; // Explicitly define for C/Swift
    #define NOISE_PLANET_ENUM_UNDERLYING_TYPE NoisePlanetEnumUnderlyingType_CSwift

    typedef vector_float3 float3_CSwift; // float3 for C/Swift
    #define PORTABLE_FLOAT3 float3_CSwift

    typedef uint32_t uint_CSwift;   // uint for C/Swift
    #define PORTABLE_UINT uint_CSwift

    typedef bool bool_CSwift;       // bool for C/Swift
    #define PORTABLE_BOOL bool_CSwift
    
    typedef int32_t int_CSwift;       // int for C/Swift
    #define PORTABLE_INT int_CSwift

#endif

// Common Enum Definition using the preprocessor macro
typedef enum : NOISE_PLANET_ENUM_UNDERLYING_TYPE {
    NoiseTypePerlin,
    NoiseTypeSimplex,
    NoiseTypeValue,
    NoiseTypeWorley_F2F1,
    NoiseTypeFBM_Perlin,
    NoiseTypeFBM_Simplex,
    NoiseTypeFBM_Value,
    NoiseTypeRidged_FBM_Perlin,
    NoiseTypeRidged_FBM_Simplex,
    NoiseTypeRidged_FBM_Value,
    NoiseTypeCurl_Intensity
} NoiseType;

// Common Struct Definitions using preprocessor macros for types
typedef struct {
    float frequency;
    float amplitude;
    PORTABLE_FLOAT3 offset;
} BaseNoiseSettings;

typedef struct {
    PORTABLE_INT octaves; // Changed from int to PORTABLE_INT
    float persistence;
    float lacunarity;
} FBMNoiseSettings;

typedef struct {
    float jitter;
    PORTABLE_UINT seedOffset;
} WorleyNoiseSettings;

typedef struct {
    float ridgeExponent;
    float ridgeOffset;
    float ridgeWeight;
} RidgedNoiseSettings;

typedef struct {
    NoiseType curlBaseNoiseType;
    float curlBaseFrequency;
    float curlBaseAmplitude;
    PORTABLE_UINT curlSeedOffset;
    float curlStepSize;
} CurlNoiseSettings;

typedef struct {
    PORTABLE_BOOL normalizeOutput01;
    float expectedInputMin;
    float expectedInputMax;
} OutputProcessingSettings;

typedef struct {
    PORTABLE_UINT randomSeed;
    float sphereRadius;
    NoiseType noiseTypeToGenerate;

    BaseNoiseSettings baseSettings;
    FBMNoiseSettings fbmSettings;
    WorleyNoiseSettings worleySettings;
    RidgedNoiseSettings ridgedSettings;
    CurlNoiseSettings curlSettings;
    OutputProcessingSettings outputProcessing;
} PlanetSurfaceParams;

#endif /* NoisePlanetTypes_h */
