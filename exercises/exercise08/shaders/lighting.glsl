
uniform bool LightIndirect;
uniform vec3 LightColor;
uniform vec3 LightPosition;
uniform vec3 LightDirection;
uniform vec4 LightAttenuation;

float ComputeDistanceAttenuation(vec3 position)
{
	// Compute distance attenuation, reading the range from LightAttenuation.x (fade start) and LightAttenuation.y (fade end)
	return smoothstep(LightAttenuation.y, LightAttenuation.x, distance(position, LightPosition));
}

float ComputeAngularAttenuation(vec3 lightDir)
{
	float angle = acos(dot(LightDirection, lightDir));
	vec2 attAngle = LightAttenuation.zw;
	return smoothstep(attAngle.y, attAngle.x, angle);
}

float ComputeAttenuation(vec3 position, vec3 lightDir)
{
	float attenuation = 1.0f;
	if (LightAttenuation.y > 0)
	{
		attenuation *= ComputeDistanceAttenuation(position);
	}
	if (LightAttenuation.w > 0)
	{
		attenuation *= ComputeAngularAttenuation(lightDir);
	}
	return attenuation;
}

vec3 ComputeLightDirection(vec3 position)
{
	return LightAttenuation.y >= 0 ? GetDirection(position, LightPosition) : -LightDirection;
}

// BSDF Light
vec3 ComputeBSDFLight(SurfaceData data, vec3 viewDir)
{
	vec3 reflection = ComputeSpecularReflection(data, viewDir);
	vec3 transmission = ComputeSpecularTransmission(data, viewDir);
	vec3 light = ComputeScatteredLighting(reflection, transmission, data, viewDir);
	return light;
}


// light = brdf ? LightColor = Li() ? see render equation
vec3 ComputeBSDFDirect(SurfaceData data, vec3 viewDir, vec3 position)
{
	vec3 lightDir = ComputeLightDirection(position);

	vec3 specular = ComputeSpecularReflectionDirect(data, lightDir, viewDir);
	vec3 light = ComputeDirect(specular, data, lightDir, viewDir);

	float attenuation = ComputeAttenuation(position, lightDir);
	return light * LightColor * attenuation;
}

// called in pbr.frag
vec3 ComputeLighting(vec3 position, SurfaceData data, vec3 viewDir, bool indirect)
{
	vec3 light = ComputeBSDFDirect(data, viewDir, position);
	
	if (indirect && LightIndirect)
	{	
		light += ComputeBSDFLight(data, viewDir);
	}

	return light;
}

vec3 ComputeLighting(vec3 position, SurfaceData data, vec3 viewDir)
{
	return ComputeLighting(position, data, viewDir, true);
}
