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
uniform sampler2D ColorTexture;
uniform sampler2D NormalTexture;
uniform sampler2D SpecularTexture;

uniform vec3 CameraPosition;

// Project specific
uniform float RefractionIndex;

void main()
{
	SurfaceData data;
	data.normal = SampleNormalMap(NormalTexture, TexCoord, normalize(WorldNormal), normalize(WorldTangent), normalize(WorldBitangent));
	data.albedo = Color; 
	// data.albedo = Color * texture(ColorTexture, TexCoord).rgb;
	vec3 arm = texture(SpecularTexture, TexCoord).rgb;
	data.ambientOcclusion = arm.x;
	// data.roughness        = arm.y;
	data.roughness        = 0.1;
	// data.metalness        = arm.z;
	data.refractionIndex  = 1.2;

	vec3 position = WorldPosition;
	vec3 viewDir = GetDirection(position, CameraPosition);
	vec3 inDir = GetDirection(CameraPosition, position);
	vec3 color = ComputeLighting(position, data, viewDir, inDir, true);
	FragColor = vec4(color.rgb, 1);
}
