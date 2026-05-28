struct VertexOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
};

@vertex
fn vs_main(
  @location(0) pos: vec2<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
) -> VertexOut {
  var out: VertexOut;
  out.position = vec4<f32>(pos, 0.0, 1.0);
  out.uv = uv;
  out.color = color;
  return out;
}

@group(0) @binding(0) var atlasTex: texture_2d<f32>;
@group(0) @binding(1) var atlasSampler: sampler;

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
  let sample = textureSample(atlasTex, atlasSampler, in.uv);
  let alpha = sample.a * in.color.a;
  return vec4<f32>(in.color.rgb * alpha, alpha);
}
