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
dual_vert_equirectangular
cylindrical
equiangular_cubemap
dual_equiangular_cubemap

//!PARAM eye
//!TYPE ENUM int
left
right
both

//!PARAM fisheye_fov
//!TYPE float
//!MINIMUM 1e-6
//!MAXIMUM 6.2831853071795864
3.1415926535897932

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

bool is_stereo() {
    return input_projection == dual_fisheye ||
           input_projection == dual_half_equirectangular ||
           input_projection == dual_vert_equirectangular ||
           input_projection == dual_equiangular_cubemap;
}

vec2 sample_dual_fisheye(vec3 dir, int source_eye) {
    dir = normalize(dir);
    float theta = acos(dir.z);
    float phi = atan(dir.y, dir.x);

    float r = theta / (fisheye_fov * 0.5);
    if (r > 1.0)
        return vec2(-1000.0);

    vec2 pos = vec2(cos(phi), sin(phi)) * r;
    if (source_eye == left)
        return vec2(0.25 + pos.x * 0.25, 0.5 + pos.y * 0.5);
    return vec2(0.75 + pos.x * 0.25, 0.5 + pos.y * 0.5);
}

vec2 sample_dual_vert_equirectangular(vec3 dir, int source_eye) {
    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);

    float u = (lon + M_PI) / (2.0 * M_PI);
    float v = (lat + M_PI * 0.5) / M_PI;

    v *= 0.5;
    v += (source_eye == left) ? 0.0 : 0.5;
    v = clamp(v, (source_eye == left) ? 0.0 : 0.5, (source_eye == left) ? 0.5 : 1.0);

    return vec2(u, v);
}

vec2 sample_dual_half_equirectangular(vec3 dir, int source_eye) {
    if (dir.z < 0.0)
        return vec2(-1000.0);

    float lon = atan(dir.x, dir.z);
    float lat = asin(dir.y);

    float u = (lon + M_PI * 0.5) / (2.0 * M_PI);
    float v = (lat + M_PI * 0.5) / M_PI;

    u += (source_eye == left) ? 0.0 : 0.5;
    u = clamp(u, (source_eye == left) ? 0.0 : 0.5, (source_eye == left) ? 0.5 : 1.0);

    return vec2(u, v);
}

