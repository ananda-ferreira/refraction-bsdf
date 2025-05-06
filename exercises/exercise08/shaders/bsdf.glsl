
uniform samplerCube EnvironmentTexture;
uniform float EnvironmentMaxLod;

// data of point aka fragment
// should refractionIndex be here? it's alwasy the same
// remove metalness
struct SurfaceData
{
	vec3 normal;
	vec3 albedo;
	float ambientOcclusion;
	float roughness;
	float metalness;
	float refractionIndex;
};

// Constant value for PI
const float Pi = 3.1416f;

// Constant value for 1 / PI
const float invPi = 0.31831f;

// Get the surface albedo
vec3 GetAlbedo(SurfaceData data)
{
	// return mix(data.albedo, vec3(0.0f), data.metalness);
	return data.albedo; 
}

// Get the surface reflectance
vec3 GetReflectance(SurfaceData data)
{
	// We use a fixed value for dielectric, with a typical value for these materials (4%)
	// 4% applies to glass too. instead of albedo, rgba?
	// return mix(vec3(0.04f), data.albedo, data.metalness); // when incl metalness
	return vec3(0.04f);
}

/*
Params:
etaI: refraction index of incident material = air
etaT: refraction index of transmission material = glass
*/
float GetCosThetaTr(float cosThetaIn, float etaI, float etaT)
{
	float sinThetaIn = sqrt(max(0.0f, 1.0f - cosThetaIn)); // why max?
	float sinThetaTr = etaI / etaT * sinThetaIn ; // Snell's Law
	float cosThetaTr = sqrt(max(0.0f, 1.0f - sinThetaTr * sinThetaTr)); // why sqrt??
	return cosThetaTr;
}

// determins if light entering or exiting (coming from behind) material 
// cosTheta should be clamped to -1,1, why though
bool IsEntering(float cosThetaIn)
{
	return cosThetaIn > 0;
}

// Fresnel with eta for transmission
float FresnelDielectric(float cosThetaIn, float etaI, float etaT)
{
	cosThetaIn = clamp(cosThetaIn, -1, 1);

	if (!IsEntering(cosThetaIn))
	{
		// swap(etaI, etaT);
		etaI = etaT, etaT = 1.0f;
		cosThetaIn = abs(cosThetaIn); // why?
	}
	
	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaI, etaT);
	if(cosThetaTr <= 0.0f) return 1.0f; // incase of total internal reflection, no transmission

	float f90 = ((etaT * cosThetaIn) - (etaI * cosThetaTr)) /
            	((etaT * cosThetaIn) + (etaI * cosThetaTr));
	float f0 = ((etaI * cosThetaIn) - (etaT * cosThetaTr)) /
                ((etaI * cosThetaIn) + (etaT * cosThetaTr));
	return (f0 * f0 + f90 * f90) / 2.0f;
}

// Schlick simplification of the Fresnel term
vec3 FresnelSchlick(vec3 f0, vec3 viewDir, vec3 halfDir)
{
	vec3 f90 = vec3(1.0f); // for dielectrics only!
	return f0 + (f90 - f0) * pow(1.0f - ClampedDot(viewDir, halfDir), 5.0f);
}

// GGX equation for distribution function
// also for bsdf
float DistributionGGX(vec3 normal, vec3 halfDir, float roughness)
{
	float roughness2 = roughness * roughness;

	float dotNH = ClampedDot(normal, halfDir);

	float expr = dotNH * dotNH * (roughness2 - 1.0) + 1.0;

	return roughness2 / (Pi * expr * expr);
}

// Geometry term in one direction, for GGX equation
float GeometrySchlickGGX(float cosAngle, float roughness)
{
	float roughness2 = roughness * roughness;

	return (2 * cosAngle) / (cosAngle + sqrt(roughness2 + (1 - roughness2) * cosAngle * cosAngle));
}

// Geometry term in both directions, following Smith simplification, that divides it in the product of both directions
float GeometrySmith(vec3 normal, vec3 inDir, vec3 outDir, float roughness)
{
	// Occlusion in input direction (shadowing)
	float ggxIn = GeometrySchlickGGX(ClampedDot(normal, inDir), roughness);

	// Occlusion in output direction (masking)
	float ggxOut = GeometrySchlickGGX(ClampedDot(normal, outDir), roughness);

	// Total occlusion is a product of 
	return ggxIn * ggxOut;
}

// Sample the EnvironmentTexture cubemap
// lodLevel is a value between 0 and 1 to select from the highest to the lowest mipmap
vec3 SampleEnvironment(vec3 direction, float lodLevel)
{
	// Flip the Z direction, because the cubemap is left-handed
	direction.z *= -1;

	// Sample the specified mip-level
	return textureLod(EnvironmentTexture, direction, lodLevel * EnvironmentMaxLod).rgb;
}

/**
Indirect Lighting (added to Lighting <+ atttenuation * lightcolor)
*/

