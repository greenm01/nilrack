struct VertexIn {
  @location(0) pos: vec2<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
};

struct VertexOut {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
};

@vertex
fn vs_main(in: VertexIn) -> VertexOut {
  var out: VertexOut;
  out.position = vec4<f32>(in.pos, 0.0, 1.0);
  out.uv = in.uv;
  out.color = in.color;
  return out;
}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4<f32> {
  return vec4<f32>(in.color.rgb * in.color.a, in.color.a);
}
