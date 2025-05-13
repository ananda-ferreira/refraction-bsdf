//Inputs
in vec3 WorldPosition;
in vec3 WorldNormal;
in vec3 WorldTangent;
in vec3 WorldBitangent;
in vec2 TexCoord;

//Outputs
out vec4 FragColor;

//Uniforms
uniform vec3 Color; // 1.0
uniform sampler2D NormalTexture;
uniform sampler2D ColorTexture; // not used
uniform sampler2D SpecularTexture; // not sued

uniform vec3 CameraPosition;

// BSDF
uniform float RefractionIndex;
uniform float Roughness;
uniform vec3 DebugColors;
uniform float ReflectionIntensity;
uniform float RefractionIntensity;

void main()
{
	SurfaceData data;
	data.normal = SampleNormalMap(NormalTexture, TexCoord, normalize(WorldNormal), normalize(WorldTangent), normalize(WorldBitangent));
	data.roughness        = Roughness;
	data.refractionIndex  = RefractionIndex;
	data.reflectionRed  = DebugColors.r;
	data.refractionGreen  = DebugColors.g;
	data.reflectionIntensity = ReflectionIntensity;
	data.refractionIntensity = RefractionIntensity;

	vec3 position = WorldPosition;
	vec3 viewDir = GetDirection(position, CameraPosition);
	vec3 color = ComputeLighting(position, data, viewDir, true);
	FragColor = vec4(color.rgb, 1);
}
