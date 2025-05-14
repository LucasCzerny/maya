{
    "entryPoints" : [
        {
            "name" : "main",
            "mode" : "comp",
            "workgroup_size" : [
                8,
                8,
                1
            ],
            "workgroup_size_is_spec_constant_id" : [
                false,
                false,
                false
            ]
        }
    ],
    "types" : {
        "_8" : {
            "name" : "Ray",
            "members" : [
                {
                    "name" : "origin",
                    "type" : "vec3"
                },
                {
                    "name" : "direction",
                    "type" : "vec3"
                }
            ]
        },
        "_11" : {
            "name" : "Intersection",
            "members" : [
                {
                    "name" : "coords",
                    "type" : "vec2"
                },
                {
                    "name" : "distance",
                    "type" : "float"
                }
            ]
        },
        "_14" : {
            "name" : "Intersection_Result",
            "members" : [
                {
                    "name" : "intersection",
                    "type" : "_11"
                },
                {
                    "name" : "indices",
                    "type" : "uvec3"
                }
            ]
        },
        "_26" : {
            "name" : "Hit_Payload",
            "members" : [
                {
                    "name" : "distance",
                    "type" : "float"
                },
                {
                    "name" : "position",
                    "type" : "vec3"
                },
                {
                    "name" : "normal",
                    "type" : "vec3"
                },
                {
                    "name" : "tangent",
                    "type" : "vec4"
                },
                {
                    "name" : "tex_coords",
                    "type" : "vec2"
                },
                {
                    "name" : "albedo",
                    "type" : "vec3"
                }
            ]
        },
        "_116" : {
            "name" : "Camera",
            "members" : [
                {
                    "name" : "camera_position",
                    "type" : "vec3",
                    "offset" : 0
                },
                {
                    "name" : "camera_forward",
                    "type" : "vec3",
                    "offset" : 16
                },
                {
                    "name" : "camera_right",
                    "type" : "vec3",
                    "offset" : 32
                },
                {
                    "name" : "camera_up",
                    "type" : "vec3",
                    "offset" : 48
                }
            ]
        },
        "_166" : {
            "name" : "Positions",
            "members" : [
                {
                    "name" : "positions",
                    "type" : "vec3",
                    "array" : [
                        0
                    ],
                    "array_size_is_literal" : [
                        true
                    ],
                    "offset" : 0,
                    "array_stride" : 16
                }
            ]
        },
        "_190" : {
            "name" : "Indices",
            "members" : [
                {
                    "name" : "indices",
                    "type" : "uvec3",
                    "array" : [
                        0
                    ],
                    "array_size_is_literal" : [
                        true
                    ],
                    "offset" : 0,
                    "array_stride" : 16
                }
            ]
        },
        "_445" : {
            "name" : "Normals",
            "members" : [
                {
                    "name" : "normals",
                    "type" : "vec3",
                    "array" : [
                        0
                    ],
                    "array_size_is_literal" : [
                        true
                    ],
                    "offset" : 0,
                    "array_stride" : 16
                }
            ]
        },
        "_479" : {
            "name" : "Tangents",
            "members" : [
                {
                    "name" : "tangents",
                    "type" : "vec4",
                    "array" : [
                        0
                    ],
                    "array_size_is_literal" : [
                        true
                    ],
                    "offset" : 0,
                    "array_stride" : 16
                }
            ]
        },
        "_514" : {
            "name" : "Tex_Coords",
            "members" : [
                {
                    "name" : "tex_coords",
                    "type" : "vec2",
                    "array" : [
                        0
                    ],
                    "array_size_is_literal" : [
                        true
                    ],
                    "offset" : 0,
                    "array_stride" : 8
                }
            ]
        }
    },
    "images" : [
        {
            "type" : "image2D",
            "name" : "color_buffer",
            "set" : 0,
            "binding" : 0,
            "format" : "rgba8"
        }
    ],
    "ssbos" : [
        {
            "type" : "_166",
            "name" : "Positions",
            "readonly" : true,
            "block_size" : 0,
            "set" : 1,
            "binding" : 0
        },
        {
            "type" : "_190",
            "name" : "Indices",
            "readonly" : true,
            "block_size" : 0,
            "set" : 1,
            "binding" : 4
        },
        {
            "type" : "_445",
            "name" : "Normals",
            "readonly" : true,
            "block_size" : 0,
            "set" : 1,
            "binding" : 1
        },
        {
            "type" : "_479",
            "name" : "Tangents",
            "readonly" : true,
            "block_size" : 0,
            "set" : 1,
            "binding" : 2
        },
        {
            "type" : "_514",
            "name" : "Tex_Coords",
            "readonly" : true,
            "block_size" : 0,
            "set" : 1,
            "binding" : 3
        }
    ],
    "ubos" : [
        {
            "type" : "_116",
            "name" : "Camera",
            "block_size" : 60,
            "set" : 2,
            "binding" : 0
        }
    ]
}