import SpriteKit
import UIKit
import simd

/// The textured paper ground and road, drawn in true perspective by a fragment shader.
/// One full-width sprite covers everything below the horizon; for each pixel the shader
/// works out the world position on the ground plane (the inverse of RunScene.project)
/// and samples the road texture inside the three lanes and the ground texture outside,
/// scrolling with the distance run and fading into flat fog toward the horizon.
enum PaperGround {

    /// Returns nil when the textures aren't in the bundle, so the flat-color fallback is used.
    static func make(colored: Bool, rect: CGRect, horizonY: CGFloat, unitK: CGFloat,
                     camHeight: Double, camBack: Double, centerX: CGFloat,
                     roadName: String? = nil, groundName: String? = nil) -> SKSpriteNode? {
        let defaultRoad = colored ? "road-color" : "road-gray"
        let defaultGround = colored ? "ground-color" : "ground-gray"
        // Holiday textures replace the defaults when they're in the app.
        let roadImage = roadName.flatMap { artImage($0) } ?? artImage(defaultRoad)
        let groundImage = groundName.flatMap { artImage($0) } ?? artImage(defaultGround)
        guard let roadImage, let groundImage else { return nil }

        let road = SKTexture(image: roadImage)
        road.filteringMode = .linear
        let ground = SKTexture(image: groundImage)
        ground.filteringMode = .linear

        let sprite = SKSpriteNode(texture: ground, size: rect.size)
        sprite.anchorPoint = .zero
        sprite.position = rect.origin

        // Average texture colors, used as the distance fog so far-off detail doesn't shimmer.
        let roadFog = averageColor(roadImage)
        let groundFog = averageColor(groundImage)
        let edgeColor = colored ? SIMD3<Float>(1.0, 0.98, 0.93) : SIMD3<Float>(0.86, 0.86, 0.89)

        // The color ground paints itself in like watercolor wherever the wash says so (see setWash);
        // the gray ground underneath shows everywhere else.
        let washNoise = colored ? artImage("wash-noise").map { SKTexture(image: $0) } : nil
        washNoise?.filteringMode = .linear
        let shader = SKShader(source: washNoise != nil ? washSource : source)
        shader.uniforms = [
            SKUniform(name: "u_road", texture: road),
            SKUniform(name: "u_ground", texture: ground),
            SKUniform(name: "u_x0", float: Float(rect.minX)),
            SKUniform(name: "u_y0", float: Float(rect.minY)),
            SKUniform(name: "u_w", float: Float(rect.width)),
            SKUniform(name: "u_h", float: Float(rect.height)),
            SKUniform(name: "u_cx", float: Float(centerX)),
            SKUniform(name: "u_horizon", float: Float(horizonY)),
            SKUniform(name: "u_k", float: Float(unitK)),
            SKUniform(name: "u_camH", float: Float(camHeight)),
            SKUniform(name: "u_camBack", float: Float(camBack)),
            SKUniform(name: "u_offset", float: 0),
            SKUniform(name: "u_roadFog", vectorFloat3: roadFog),
            SKUniform(name: "u_groundFog", vectorFloat3: groundFog),
            SKUniform(name: "u_edge", vectorFloat3: edgeColor),
            SKUniform(name: "u_fogNear", float: 16),
            SKUniform(name: "u_fogFar", float: 60)
        ]
        if let washNoise {
            shader.addUniform(SKUniform(name: "u_noise", texture: washNoise))
            shader.addUniform(SKUniform(name: "u_front", float: -20))
            for i in 0..<washSlots {
                shader.addUniform(SKUniform(name: "u_p\(i)", vectorFloat4: SIMD4<Float>(0, -100, 0, 0)))
            }
        }
        sprite.shader = shader
        return sprite
    }

    /// Fog Day pulls the fog in close; normal runs keep it near the horizon.
    static func setFog(_ sprite: SKSpriteNode?, near: Float, far: Float) {
        sprite?.shader?.uniformNamed("u_fogNear")?.floatValue = near
        sprite?.shader?.uniformNamed("u_fogFar")?.floatValue = far
    }

