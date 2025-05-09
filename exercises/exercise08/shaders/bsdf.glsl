
uniform samplerCube EnvironmentTexture;
uniform float EnvironmentMaxLod;

struct SurfaceData
{
	vec3 normal;
	vec3 albedo;
	float ambientOcclusion;
	float roughness;
	// float metalness;
	float refractionIndex;
};

// Constant value for PI
const float Pi = 3.1416f;

// Constant value for 1 / PI
const float invPi = 0.31831f;

// Get the surface albedo
vec3 GetAlbedo(SurfaceData data)
{
	return data.albedo; // return mix(data.albedo, vec3(0.0f), data.metalness);
}

// Get the surface reflectance
vec3 GetReflectance(SurfaceData data)
{
	// We use a fixed value for dielectric, with a typical value for these materials (4%)
	// return mix(vec3(0.04f), data.albedo, data.metalness); // when incl metalness
	return vec3(0.04f);
}

float GetCosThetaTr(float cosThetaIn, float eta)
{
	float sinThetaIn2 = sqrt(max(0.0f, 1.0f - cosThetaIn )); // (sin theta)^2 + (cos theta)^2 = 1, (sin theta)^2 = 1 - (cos theta)^2
	float sinThetaTr = sinThetaIn2 * eta; // Snell's Law // study ratio
	float cosThetaTr = sqrt(max(0.0f, 1.0f - sinThetaTr * sinThetaTr )); 
	return cosThetaTr;
}

float FresnelBSDF(float cosThetaIn, float etaIn, float etaTr)
{
	// cosThetaIn = clamp(cosThetaIn, -1, 1);

	bool isEntering = cosThetaIn > 0;
	float etaI = etaIn, etaT = etaTr;
	if (!isEntering)
	{
		float etaI = etaTr, etaT = etaIn;
		cosThetaIn = abs(cosThetaIn); // why? or -cosThetaIn?
	}
	
	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaT/etaI);
	if(cosThetaTr <= 0.0f) return 1.0f; // incase of total internal reflection -> no transmission

	float f90 = ((etaT * cosThetaIn) - (etaI * cosThetaTr)) /
            	((etaT * cosThetaIn) + (etaI * cosThetaTr));
	float f0 = ((etaI * cosThetaIn) - (etaT * cosThetaTr)) /
                ((etaI * cosThetaIn) + (etaT * cosThetaTr));
	return (f0 * f0 + f90 * f90) / 2.0f ;
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
// vec3 ComputeDiffuseLighting(SurfaceData data, vec3 lightDir)
// {
// 	// Implement the lambertian equation for diffuse
// 	return GetAlbedo(data) * invPi;
// }

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

vec3 CombineLighting(vec3 specular, SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	// Compute the Fresnel term between the half direction and the view direction
	vec3 halfDir = normalize(viewDir + lightDir);
	vec3 fresnel = FresnelSchlick(GetReflectance(data), viewDir, halfDir);

	// Linearly interpolate between the diffuse and specular term, using the fresnel value
	vec3 lighting = mix(vec3(0), specular, fresnel);

	// Move the incidence factor to affect the combined light value
	float incidence = ClampedDot(data.normal, lightDir);
	lighting *= incidence;

	return lighting;
}

/**
BSDF (scales attenuation * lightcolor)
*/
vec3 ComputeSpecularReflection(SurfaceData data, vec3 viewDir)
{
	vec3 inDir = -viewDir; // - viewDir, because viewDir should be point in not out (!)
	vec3 reflectionDir = reflect(inDir, data.normal);

	vec3 specularReflection = vec3(1.0f) ; //* GeometrySmith(data.normal, reflectionDir, viewDir, data.roughness) ;

	// Sample the environment map using the reflection vector, at a specific LOD level
	float lodLevel = pow(data.roughness, 0.25f);
	specularReflection *= SampleEnvironment(reflectionDir, lodLevel);
	
	return specularReflection; // vec3(1.0,0,0);
}

vec3 ComputeSpecularTransmission(SurfaceData data, vec3 lightDir, vec3 viewDir, vec3 inDir)
{
	// vec3 inDir = - viewDir;
	float etaRatio = data.refractionIndex / 1.0f ;

	float cosThetaIn = clamp(dot(data.normal, inDir), -1, 1);
	bool isEntering = cosThetaIn > 0;

	if (!isEntering)
	{
		etaRatio = 1 / etaRatio;
		cosThetaIn = abs(cosThetaIn); // why?
	}
	
	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaRatio);
	if(cosThetaTr <= 0.0f) return vec3(0.0f); // total internal reflection
	// if (isEntering) cosThetaTr *= -1; // why?
	
	vec3 transmissionDir = refract( inDir, data.normal, etaRatio);
	float lodLevel = pow(data.roughness, 0.6f);
	vec3 specularTransmission = SampleEnvironment(transmissionDir, lodLevel);
	
	return specularTransmission; // + vec3(0.0f, 0.5 ,0);
}

vec3 ComputeScatteredLighting(vec3 reflection, vec3 transmission, SurfaceData data, vec3 viewDir)
{
	vec3 inDir = - viewDir;
	float cosThetaIn = dot(inDir, data.normal);

	float fresnel = FresnelBSDF(cosThetaIn, 1.0f, data.refractionIndex);
	vec3 lighting = mix(transmission, reflection, fresnel);
	lighting *= data.ambientOcclusion;

	// // Move the incidence factor to affect the combined light value
	// float incidence = ClampedDot(data.normal, lightDir);
	// lighting *= incidence;

	return lighting;
}
