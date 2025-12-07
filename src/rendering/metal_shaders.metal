#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct RasterizerData {
    float4 position [[position]];
    float2 texCoord;
};

vertex RasterizerData
vertexShader(VertexInput in [[stage_in]])
{
    RasterizerData out;
    
    // Pass position directly (it's already in NDC [-1, 1])
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4
fragmentShader(RasterizerData in [[stage_in]],
               texture2d<float> texture [[texture(0)]])
{
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    // Sample the texture
    float4 color = texture.sample(textureSampler, in.texCoord);
    
    return color;
}
