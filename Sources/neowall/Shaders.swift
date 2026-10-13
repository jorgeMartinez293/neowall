/// Compiled at launch, which keeps the build free of the Metal toolchain.
/// `Uniforms` must match the Swift struct of the same name in Renderer.swift.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 origin;
    float2 cellSize;
    float2 tileSize;
    float2 viewport;
    uint2 gridSize;
    uint atlasColumns;
    float brightness;
    float vignette;
    float padding0;
    float2 padding1;
    float4 background;
    float4 inks[8];
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]]) {
    float2 corner = float2((vertexID << 1) & 2, vertexID & 2);
    VertexOut out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             texture2d<float> cells [[texture(0)]],
                             texture2d<float> atlas [[texture(1)]]) {
    float2 scaled = (in.position.xy - u.origin) / u.cellSize;
    float2 cell = floor(scaled);
    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= float(u.gridSize.x) || cell.y >= float(u.gridSize.y)) {
        return float4(u.background.rgb * u.background.a, u.background.a);
    }

    float4 data = cells.read(uint2(cell));
    uint glyph = uint(data.r * 255.0 + 0.5);
    uint ink = min(uint(data.g * 255.0 + 0.5), 7u);
    float2 local = (scaled - cell) * u.cellSize;

    float coverage = 0.0;
    if (glyph >= 2u) {
        float2 texel = local - (u.cellSize - u.tileSize) * 0.5;
        if (texel.x >= 0.0 && texel.y >= 0.0 && texel.x < u.tileSize.x && texel.y < u.tileSize.y) {
            uint tile = glyph - 2u;
            uint2 tileOrigin = uint2(tile % u.atlasColumns, tile / u.atlasColumns) * uint2(u.tileSize);
            coverage = atlas.read(tileOrigin + uint2(texel)).r;
        }
    }

    float2 centered = in.position.xy / u.viewport - 0.5;
    float edge = 1.0 - u.vignette * smoothstep(0.35, 0.75, length(centered));
    float amount = saturate(coverage * data.b * u.brightness * edge);
    // Premultiplied: a background alpha of 0 leaves only the ink, for overlays.
    float3 backdrop = u.background.rgb * u.background.a;
    return float4(mix(backdrop, u.inks[ink].rgb, amount), mix(u.background.a, 1.0, amount));
}
"""
