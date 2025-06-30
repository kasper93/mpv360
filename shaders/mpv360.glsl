//!PARAM fov
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 3.1415926535897932
2.1

//!PARAM yaw
//!TYPE float
//!MINIMUM -6.2831853071795864
//!MAXIMUM 6.2831853071795864
0.0

//!PARAM pitch
//!TYPE float
//!MINIMUM -3.1415926535897932
//!MAXIMUM 3.1415926535897932
0.0

//!PARAM roll
//!TYPE float
//!MINIMUM -3.1415926535897932
//!MAXIMUM 3.1415926535897932
0.0

//!HOOK MAINPRESUB
//!BIND HOOKED

#define M_PI 3.1415926535897932

mat3 rot_yaw = mat3(
    cos(yaw), 0.0, -sin(yaw),
    0.0, 1.0, 0.0,
    sin(yaw), 0.0, cos(yaw)
);

mat3 rot_pitch = mat3(
    1.0, 0.0, 0.0,
    0.0, cos(pitch), sin(pitch),
    0.0, -sin(pitch), cos(pitch)
);

mat3 rot_roll = mat3(
    cos(roll), sin(roll), 0.0,
    -sin(roll), cos(roll), 0.0,
    0.0, 0.0, 1.0
);

vec4 hook() {
    vec2 uv = HOOKED_pos * 2.0 - 1.0;

    float aspect = target_size.x / target_size.y;
    float fov_scale_x = tan(fov * 0.5);
    float fov_scale_y = fov_scale_x / aspect;

    vec2 scaled_uv = uv * vec2(fov_scale_x, fov_scale_y);
    vec3 view_dir = normalize(vec3(scaled_uv, 1.0));
    vec3 dir = rot_yaw * rot_pitch * rot_roll * view_dir;
    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);

    return HOOKED_tex(vec2((lon + M_PI) / (2.0 * M_PI), (lat + M_PI * 0.5) / M_PI));
}
