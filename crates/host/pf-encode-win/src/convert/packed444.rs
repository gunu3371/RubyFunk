use super::*;
use pf_packed444::Geometry;

/// Full-resolution RGB conversion and v1 packing, before any chroma filter.
pub struct Packed444Converter {
    vs: ID3D11VertexShader,
    y: ID3D11PixelShader,
    uv: ID3D11PixelShader,
    layout: ID3D11Buffer,
    geometry: Geometry,
}

impl Packed444Converter {
    pub fn new(
        device: &ID3D11Device,
        geometry: Geometry,
        depth: u8,
        hdr: bool,
        fp16: bool,
        full_range: bool,
    ) -> Result<Self> {
        anyhow::ensure!(
            matches!(depth, 8 | 10) && (!hdr || depth == 10),
            "packed video depth"
        );
        let curve = if hdr { CURVE_PQ2020 } else { CURVE_SRGB709 };
        let curve = if fp16 {
            format!("{curve}\nfloat3 encode_rgb(float3 v) {{ return encode_scrgb(v); }}\n")
        } else {
            "float3 encode_rgb(float3 v) { return saturate(v); }\n".to_string()
        };
        let max = if depth == 8 { 255.0 } else { 1023.0 };
        let shift = if depth == 8 { 1.0 } else { 4.0 };
        let (y_min, y_scale, c_scale) = if full_range {
            (0.0, max, max)
        } else {
            (16.0 * shift, 219.0 * shift, 224.0 * shift)
        };
        let (kr, kb) = if hdr {
            (0.2627, 0.0593)
        } else {
            (0.2126, 0.0722)
        };
        let store_scale = if depth == 8 {
            1.0 / 255.0
        } else {
            64.0 / 65535.0
        };
        let src = format!("{curve}\nstatic const float kr={kr}, kb={kb}, maximum={max}, \
            y_min={y_min}, y_scale={y_scale}, c_mid={}, c_scale={c_scale}, store_scale={store_scale};\n{}",
            128.0 * shift, include_str!("packed444.hlsl"));
        let (w, h) = geometry.source();
        let (pw, ph) = geometry.padded();
        let dimensions = [w, h, pw, ph];
        let desc = D3D11_BUFFER_DESC {
            ByteWidth: 16,
            Usage: D3D11_USAGE_IMMUTABLE,
            BindFlags: D3D11_BIND_CONSTANT_BUFFER.0 as u32,
            ..Default::default()
        };
        let data = D3D11_SUBRESOURCE_DATA {
            pSysMem: dimensions.as_ptr().cast(),
            ..Default::default()
        };
        let (mut vs, mut y, mut uv, mut layout) = (None, None, None, None);
        // SAFETY: bytecode and constant data live through each synchronous device call.
        // All interfaces belong to this device and each out-param is checked.
        unsafe {
            device.CreateVertexShader(
                &compile_shader(HDR_VS, s!("main"), s!("vs_5_0"))?,
                None,
                Some(&mut vs),
            )?;
            device.CreatePixelShader(
                &compile_shader(&src, s!("packed_y"), s!("ps_5_0"))?,
                None,
                Some(&mut y),
            )?;
            device.CreatePixelShader(
                &compile_shader(&src, s!("packed_uv"), s!("ps_5_0"))?,
                None,
                Some(&mut uv),
            )?;
            device.CreateBuffer(&desc, Some(&data), Some(&mut layout))?;
        }
        Ok(Self {
            vs: vs.context("packed vertex shader")?,
            y: y.context("packed luma shader")?,
            uv: uv.context("packed chroma shader")?,
            layout: layout.context("packed layout buffer")?,
            geometry,
        })
    }

    pub fn convert(
        &self,
        ctx: &ID3D11DeviceContext,
        source: &ID3D11ShaderResourceView,
        y: &ID3D11RenderTargetView,
        uv: &ID3D11RenderTargetView,
    ) {
        let (w, h) = self.geometry.coded();
        // SAFETY: the caller serializes this context; views and shaders belong to its device.
        // Both passes finish issuing before resources are unbound for the encoder.
        unsafe {
            ctx.OMSetBlendState(None, None, u32::MAX);
            ctx.IASetInputLayout(None);
            ctx.IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            ctx.VSSetShader(&self.vs, None);
            ctx.PSSetShaderResources(0, Some(&[Some(source.clone())]));
            ctx.PSSetConstantBuffers(0, Some(&[Some(self.layout.clone())]));
            for (shader, target, scale) in [(&self.y, y, 1), (&self.uv, uv, 2)] {
                ctx.RSSetViewports(Some(&[D3D11_VIEWPORT {
                    Width: (w / scale) as f32,
                    Height: (h / scale) as f32,
                    MaxDepth: 1.0,
                    ..Default::default()
                }]));
                ctx.OMSetRenderTargets(Some(&[Some(target.clone())]), None);
                ctx.PSSetShader(shader, None);
                ctx.Draw(3, 0);
            }
            ctx.OMSetRenderTargets(Some(&[None]), None);
            ctx.PSSetShaderResources(0, Some(&[None]));
            ctx.PSSetConstantBuffers(0, Some(&[None]));
        }
    }
}
