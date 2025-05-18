import Metal
import MetalKit // For MTLDevice, etc.
import simd    // For float3 etc. on CPU side if needed
import SharedTypes

// Import shared types if your Package.swift exposes them correctly
// from the Shaders target to this Swift target.
// This might require more setup in Package.swift or an umbrella header.
// For simplicity, assume direct access or manual redefinition for now.
// #include "NoisePlanetTypes.h" // This won't work directly in Swift

// ---- Manually redefine or bridge NoisePlanetTypes.h enums/structs in Swift ----
// Example (manual bridging is tedious and error-prone, better to use Clang importer via module map if possible)
public enum NoiseTypeSwift: UInt16 {
    case perlin = 0 // Ensure values match MSL enum
    case simplex
    case value
    case worley_F2F1
    case fbm_Perlin
    case fbm_Simplex
    case fbm_Value
    case ridged_FBM_Perlin
    case ridged_FBM_Simplex
    case ridged_FBM_Value
    case curl_Intensity
    // ... map all values from NoisePlanetTypes.h NoiseType
}

public struct BaseNoiseSettingsSwift {
    public var frequency: Float
    public var amplitude: Float
    public var offset: SIMD3<Float>
    // public var periodic: Bool // V1 not used
    // public var period: SIMD3<Float> // V1 not used

    public init(frequency: Float, amplitude: Float, offset: SIMD3<Float>) {
        self.frequency = frequency
        self.amplitude = amplitude
        self.offset = offset
    }
}

// ... Define ALL other structs from NoisePlanetTypes.h similarly for Swift ...
// (FBMNoiseSettingsSwift, WorleyNoiseSettingsSwift, etc.)
// (OutputProcessingSettingsSwift)
// (PlanetSurfaceParamsSwift)
// This is a lot of boilerplate. A proper C interop setup would be better.

// For this example, we'll assume you have a way to get PlanetSurfaceParams into a MTLBuffer.

public class PlanetTextureGeneratorAPI {
    private var device: MTLDevice
    private var commandQueue: MTLCommandQueue
    private var pipelineState: MTLComputePipelineState

    public init?(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        // Load the library from the Shaders target
        // This assumes the SPM structure correctly builds and links the .metallib
        // For an app, you'd use device.makeDefaultLibrary() or device.makeLibrary(filepath: ...)
        // For a library within SPM, it might be Bundle.module for the Shaders target.
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module), // Bundle.module refers to current SPM target
              let kernelFunction = library.makeFunction(name: "generatePlanetTexture") else {
            print("Error: Could not load Metal library or kernel function.")
            return nil
        }
        
        do {
            self.pipelineState = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Error: Could not create compute pipeline state: \(error)")
            return nil
        }
    }

    public func generateTexture(
        width: Int,
        height: Int,
        // Pass your PlanetSurfaceParamsSwift struct here
        params: PlanetSurfaceParams // This needs to be the MSL-compatible C struct
    ) -> MTLTexture? {

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, // Assuming single float output for V1
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .shaderRead] // ShaderRead if you blend in next step on GPU
        if device.hasUnifiedMemory {
            textureDescriptor.storageMode = .shared
        } else {
            textureDescriptor.storageMode = .private
        }

        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        computeCommandEncoder.setComputePipelineState(pipelineState)
        computeCommandEncoder.setTexture(outputTexture, index: 0)

        // Convert Swift `params` to a Data buffer or use setBytes
        var mutableParams = params // Make it mutable to get its pointer
        computeCommandEncoder.setBytes(&mutableParams, length: MemoryLayout<PlanetSurfaceParams>.stride, index: 0)
        // Ensure PlanetSurfaceParams is laid out identically in Swift and MSL.
        // Using `MemoryLayout<PlanetSurfaceParams>.stride` is crucial.

        let threadgroupSize = MTLSize(width: pipelineState.threadExecutionWidth,
                                     height: pipelineState.maxTotalThreadsPerThreadgroup / pipelineState.threadExecutionWidth,
                                     depth: 1)
        let gridWidth = (width + threadgroupSize.width - 1) / threadgroupSize.width
        let gridHeight = (height + threadgroupSize.height - 1) / threadgroupSize.height
        let gridSize = MTLSize(width: gridWidth, height: gridHeight, depth: 1)

        computeCommandEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadgroupSize)
        computeCommandEncoder.endEncoding()
        commandBuffer.commit()
        // commandBuffer.waitUntilCompleted() // If you need it immediately for CPU access or next step

        return outputTexture
    }
}
