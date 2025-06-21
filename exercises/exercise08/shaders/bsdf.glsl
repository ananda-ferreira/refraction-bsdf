
uniform samplerCube EnvironmentTexture;
uniform float EnvironmentMaxLod;

struct SurfaceData
{
	vec3 normal;
	float roughness;
	float refractionIndex;
	float refractionGreen;
	float reflectionRed;
	float reflectionIntensity;
	float refractionIntensity;
};

// Constant value for PI
const float Pi = 3.1416f;

// Sample the EnvironmentTexture cubemap
// lodLevel is a value between 0 and 1 to select from the highest to the lowest mipmap
vec3 SampleEnvironment(vec3 direction, float lodLevel)
{
	// Flip the Z direction, because the cubemap is left-handed
	direction.z *= -1;

	// Sample the specified mip-level
	return textureLod(EnvironmentTexture, direction, lodLevel * EnvironmentMaxLod).rgb;
}

float GetCosThetaTr(float cosThetaIn, float etaIOverT)
{
	float sinThetaIn = sqrt(max(0.0f, 1.0f - cosThetaIn * cosThetaIn )); // (sin theta)^2 + (cos theta)^2 = 1
	float sinThetaTr = sinThetaIn * etaIOverT; // by Snell's Law 
	float cosThetaTr = sqrt(max(0.0f, 1.0f - sinThetaTr * sinThetaTr )); 
	return cosThetaTr;
}

float FresnelBSDF(float cosThetaIn, float etaIn, float etaTr)
{
	float etaI = etaIn, etaT = etaTr;
	cosThetaIn = clamp(cosThetaIn, -1, 1);

	// // Irrelevant for the current setup
	// bool isEntering = cosThetaIn > 0;
	// if (!isEntering)
	// {
	// 	float etaI = etaTr, etaT = etaIn;
	// 	cosThetaIn = abs(cosThetaIn);
	// }
	
	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaI/etaT);
	if(cosThetaTr <= 0.0f) return 1.0f; // total internal reflection -> no transmission

	float f0 = ((etaT * cosThetaIn) - (etaI * cosThetaTr)) /
            	((etaT * cosThetaIn) + (etaI * cosThetaTr));
	float f90 = ((etaI * cosThetaIn) - (etaT * cosThetaTr)) /
                ((etaI * cosThetaIn) + (etaT * cosThetaTr));
	return (f0 * f0 + f90 * f90) / 2.0f ;
}

// GGX equation for distribution function
float DistributionGGX(vec3 normal, vec3 halfDir, float roughness)
{
	float roughness2 = roughness * roughness;
	float cosThetaH = ClampedDot(normal, halfDir);
	float expr = cosThetaH * cosThetaH * (roughness2 - 1.0) + 1.0; // instead - 1.0 , + (tanThetaH)^2

	return roughness2 / (Pi * expr * expr);
}

// Geometry term in one direction, for GGX equation
float GeometrySchlickGGX(float cosAngle, float roughness)
{
	float roughness2 = roughness * roughness;
	float denom = (cosAngle + sqrt(roughness2 + (1 - roughness2) * cosAngle * cosAngle));

	float tanAngle = sqrt(1.f - cosAngle * cosAngle) / cosAngle;
	float denomBSDF = 1.f + sqrt(1.f + roughness2 * tanAngle * tanAngle);

	return (2 * cosAngle) / denom;
}

// Geometry term in both directions, following Smith simplification, that divides it in the product of both directions
float GeometrySmith(vec3 normal, vec3 inDir, vec3 outDir, float roughness)
{
	// Occlusion in input direction (shadowing)
	float ggxIn = GeometrySchlickGGX(ClampedDot(normal, inDir), roughness);

	// Occlusion in output direction (masking)
	float ggxOut = GeometrySchlickGGX(ClampedDot(normal, outDir), roughness);

	//otal occlusion is a product of 
	return ggxIn * ggxOut;
}
/**
BSDF Direct Lighting
*/

vec3 ComputeSpecularReflectionDirect(SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	vec3 halfDir = normalize(lightDir + viewDir);

	float D = DistributionGGX(data.normal, halfDir, data.roughness);
	float G = GeometrySmith(data.normal, lightDir, viewDir, data.roughness);

	float cosThetaIn = ClampedDot(data.normal, lightDir);
	float cosThetaO = ClampedDot(data.normal, viewDir);

	return vec3((D * G) / (4.0f * cosThetaO * cosThetaIn + 0.00001f));
}

vec3 ComputeDirect(vec3 reflection, SurfaceData data, vec3 lightDir, vec3 viewDir)
{
	// Compute the Fresnel term between the half direction and the view direction
	vec3 halfDir = normalize(viewDir + lightDir);
	float cosThetaIn = ClampedDot(data.normal, lightDir); // maybe halfDir for microfacet

	float fresnelbsdf = FresnelBSDF(cosThetaIn, 1.0f, data.refractionIndex);

	// Linearly interpolate between the diffuse and specular term, using the fresnel value
	vec3 lighting = mix(vec3(0.f), reflection, fresnelbsdf);

	// Move the incidence factor to affect the combined light value
	float incidence = cosThetaIn;
	lighting *= incidence;

	return lighting;
}

/**
BSDF environemnt
*/
vec3 ComputeSpecularReflection(SurfaceData data, vec3 viewDir)
{
	vec3 inDir = -viewDir;
	vec3 reflectionDir = reflect(inDir, data.normal);

	float lodLevel = pow(data.roughness, 0.25f);
	vec3 specularReflection = SampleEnvironment(reflectionDir, lodLevel);

	return (specularReflection + vec3(data.reflectionRed,0,0)) * data.reflectionIntensity;
}

vec3 ComputeSpecularTransmission(SurfaceData data, vec3 viewDir)
{
	float cosThetaIn = clamp(dot(data.normal, viewDir), -1, 1); // viewDir needs to be outgoing, otherwise isEntering falsified 
	float etaIOverT =  1.0f / data.refractionIndex ;

	// // Irrelevant for the current setup
	// bool isEntering = cosThetaIn > 0;
	// if (!isEntering)
	// {
	// 	etaIOverT = 1 / etaIOverT;
	// 	cosThetaIn = abs(cosThetaIn); 
	// }

	float cosThetaTr = GetCosThetaTr(cosThetaIn, etaIOverT);
	if(cosThetaTr <= 0.0f) return vec3(0.f); // total internal reflection

	vec3 inDir = -viewDir;
	etaIOverT = 1/etaIOverT;
	vec3 transmissionDir = etaIOverT * inDir + (etaIOverT * cosThetaIn - cosThetaTr) * data.normal; // *wt = eta * -wi + (eta * cosThetaI - cosThetaT) * Vector3f(n);

	float lodLevel = pow(data.roughness, 0.6f);
	vec3 specularTransmission = SampleEnvironment( transmissionDir, lodLevel);
	
	return (specularTransmission + vec3(0.0f, data.refractionGreen ,0)) * data.refractionIntensity;
}

vec3 ComputeScatteredLighting(vec3 reflection, vec3 transmission, SurfaceData data, vec3 viewDir)
{
	vec3 inDir = viewDir;
	float cosThetaIn = dot(inDir, data.normal);
	float fresnel = FresnelBSDF(cosThetaIn, 1.0f, data.refractionIndex);
	vec3 lighting = mix(transmission, reflection, fresnel);

	return lighting;
}