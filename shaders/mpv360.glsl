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

//!PARAM input_projection
//!TYPE ENUM int
equirectangular
dual_fisheye
dual_half_equirectangular
half_equirectangular

//!PARAM eye
//!TYPE ENUM int
left
right

//!PARAM sampling
//!TYPE ENUM int
linear
mitchell
lanczos

//!HOOK MAINPRESUB
//!BIND HOOKED
//!DESC mpv360 - 360° Video Viewer

#define M_PI 3.1415926535897932

float sinc(float x) {
    if (abs(x) < 1e-6) return 1.0;
    x *= M_PI;
    return sin(x) / x;
}

float weight(float x) {
    if (sampling == mitchell) {
        x = abs(x);
        float b = 1.0 / 3.0, c = 1.0 / 3.0;
        float p0 = (6.0 - 2.0 * b) / 6.0,
              p2 = (-18.0 + 12.0 * b + 6.0 * c) / 6.0,
              p3 = (12.0 - 9.0 * b - 6.0 * c) / 6.0,
              q0 = (8.0 * b + 24.0 * c) / 6.0,
              q1 = (-12.0 * b - 48.0 * c) / 6.0,
              q2 = (6.0 * b + 30.0 * c) / 6.0,
              q3 = (-b - 6.0 * c) / 6.0;

        if (x < 1.0) {
            return p0 + x * x * (p2 + x * p3);
        } else if (x < 2.0) {
            return q0 + x * (q1 + x * (q2 + x * q3));
        }
        return 0.0;
    } else if (sampling == lanczos) {
        if (abs(x) >= 3.0) return 0.0;
        return sinc(x) * sinc(x / 3.0);
    }

    return 0.0;
}

vec4 sample_pt(vec2 coord) {
    vec2 pt_coord = coord * HOOKED_size - 0.5;
    vec2 base_coord = floor(pt_coord);
    vec2 frac_coord = pt_coord - base_coord;

    int kernel_size = (sampling == mitchell) ? 2 : 3;
    int start = -kernel_size + 1;
    int end = kernel_size;

    vec4 result = vec4(0.0);
    float weight_sum = 0.0;

    for (int y = start; y <= end; y++) {
        for (int x = start; x <= end; x++) {
            vec2 sample_coord = (base_coord + vec2(x, y) + 0.5) / HOOKED_size;
            float weight_x = weight(float(x) - frac_coord.x);
            float weight_y = weight(float(y) - frac_coord.y);
            float weight = weight_x * weight_y;

            if (weight != 0.0) {
                result += HOOKED_tex(sample_coord) * weight;
                weight_sum += weight;
            }
        }
    }

    return weight_sum > 0.0 ? result / weight_sum : result;
}

vec4 sample_tex(vec2 coord) {
    if (sampling == linear) {
        return HOOKED_tex(coord);
    } else {
        return sample_pt(coord);
    }
}
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

vec2 sample_dual_fisheye(vec3 dir) {
    if (dir.z < 0.0)
        return vec2(-1.0);

    dir = normalize(dir);
    float theta = acos(abs(dir.z));
    float phi = atan(dir.y, dir.x);

    float r = theta / (M_PI * 0.5);
    if (r > 1.0)
        return vec2(-1.0);

    vec2 pos = vec2(cos(phi), sin(phi)) * r;
    if (eye == left)
        return vec2(0.25 + pos.x * 0.25, 0.5 + pos.y * 0.5);
    return vec2(0.75 + pos.x * 0.25, 0.5 + pos.y * 0.5);
}

vec2 sample_dual_half_equirectangular(vec3 dir) {
    if (dir.z < 0.0)
        return vec2(-1.0);

    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);

    float u = (lon + M_PI * 0.5) / M_PI * 0.5;
    u += (eye == left) ? 0.0 : 0.5;

    float v = (lat + M_PI * 0.5) / M_PI;
    u = clamp(u, (eye == left) ? 0.0 : 0.5, (eye == left) ? 0.5 : 1.0);

    return vec2(u, v);
}

vec2 sample_half_equirectangular(vec3 dir) {
    if (dir.z < 0.0)
        return vec2(-1.0);

    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);

    float u = (lon + M_PI * 0.5) / M_PI;
    float v = (lat + M_PI * 0.5) / M_PI;
    return vec2(u, v);
}

vec2 sample_equirectangular(vec3 dir) {
    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);
    return vec2((lon + M_PI) / (2.0 * M_PI), (lat + M_PI * 0.5) / M_PI);
}

vec4 hook() {
    vec2 uv = HOOKED_pos * 2.0 - 1.0;

    float aspect = target_size.x / target_size.y;
    float fov_scale_x = tan(fov * 0.5);
    float fov_scale_y = fov_scale_x / aspect;

    vec2 scaled_uv = uv * vec2(fov_scale_x, fov_scale_y);
    vec3 view_dir = normalize(vec3(scaled_uv, 1.0));
    vec3 dir = rot_yaw * rot_pitch * rot_roll * view_dir;

    vec2 coord;
    switch (input_projection) {
    case dual_fisheye:
        coord = sample_dual_fisheye(dir);
        break;
    case dual_half_equirectangular:
        coord = sample_dual_half_equirectangular(dir);
        break;
    case half_equirectangular:
        coord = sample_half_equirectangular(dir);
        break;
    case equirectangular:
        coord = sample_equirectangular(dir);
        break;
    }

    if (coord.x < 0.0)
        return vec4(0.0, 0.0, 0.0, 1.0);

    return sample_tex(coord);
}
