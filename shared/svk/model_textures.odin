package svk

Model_Texture_Type :: enum {
	base_color,
	pbr_metallic_roughness,
	pbr_specular_glossiness,
	clearcoat,
	transmission,
	volume,
	ior,
	specular,
	sheen,
	emissive_strength,
	iridescence,
	anisotropy,
	dispersion,
}

Alpha_Mode :: enum {
	opaque,
	mask,
	blend,
}

Model_Texture_Data_Scalar :: enum {
	metallic_factor,
	roughness_factor,
	glossiness_factor,
	clearcoat_factor,
	clearcoat_roughness_factor,
	transmission_factor,
	thickness_factor,
	attenuation_distance,
	ior,
	specular_factor,
	sheen_roughness_factor,
	emissive_strength,
	iridescence_factor,
	iridescence_ior,
	iridescence_thickness_min,
	iridescence_thickness_max,
	anisotropy_strength,
	anisotropy_rotation,
	dispersion,
}

Model_Texture_Data_Vec3 :: enum {
	specular_factor,
	attenuation_color,
	specular_color_factor,
	sheen_color_factor,
}

Model_Texture_Data_Vec4 :: enum {
	base_color_factor,
}