vec3 ComputeDiffuseIndirectLighting(SurfaceData data)
{
	// Sample the environment map at its max LOD level and multiply with the albedo
	vec3 envSample = vec3(1);
	// envSample = SampleEnvironment(data.normal, 1.0f);
	return envSample * GetAlbedo(data);
}

vec3 ComputeSpecularIndirectLighting(SurfaceData data, vec3 viewDir)
{
	// Compute the reflection vector with the viewDir and the normal
	vec3 reflectionDir = reflect(-viewDir, data.normal);
	vec3 specularLighting = vec3(1.0f) * GeometrySmith(data.normal, reflectionDir, viewDir, data.roughness);

	// Add a geometry term to the indirect specular
	// Sample the environment map using the reflection vector, at a specific LOD level
	float lodLevel = pow(data.roughness, 0.25f);
	specularLighting *= SampleEnvironment(reflectionDir, lodLevel);

	return specularLighting;
}

vec3 CombineIndirectLighting(vec3 diffuse, vec3 specular, SurfaceData data, vec3 viewDir)
{
	// Compute the Fresnel term between the normal and the view direction
	vec3 fresnel = FresnelSchlick(GetReflectance(data), viewDir, data.normal);

	// Linearly interpolate between the diffuse and specular term, using the fresnel value
	return mix(diffuse, specular, fresnel) * data.ambientOcclusion;
}

/**
Lighting
*/
vec3 ComputeDiffuseLighting(SurfaceData data, vec3 lightDir)
{
	// Implement the lambertian equation for diffuse
	return GetAlbedo(data) * invPi;
}

vec3 ComputeSpecularLighting(SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	// Implement the Cook-Torrance equation using the D (distribution) and G (geometry) terms
	vec3 halfDir = normalize(lightDir + viewDir);

	float D = DistributionGGX(data.normal, halfDir, data.roughness);
	float G = GeometrySmith(data.normal, lightDir, viewDir, data.roughness);

	float cosThetaIn = ClampedDot(data.normal, lightDir);
	float cosThetaO = ClampedDot(data.normal, viewDir);

	return vec3((D * G) / (4.0f * cosThetaO * cosThetaIn + 0.00001f));
}

vec3 CombineLighting(vec3 diffuse, vec3 specular, SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	// Compute the Fresnel term between the half direction and the view direction
	vec3 halfDir = normalize(viewDir + lightDir);
	vec3 fresnel = FresnelSchlick(GetReflectance(data), viewDir, halfDir);

	// Linearly interpolate between the diffuse and specular term, using the fresnel value
	vec3 lighting = mix(diffuse, specular, fresnel);

	// Move the incidence factor to affect the combined light value
	float incidence = ClampedDot(data.normal, lightDir);
	lighting *= incidence;

	return lighting;
}

/**
BSDF (scales attenuation * lightcolor)
*/
vec3 ComputeSpecularReflection(SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	// implement cook torrance with DG 
	vec3 specularReflection = ComputeSpecularLighting(data, lightDir, viewDir);

	// Compute the reflection vector with the viewDir and the normal
	// Sample the environment map using the reflection vector, at a specific LOD level
	// - viewDir, because viewDir should be point in not out (!)
	vec3 reflectionDir = reflect(- viewDir, data.normal);
	float lodLevel = pow(data.roughness, 0.25f);
	specularReflection *= SampleEnvironment(reflectionDir, lodLevel);
	
	return specularReflection;
}

vec3 ComputeSpecularTransmission(SurfaceData data, vec3 lightDir)
{
	float cosThetaIn = clamp(dot(data.normal, lightDir), -1, 1);
	float etaI = 1.0f, etaT = data.refractionIndex;

	if (!IsEntering(cosThetaIn))
	{
		etaI = etaT, etaT = 1.0f;
		cosThetaIn = abs(cosThetaIn); // why?
	}
	
	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaI, etaT);
	if(cosThetaTr <= 0.0f) return vec3(0.0f); // total internal reflection
	// if (entering) cos_thetaT *= -1; // why?

	float etaEff = etaI / etaT;
	// vec3 transmissionDir = vec3(etaEff * -wo.x, etaEff * -wo.y, cos_thetaT);
	vec3 transmissionDir = refract(-lightDir, data.normal, etaEff);
	float lodLevel = pow(data.roughness, 0.25f);
	vec3 specularLighting = SampleEnvironment(transmissionDir, lodLevel);

	return specularLighting;
}

vec3 ComputeScatteredLighting(vec3 reflection, vec3 transmission, SurfaceData data, vec3 lightDir)
{
	float cosThetaIn = dot(lightDir, data.normal);

	float fresnel = FresnelDielectric(cosThetaIn, 1.0f, data.refractionIndex);

	// interpolate, if fresnel = 1 there is only reflection, if fresnel = 0 there is only transmission
	vec3 lighting = mix(transmission, reflection, fresnel);

	lighting *= data.ambientOcclusion;

	// // // what is this?
	// // Move the incidence factor to affect the combined light value
	// float incidence = ClampedDot(data.normal, lightDir);
	// lighting *= incidence;

	return lighting;
}