vec2 sample_half_equirectangular(vec3 dir) {
    if (dir.z < 0.0)
        return vec2(-1000.0);

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

vec2 sample_cylindrical(vec3 dir) {
    float u = (atan(dir.x, dir.z) + M_PI) / (2.0 * M_PI);
    float v = dir.y / length(dir.xz);
    return (v < -1.0 || v > 1.0) ? vec2(-1000.0) : vec2(u, (v + 1.0) * 0.5);
}

/*
 * YouTube Equi-Angular Cubemap (EAC) Projection
 * <https://blog.google/products/google-ar-vr/bringing-pixels-front-and-center-vr-video>
 *
 * This projection maps a 360° video to a cubemap with a 3x2 layout.
 * With Equi-Angular projection. Cubemap faces are arranged in a 3x2 grid,
 * such that the top row contains left to right faces, and the bottom row
 * contains bottom to top faces.
 *
 * Each side that is not connected to another side has a 2-pixel border.
 *
 * LE = Left Eye, RE = Right Eye, CW/CCW = Clockwise/Counter-clockwise
 * ─ and │ are 2px borders. Note that faces are rotated such that there is no
 * border needed between adjacent sides, at least some of them.
 *
 * Single Eye (mono) (3×2):
 * ┌─────────────────────────────────────────┐
 * │    Left          Front         Right    │
 * │                                         │
 * ├─────────────────────────────────────────┤
 * │   Bottom         Back           Top     │
 * │  (90° CW)      (90° CW)      (90° CW)   │
 * └─────────────────────────────────────────┘
 *
 * Stereoscopic is basically the same as the mono layout, but rotated 90° CCW,
 * and stacked side-by-side with the left eye on the left and the right eye on
 * the right.
 *
 * Dual Eye (stereo) (4x3):
 * ┌─────────────┬─────────────┬─────────────┬─────────────┐
 * │    Right    │    Top      │    Right    │    Top      │
 * │  (90° CCW)  │    (LE)     │  (90° CCW)  │    (RE)     │
 * │    (LE)     │             │    (RE)     │             │
 * │             │             │             │             │
 * │    Front    │    Back     │    Front    │    Back     │
 * │  (90° CCW)  │    (LE)     │  (90° CCW)  │    (RE)     │
 * │    (LE)     │             │    (RE)     │             │
 * │             │             │             │             │
 * │    Left     │   Bottom    │    Left     │   Bottom    │
 * │  (90° CCW)  │    (LE)     │  (90° CCW)  │    (RE)     │
 * │    (LE)     │             │    (RE)     │             │
 * └─────────────┴─────────────┴─────────────┴─────────────┘
 */
vec2 sample_equiangular_cubemap(vec3 dir, int source_eye) {
    vec3 abs_dir = abs(dir);
    int face;
    vec3 view;

    if (abs_dir.x >= abs_dir.y && abs_dir.x >= abs_dir.z) {
        face = (dir.x > 0.0) ? 2 : 0;
        view = (dir.x > 0.0) ? vec3(-dir.z, dir.y, dir.x)
                             : vec3( dir.z, dir.y, -dir.x);
    } else if (abs_dir.y >= abs_dir.z) {
        face = (dir.y > 0.0) ? 3 : 5;
        view = (dir.y > 0.0) ? vec3( dir.x, -dir.z, dir.y)
                             : vec3( dir.x,  dir.z, -dir.y);
    } else {
        face = (dir.z > 0.0) ? 1 : 4;
        view = (dir.z > 0.0) ? vec3( dir.x, dir.y, dir.z)
                             : vec3(-dir.x, dir.y, -dir.z);
    }

    // Equi-Angular Projection
    vec2 uv = vec2(atan(view.x, view.z), atan(view.y, view.z)) * (2.0 / M_PI) + 0.5;

    if (face == 3 || face == 5) {
        // Rotate top and bottom faces 90° CCW
        uv = vec2(uv.y, 1.0 - uv.x);
    } else if (face == 4) {
        // Rotate back face 90° CW
        uv = vec2(1.0 - uv.y, uv.x);
    }

    ivec2 grid = ivec2(face % 3, face / 3);
    if (is_stereo()) {
        // Rotate 90° CCW
        grid = ivec2(grid.y, 2 - grid.x);
        uv = vec2(uv.y, 1.0 - uv.x);
        if (source_eye == right)
            grid.x += 2;
    }

    // Non-adjacent sides have a 2px border
    const vec2 border = vec2(2.0) / HOOKED_size;

    vec2 face_size = is_stereo() ?
        vec2(1.0 / 4.0, (1.0 - 2.0 * border.y) / 3.0) :
        vec2((1.0 - 2.0 * border.x) / 3.0, 1.0 / 2.0);

    vec2 uv_start = vec2(grid) * face_size;
    vec2 uv_end = uv_start + face_size;

    uv_start += border;
    uv_end += is_stereo() ? vec2(-border.x, border.y) : vec2(border.x, -border.y);

    return mix(uv_start, uv_end, uv);
}

vec4 render(vec2 uv, int source_eye) {
    float aspect = target_size.x / target_size.y;
    if (source_eye == both && is_stereo())
        aspect *= 0.5;

    float fov_scale_x = tan(fov * 0.5);
    float fov_scale_y = fov_scale_x / aspect;

    vec2 scaled_uv = uv * vec2(fov_scale_x, fov_scale_y);
    vec3 view_dir = normalize(vec3(scaled_uv, 1.0));
    vec3 dir = rot_yaw * rot_pitch * rot_roll * view_dir;

    vec2 coord;
    switch (input_projection) {
    case dual_fisheye:
        coord = sample_dual_fisheye(dir, source_eye);
        break;
    case dual_half_equirectangular:
        coord = sample_dual_half_equirectangular(dir, source_eye);
        break;
    case dual_vert_equirectangular:
        coord = sample_dual_vert_equirectangular(dir, source_eye);
        break;
    case half_equirectangular:
        coord = sample_half_equirectangular(dir);
        break;
    case equirectangular:
        coord = sample_equirectangular(dir);
        break;
    case cylindrical:
        coord = sample_cylindrical(dir);
        break;
    case equiangular_cubemap:
    case dual_equiangular_cubemap:
        coord = sample_equiangular_cubemap(dir, source_eye);
        break;
    }

    if (coord.x < -999.0)
        return vec4(0.0, 0.0, 0.0, 1.0);

    return sample_tex(coord);
}

vec4 hook() {
    vec2 uv = HOOKED_pos;

    if (eye == both && is_stereo()) {
        int source_eye = (uv.x < 0.5) ? left : right;
        if (source_eye == right)
            uv.x -= 0.5;
        uv.x *= 2.0;
        uv = uv * 2.0 - 1.0;
        return render(uv, source_eye);
    }

    return render(uv * 2.0 - 1.0, eye);
}
