Texture2D<float4> source : register(t0);
cbuffer Layout : register(b0) {
    uint source_width, source_height, padded_width, padded_height;
};

// COLOUR supplies encode_rgb, kr, kb, maximum and the source's code ranges.
float3 codes(uint2 p) {
    p = min(p, uint2(source_width - 1, source_height - 1));
    float3 rgb = encode_rgb(source.Load(int3(p, 0)).rgb);
    float y = dot(rgb, float3(kr, 1.0 - kr - kb, kb));
    float2 c = float2((rgb.b - y) / (2.0 * (1.0 - kb)),
                      (rgb.r - y) / (2.0 * (1.0 - kr)));
    return round(clamp(float3(y_min + y_scale * y, c_mid + c_scale * c), 0.0, maximum));
}
float storage(float code) { return code * store_scale; }

float packed_y(float4 position : SV_POSITION) : SV_TARGET {
    uint2 p = uint2(position.xy);
    if (p.y < padded_height) return storage(codes(p).x);
    bool v = p.x >= padded_width / 2;
    uint2 original = uint2(2 * (p.x % (padded_width / 2)) + 1, p.y - padded_height);
    float3 value = codes(original);
    return storage(v ? value.z : value.y);
}

float2 packed_uv(float4 position : SV_POSITION) : SV_TARGET {
    uint2 p = uint2(position.xy);
    return codes(uint2(2 * p.x, p.y)).yz * store_scale;
}