    /// The average color of an image, for the fog.
    private static func averageColor(_ image: UIImage) -> SIMD3<Float> {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        var result = SIMD3<Float>(0.6, 0.6, 0.6)
        guard let cg = small.cgImage else { return result }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            result = SIMD3<Float>(Float(buffer[0]) / 255, Float(buffer[1]) / 255, Float(buffer[2]) / 255)
        }
        return result
    }

    /// Scrolls the textures. Wrapped at 12 world units (a multiple of both tile sizes) to keep precision.
    static func setDistance(_ sprite: SKSpriteNode?, _ distance: Double) {
        sprite?.shader?.uniformNamed("u_offset")?.floatValue = Float(distance.truncatingRemainder(dividingBy: 12.0))
    }

    /// How many color blooms the shader can paint at once (the nearest ones win).
    static let washSlots = 32

    /// True when this sprite paints with the watercolor wash.
    static func hasWash(_ sprite: SKSpriteNode?) -> Bool {
        sprite?.shader?.uniformNamed("u_p0") != nil
    }

    /// Sets the blooms to paint, each (x, z, radius, 0) in world units relative to the camera,
    /// nearest first; and `front`, the z up to which the whole world is washed in (for the finish).
    static func setWash(_ sprite: SKSpriteNode?, blooms: [SIMD4<Float>], front: Float) {
        guard let shader = sprite?.shader else { return }
        if washUniforms.isEmpty || washShader !== shader {
            washShader = shader
            washUniforms = (0..<washSlots).compactMap { shader.uniformNamed("u_p\($0)") }
            washFront = shader.uniformNamed("u_front")
        }
        for (i, uniform) in washUniforms.enumerated() {
            uniform.vectorFloat4Value = i < blooms.count ? blooms[i] : SIMD4<Float>(0, -100, 0, 0)
        }
        washFront?.floatValue = front
    }

    private static var washShader: SKShader?
    private static var washUniforms: [SKUniform] = []
    private static var washFront: SKUniform?

    /// The ground shader plus the watercolor wash. Each bloom is a soft circle on the ground;
    /// a paper-grain noise that moves with the ground roughens the edge so it bleeds like paint,
    /// and a faint darker rim marks where the wash is still wet.
    private static let washSource: String = {
        let blooms = (0..<washSlots).map { "    wash = max(wash, bloom(u_p\($0), x, z));" }.joined(separator: "\n")
        return """
        float bloom(vec4 p, float x, float z) {
            if (p.z <= 0.001) { return 0.0; }
            float d = length(vec2(x - p.x, z - p.y)) / p.z;
            return clamp((1.0 - d) / 0.5, 0.0, 1.0);
        }

        void main() {
            float px = u_x0 + v_tex_coord.x * u_w;
            float py = u_y0 + v_tex_coord.y * u_h;
            float below = max(u_horizon - py, 0.5);
            float depth = u_camH * u_k / below;
            float z = depth - u_camBack;
            float x = (px - u_cx) * depth / u_k;
            float ax = abs(x);
            float onRoad = step(ax, 1.5);

            vec2 roadUV = fract(vec2((x + 1.5) / 3.0, (z + u_offset) / 3.0));
            vec2 groundUV = fract(vec2(x / 4.0, (z + u_offset) / 4.0));
            vec3 roadColor = texture2D(u_road, roadUV).rgb;
            vec3 groundColor = texture2D(u_ground, groundUV).rgb;
            vec3 color = mix(groundColor, roadColor, onRoad);

            float edge = 1.0 - smoothstep(0.02, 0.05, abs(ax - 1.5));
            color = mix(color, u_edge, edge * 0.85);

            vec3 fogColor = mix(u_groundFog, u_roadFog, onRoad);
            float fog = smoothstep(u_fogNear, u_fogFar, depth);
            color = mix(color, fogColor, fog);

            float wash = clamp((u_front - z) / 8.0, 0.0, 1.0);
        \(blooms)
            float grain = texture2D(u_noise, fract(vec2(x / 4.0, (z + u_offset) / 4.0))).r;
            float paint = smoothstep(0.32, 0.68, wash + (grain - 0.5) * 0.55);
            float rim = paint * (1.0 - paint) * 4.0;
            color *= 1.0 - rim * 0.1;
            gl_FragColor = vec4(color, 1.0) * paint;
        }
        """
    }()

    private static let source = """
    void main() {
        float px = u_x0 + v_tex_coord.x * u_w;
        float py = u_y0 + v_tex_coord.y * u_h;
        float below = max(u_horizon - py, 0.5);
        float depth = u_camH * u_k / below;
        float z = depth - u_camBack;
        float x = (px - u_cx) * depth / u_k;
        float ax = abs(x);
        float onRoad = step(ax, 1.5);

        vec2 roadUV = fract(vec2((x + 1.5) / 3.0, (z + u_offset) / 3.0));
        vec2 groundUV = fract(vec2(x / 4.0, (z + u_offset) / 4.0));
        vec3 roadColor = texture2D(u_road, roadUV).rgb;
        vec3 groundColor = texture2D(u_ground, groundUV).rgb;
        vec3 color = mix(groundColor, roadColor, onRoad);

        // A soft paper edge along both sides of the road.
        float edge = 1.0 - smoothstep(0.02, 0.05, abs(ax - 1.5));
        color = mix(color, u_edge, edge * 0.85);

        // Fade into flat fog toward the horizon.
        vec3 fogColor = mix(u_groundFog, u_roadFog, onRoad);
        float fog = smoothstep(u_fogNear, u_fogFar, depth);
        color = mix(color, fogColor, fog);

        gl_FragColor = vec4(color, 1.0);
    }
    """
}
