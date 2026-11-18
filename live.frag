#version 300 es
precision highp float;
precision highp int;
uniform sampler2D scenery;
uniform sampler2D templeMask;
uniform float seconds;
in vec2 uv;
out vec4 color;
const float DETAIL_LOOP_SECONDS = 12.;
const float WILDLIFE_LOOP_SECONDS = 60.;
const float DETAIL_TAU = 6.283185307179586;
const float FISH_ASPECT = 4400.0 / 1884.0;

float detailPhase(float seconds) {
    return DETAIL_TAU * fract(seconds / DETAIL_LOOP_SECONDS);
}

vec2 detailOrbit(float phase) {
    return vec2(cos(phase), sin(phase));
}

uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }

float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}

vec2 quinticFade(vec2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }

float valueNoise(vec2 p) { vec2 i = floor(p), f = quinticFade(fract(p));
    return mix(mix(hash12(i), hash12(i+vec2(1,0)), f.x),
               mix(hash12(i+vec2(0,1)), hash12(i+1.), f.x), f.y); }

float sceneSquare(float x){return x*x;}

vec3 jellyBell(vec2 p, vec2 center, float radius, float phase, float brightness, vec3 rgb) {
    vec2 q = (p - center) * vec2(1.0, .42818) / radius;
    if (abs(q.x) > 2.25 || q.y < -1.0 || q.y > 4.4) return rgb;

    float pulse = sin(phase);
    float tilt = .12 + .13 * sin(phase * .62);
    vec2 bell = mat2(1.0, tilt, -tilt, 1.0) * q;
    bell.x *= 1.0 + .11 * pulse;
    bell.y *= 1.0 - .13 * pulse;
    float crossSection = sqrt(max(0.0, 1.0 - bell.x * bell.x));
    float crown = -.79 * crossSection;
    float bellRim = .24 + .065 * crossSection - .10 * exp(-4.1 * bell.x * bell.x);
    float cap = smoothstep(crown - .023, crown + .054, bell.y)
              * (1.0 - smoothstep(bellRim - .026, bellRim + .043, bell.y))
              * (1.0 - smoothstep(.962, 1.025, abs(bell.x)));
    float upperWall = exp(-29.0 * abs(bell.y - crown)) * crossSection;
    float lowerWall = exp(-29.0 * abs(bell.y - bellRim));
    float underside = exp(-15.0 * abs(bell.y - .045 * crossSection)) * crossSection;
    float facing = clamp(1.0 - bell.x * bell.x - sceneSquare((bell.y + .11) * 1.55), 0.0, 1.0);
    float marbling = valueNoise(vec2(bell.x * 21.0 + phase * .06, bell.y * 23.0));
    float radial = atan(bell.x, max(.22, .53 - bell.y));
    float canals = pow(.5 + .5 * cos(27.0 * radial + 1.5 * marbling), 7.0);
    float gonads = exp(-sceneSquare((bell.x + .055) * 2.7)
                       - 9.6 * abs(bell.y + .19 - .042 * sin(bell.x * 16.0)))
                 * (.50 + .50 * pow(abs(sin(13.0 * bell.x)), 2.0)) * (.61 + .39 * marbling);
    vec3 gel = mix(vec3(.46, .68, .84), vec3(.85, .93, 1.), facing * .66 + upperWall * .28);
    float opacity = .46 + .54 * upperWall + .34 * lowerWall + .14 * underside
                  + .13 * canals * facing + .20 * gonads;
    rgb = mix(rgb, gel, brightness * cap * min(.88, opacity));
    rgb += brightness * cap * (vec3(.12,.15,.18)*(.60+.40*facing) + gonads * vec3(.30, .24, .21)
                            + upperWall * vec3(.16, .20, .23));

    if (q.y > -.08) {
        float h = max(q.y, 0.0);
        float trail = .19 * h + .11 * h * sin(phase * .59 - h * .77);
        float strands = 0.0;
        for (int i = 0; i < 10; i++) {
            float k = float(i);
            float r = hash12(vec2(k, 17.0));
            float root = (k / 9.0 - .5) * 1.45;
            float line = root * exp(-h * (.21 + .13 * r)) + trail
                       + h * (.046 + .045 * r) * sin(h * (2.1 + r) - phase * .74 + 1.9 * k);
            float vein = 1.0 - smoothstep(.009, .034 + .012 * r, abs(q.x - line));
            float lengthFade = 1.0 - smoothstep(.63 + 1.46 * r, 1.10 + 2.91 * r, h);
            float glint = .42 + .58 * pow(.5 + .5 * sin(h * (19.0 + 9.0 * r) - phase + k), 4.0);
            strands = max(strands, vein * lengthFade * glint);
        }
        float armAxis = .078 * sin(h * 8.4 - phase * 1.18) + trail * .75;
        float armWidth = .225 * exp(-h * .71) + .036 * sin(h * 9.5 + phase);
        float arms = exp(-25.0 * abs(abs(q.x - armAxis) - armWidth))
                   * (1.0 - smoothstep(.72, 1.93, h)) * (.21 + .21 * sin(h * 11.0 + .87 * phase));
        float stalk = exp(-10.5 * abs(q.x - armAxis) - 1.58 * h)
                    * (.22 + .10 * sin(h * 16.0 - phase) * sin(h * 16.0 - phase));
        float visibility = brightness * smoothstep(-.08, .16, q.y);
        rgb = mix(rgb, vec3(.72, .83, .94), visibility * (.78 * strands + .64 * arms + stalk));
    }
    return rgb;
}

vec3 ventBubble(vec3 rgb, vec2 q, float light) {
    float distanceToCenter = length(q);
    if (distanceToCenter > 1.15) return rgb;
    float shell = exp(-8.5 * abs(distanceToCenter - .87));
    float upperRim = smoothstep(.03, .88, -q.y + .34 * q.x);
    float lowerRim = smoothstep(.08, .85, q.y - .46 * q.x);
    float body = 1.0 - smoothstep(.68, 1.0, distanceToCenter);
    float highlight = exp(-8.8 * length(q - vec2(-.35, -.60)));
    float reflection = exp(-10.0 * length(q - vec2(.39, .53)));
    rgb *= 1.0 - light * (.16 * body + .12 * shell * (1.0 - upperRim));
    return rgb + light * (shell * (.09 + .68 * upperRim + .23 * lowerRim)
                          + .56 * highlight + .25 * reflection) * vec3(.85, .96, 1.0);
}

float rfHash(vec2 p) {
    vec3 v = fract(vec3(p.xyx) * vec3(.1031, .11369, .13787));
    v += dot(v, v.yzx + 19.19);
    return fract((v.x + v.y) * v.z);
}

float rfNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f*f*(3.0 - 2.0*f);
    return mix(mix(rfHash(i), rfHash(i + vec2(1, 0)), f.x),
               mix(rfHash(i + vec2(0, 1)), rfHash(i + vec2(1, 1)), f.x), f.y);
}

void rfOver(inout vec4 outColor, vec3 rgb, float a) {
    outColor = vec4(mix(outColor.rgb, rgb, a), a + outColor.a*(1.0 - a));
}

vec4 rfFinish(vec4 color) {
    return vec4(color.rgb / max(color.a, .0001), color.a);
}

float rfMask(float d, float a) {
    return 1.0 - smoothstep(-a, a, d);
}

void rfKelpBlade(inout vec4 col, vec2 p, vec2 base, vec2 end, float width,
                 float curve, float seed, float phase, float warm) {
    float u = (p.y-base.y)/(end.y-base.y);
    if (u < 0.0 || u > 1.0) return;
    float arc = sin(3.14159265*u);
    float fold = sin(8.6*u+phase);
    float center = mix(base.x,end.x,u) + arc*(curve+width*.35*fold);
    float taper = 2.12*pow(u,.47)*pow(1.0-u,.91);
    float crossBlade = clamp((p.x-center)/max(width*taper,.00004),-1.35,1.35);
    float side = sign(crossBlade);
    float edge = 1.0 + .16*sin(17.2*u+seed+side) + .10*sin(34.0*u+seed*1.3-side);
    edge += .20*fold + .12*side*cos(u*9.0+seed);
    float a = rfMask(abs(p.x-center)-width*taper*edge,.00046);
    if (a <= .001) return;
    float midrib = exp(-8.0*abs(crossBlade+.06*fold));
    float surface = rfNoise(vec2(2.8*crossBlade+u*3.5,19.0*u+seed));
    float margin = smoothstep(.45,1.1,abs(crossBlade));
    float light = .47 + .31*u + .14*fold*crossBlade + .18*surface;
    light += .12*midrib + .16*margin;
    vec3 tint = mix(vec3(.18,.27,.11),vec3(.72,.53,.13),warm);
    vec3 rgb = tint*light + vec3(.017,.038,.038);
    rfOver(col,rgb,a*clamp(.80+.13*midrib-.18*margin,.50,.93));
}

vec4 fishOver(vec4 background, vec4 foreground) {
    float a = foreground.a + background.a * (1.0 - foreground.a);
    vec3 c = foreground.rgb * foreground.a + background.rgb * background.a * (1.0 - foreground.a);
    return vec4(c / max(a, .00001), a);
}

float fishCross(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

float fishTriangle(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    float orientation = sign(fishCross(e0, c - a));
    return -min(min(orientation * fishCross(e0, p - a) / max(length(e0), .001),
                    orientation * fishCross(e1, p - b) / max(length(e1), .001)),
                    orientation * fishCross(e2, p - c) / max(length(e2), .001))
           + 1e3 * (1.0 - abs(orientation));
}

vec4 fishIndividual(vec2 p, vec2 at, float angle, float size, float depth, float seed, float t) {
    vec2 d = (p - at) * vec2(1.0, 1.0 / FISH_ASPECT);
    if (max(abs(d.x), abs(d.y)) > 1.23 * size + .0018) return vec4(0.0);

    vec2 tangent = vec2(cos(angle), sin(angle));
    vec2 q = vec2(dot(d, tangent), dot(d, vec2(-tangent.y, tangent.x))) / size;
    if (abs(q.y) > .49 || q.x > .98) return vec4(0.0);
    float roll = sin(t * mix(2.7, 4.0, seed) + 9.8 * seed);
    float stroke = t * mix(17.5, 10.9, depth) + 26.1 * seed;
    float tailBeat = sin(stroke);
    float x = clamp((q.x + .74) / 1.54, 0.0, 1.0);
    float rear = smoothstep(.12, .76, -q.x);
    float spine = (.087 * sin(stroke + 2.26 * (q.x + .74)) + .032 * roll) * rear;
    spine += (.021 + .029 * roll) * smoothstep(.17, .80, q.x);
    spine += (.013 + .022 * seed) * sin(4.1 * q.x + seed * 5.3) * (1.0 - rear);

    // Broad shoulders taper to a short curved snout and a flexible, narrow peduncle.
    float width = mix(.149, .210, seed) * mix(.86, 1.06, abs(roll));
    float nose = sqrt(clamp((1.0 - x) * 6.8, 0.0, 1.0));
    float back = width * nose * mix(.13, 1.0, smoothstep(.0, .55, x));
    float belly = width * nose * mix(.11, 1.04, smoothstep(.015, .47, x));
    back *= (1.0 - .23 * smoothstep(.75, 1.0, x)) * (1.0 + .064 * sin(x * 8.8 + stroke * .34));
    belly *= (1.0 - .37 * smoothstep(.63, 1.0, x)) * (1.0 + .15 * roll * sin(x * 6.4 - .52));
    float side = q.y - spine;
    float outline = max(max(-side - back, side - belly), max(-q.x - .74, q.x - .80));

    float tailHinge = .087 * tailBeat + .032 * roll;
    float tailSweep = .14 * sin(stroke - .81) + .045 * roll;
    float tailReach = .082 * roll + .024 * tailBeat;
    vec2 tailPoint = q;
    tailPoint.y -= (tailSweep - tailHinge) * smoothstep(.69, 1.07, -q.x);
    float highLobe = fishTriangle(tailPoint, vec2(-.63, tailHinge - .010),
                                  vec2(-1.11 + tailReach, tailHinge - .151 - .025 * seed), vec2(-.85, tailHinge - .007));
    float lowLobe = fishTriangle(tailPoint, vec2(-.66, tailHinge + .016),
                                 vec2(-.85, tailHinge - .007), vec2(-1.058 + tailReach, tailHinge + .124));
    vec2 local = vec2(q.x, side);
    float dorsal = fishTriangle(local, vec2(-.44, -.063),
                               vec2(-.13 - .077 * seed, -.205 - .055 * seed - .038 * roll), vec2(.16, -.116));
    float pectoral = fishTriangle(local, vec2(.275, .057),
                                 vec2(-.19, .192 + .060 * roll), vec2(.04, .107));
    float anal = fishTriangle(local, vec2(-.60, .035), vec2(-.53, .092), vec2(-.21, .083));

    float blur = clamp((.00056 + .00102 * depth) / size, .016, .105);
    float endBlur = .027 * depth * max(rear, smoothstep(.68, 1.0, x));
    float body = 1.0 - smoothstep(-.75 * blur, blur + endBlur, outline);
    float finBlur = blur + .019 + .023 * abs(tailBeat);
    float tail = 1.0 - smoothstep(-.036, finBlur, min(highLobe, lowLobe));
    float backFin = 1.0 - smoothstep(-.018, finBlur, dorsal);
    float lowerFins = 1.0 - smoothstep(-.019, finBlur, min(pectoral, anal));

    float section = max(side < 0.0 ? back : belly, .025);
    float u = side / section;
    float flank = smoothstep(-.30, .97, u);
    float haze = 1.0 - smoothstep(.21, .81, depth);
    vec3 bodyColor = mix(vec3(.037, .108, .161), vec3(.095, .258, .328), flank);
    bodyColor *= mix(.84, 1.13, seed);
    bodyColor += haze * vec3(.062, .127, .159);
    float bank = smoothstep(-.43, .88, roll + .23 * sin(stroke * .34 + x * 8.0));
    float rimLight = .47 + .53 * smoothstep(-.66, .88, sin(x * mix(10.0, 15.0, seed) + seed * 18.0 + t));
    float rimPath = -.944 + .050 * bank + .023 * sin(x * 17.0 + seed * 11.0);
    float rimWidth = max(section * mix(.122, .182, haze),
                         .00087 / size * smoothstep(.61, .91, x));
    float rimOffset = (side - rimPath * section) / rimWidth;
    float rim = exp(-rimOffset * rimOffset);
    rim *= smoothstep(.14, .48, x) * (1.0 - smoothstep(.82, .994, x));
    vec3 reflected = mix(vec3(.74, .78, .73), vec3(1.00, .81, .65), smoothstep(.19, .76, depth));
    bodyColor += reflected * rim * (.55 + .61 * bank) * rimLight;
    bodyColor += vec3(.070, .106, .110) * bank * exp(-sceneSquare((x - .77) / .19) - sceneSquare((u + .31) / .62));

    float gillHeight = (u - .14) * 1.7;
    float gill = exp(-abs(q.x - .44 + .25 * side) * 27.0 - gillHeight * gillHeight);
    float eye = 1.0 - smoothstep(.016, .031 + blur, length(vec2(q.x - .635, side + .041)));
    bodyColor *= 1.0 - .11 * gill - .21 * eye;
    vec3 finColor = mix(vec3(.066, .133, .181), vec3(.101, .247, .322), smoothstep(-.21, .19, side));
    finColor += haze * vec3(.033, .052, .063);
    finColor += reflected * .10 * bank * backFin;
    float finAlpha = max(tail * mix(.55, .82, abs(roll)), max(backFin * .79, lowerFins * .48));
    return fishOver(vec4(finColor, finAlpha), vec4(bodyColor, body * mix(.90, .99, depth)));
}

vec3 detailOver(vec3 under, vec4 over) {
    return mix(under, over.rgb, clamp(over.a, 0.0, 1.0));
}

vec3 detailMotes(vec3 rgb, vec2 p, float seconds) {
    float age = fract(seconds / DETAIL_LOOP_SECONDS);
    float phase = detailPhase(seconds);
    float illumination = exp(-sceneSquare((p.x - .46) / .50) - 1.6 * p.y);
    for (int plane = 0; plane < 2; ++plane) {
        float depth = float(plane);
        float repeatRows = mix(19.0, 31.0, depth);
        vec2 scale = mix(vec2(466.0, 199.5), vec2(316.0, 135.3), depth);
        vec2 current = mix(vec2(.84, .67), vec2(1.57, .38), depth);
        vec2 position = p * scale + current * detailOrbit(phase + depth * 2.3);
        position.y += repeatRows * age;
        vec2 cell = floor(position);
        vec2 key = vec2(cell.x, mod(cell.y, repeatRows)) + 173.0 * depth;
        float seed = hash12(key + 36.0);
        if (seed < mix(.956, .966, depth)) continue;
        vec2 offset = .45 * (vec2(hash12(key + 197.0), hash12(key + 283.0)) - .5);
        vec2 q = fract(position) - .5 - offset;
        float radius = mix(.18, .20, depth) * (.79 + .21 * hash12(key + 13.0));
        float dotMask = 1.0 - smoothstep(.02, radius, length(q));
        float pulse = .68 + .32 * sin(phase * (depth + 2.0) + 43.4 * seed);
        rgb += vec3(.49, .72, .84) * dotMask * illumination * pulse * mix(.18, .23, depth);
    }
    return rgb;
}

vec3 detailVents(vec3 rgb, vec2 p, float seconds) {
    // Each column is a timed stream of bubbles that rise and dissolve at depth.
    const vec4 vents[6] = vec4[6](
        vec4(.234,.894,.305,-.042), vec4(.880,.894,.155,-.013),
        vec4(.315,.437,.233,-.020), vec4(.510,.355,.172,-.009),
        vec4(.658,.274,.205,.019), vec4(.767,.284,.216,.018)
    );
    float cycle = seconds / DETAIL_LOOP_SECONDS;
    for (int vent = 0; vent < 6; ++vent) {
        vec4 v = vents[vent];
        if (p.y < v.y - v.z - .009 || p.y > v.y + .007 ||
            abs(p.x - v.x) > abs(v.w) + .029) continue;
        for (int bubble = 0; bubble < 20; ++bubble) {
            float slot = float(bubble);
            vec2 key = vec2(slot + 19.1, float(vent) * 8.0);
            float seed = hash12(key);
            float tick = .05 * slot + .042 * seed + .11 * float(vent);
            float age = fract(cycle * (1.0 + float(vent % 2)) + tick);
            float life = smoothstep(.0, .078, age) * (1.0 - smoothstep(.76, 1.0, age));
            float x = v.x + v.w * age + (.009 + .009 * age) * (seed - .5)
                      + .004 * sin(age * 13.0 + 9.0 * seed);
            float radius = mix(.00052, .00156, seed) * mix(.78, 1.12, age);
            vec2 q = (p - vec2(x, v.y - age * v.z)) * vec2(1.0, .42818) / radius;
            rgb = ventBubble(rgb, q, life * (.34 + .44 * seed));
        }
    }
    return rgb;
}

vec3 detailJellies(vec3 rgb, vec2 p, float seconds) {
    const vec3 pods[5] = vec3[5](vec3(.127,.154,.0053), vec3(.355,.137,.0047),
                               vec3(.205,.337,.0034), vec3(.722,.144,.0043),
                               vec3(.878,.234,.0038));
    float phase = detailPhase(seconds);
    for (int i = 0; i < 5; ++i) {
        vec3 pod = pods[i];
        float seed = 2.17 * float(i);
        float angle = phase + seed;
        vec2 center = pod.xy + vec2(.0048,.0103) * detailOrbit(angle) +
                      vec2(.0012,.0022) * detailOrbit(2.0 * angle);
        float pulse = seed + 1.30 * sin(3.0 * phase + seed) + .39 * cos(2.0 * angle);
        rgb = jellyBell(p, center, pod.z, pulse, .57, rgb);
    }
    return rgb;
}

vec3 detailSwim(vec3 rgb, vec2 p, vec3 home, vec2 range, float seed, vec3 color, float phase) {
    if (any(greaterThan(abs(p - home.xy), 1.13 * range + vec2(home.z, home.z * FISH_ASPECT) * 1.7)))
        return rgb;
    float a = phase + seed;
    vec2 cycle = detailOrbit(a);
    vec2 turn = detailOrbit(2.0 * a + seed);
    vec2 position = home.xy + range * (cycle + .12 * turn);
    vec2 tangent = range * (vec2(-cycle.y, cycle.x) + .24 * vec2(-turn.y, turn.x));
    tangent = normalize(tangent * vec2(1.0, 1.0 / FISH_ASPECT));
    vec2 d = (p - position) * vec2(1.0, 1.0 / FISH_ASPECT) / home.z;
    vec2 q = vec2(dot(d, tangent), dot(d, vec2(-tangent.y, tangent.x)));
    float body = length((q - vec2(.10,0.0)) / vec2(.77,.245)) - 1.0;
    float wag = .18 * sin(16.0 * phase + seed * 4.7);
    float tail = fishTriangle(q, vec2(-.53,.0), vec2(-1.12,-.32 + wag), vec2(-1.07,.32 + wag));
    float blur = max(.10,.00045 / home.z);
    float silhouette = 1.0 - smoothstep(-blur, blur, body);
    float fin = 1.0 - smoothstep(-.07, blur, tail);
    float back = exp(-18.0 * sceneSquare(q.y + .16));
    vec3 lit = color * (.72 + .42 * back) + back * vec3(.102,.113,.115);
    return mix(rgb, lit, .83 * max(silhouette, .60 * fin));
}

vec3 detailSwimmers(vec3 rgb, vec2 p, float seconds, bool distant) {
    float phase = detailPhase(seconds);
    if (distant) {
        if (p.y > .29) return rgb;
        const vec3 scouts[8] = vec3[8](vec3(.185,.155,.0030), vec3(.217,.201,.0027),
            vec3(.271,.166,.0021),vec3(.337,.180,.0040),vec3(.667,.207,.0032),
            vec3(.729,.173,.0031),vec3(.816,.167,.0040),vec3(.880,.199,.0027));
        for (int i = 0; i < 8; ++i) {
            float k = float(i);
            float flip = i % 2 == 0 ? 1.0 : -1.0;
            rgb = detailSwim(rgb, p, scouts[i], vec2(.031 + .006*sin(k),.0072),
                             k*2.71, vec3(.111,.290,.391), phase*flip);
        }
        return rgb;
    }
    if (p.y < .63) return rgb;
    const vec3 shoals[14] = vec3[14](vec3(.200,.785,.0037), vec3(.258,.804,.0029),
        vec3(.327,.811,.0034),vec3(.379,.853,.0035),vec3(.410,.864,.0029),
        vec3(.476,.899,.0043),vec3(.509,.878,.0030),vec3(.547,.923,.0033),
        vec3(.566,.908,.0041),vec3(.668,.853,.0041),vec3(.736,.702,.0034),
        vec3(.758,.700,.0032),vec3(.842,.768,.0035),vec3(.919,.809,.0035));
    for (int i = 0; i < 14; ++i) {
        float k = float(i);
        float seed = hash12(vec2(k,21.0));
        float rate = i % 3 == 0 ? -2.0 : 1.0;
        vec3 color = mix(vec3(.25,.10,.21), vec3(.61,.441,.096), smoothstep(.22,.74,seed));
        rgb = detailSwim(rgb, p, shoals[i], vec2(.0105 + .0065 * seed,.009 + .005 * seed),
                         k * 3.51, color, phase * rate);
    }
    return rgb;
}

vec3 wildlifeSchool(vec3 rgb, vec2 p, float phase) {
    if (p.x < .30 || p.x > .88 || p.y < .18 || p.y > .54) return rgb;
    float templeAlpha = texture(templeMask, p).r;
    for (int i = 0; i < 18; ++i) {
        float k = float(i);
        float seed = hash12(vec2(k, 72.));
        float angle = phase + .047 * k + .09 * seed;
        vec2 orbit = detailOrbit(angle);
        vec2 radius = vec2(.245 + .018 * seed, .113 + .014 * seed);
        vec2 center = vec2(.59, .36) + radius * orbit;
        center.y += .044 * (seed - .5) + .005 * sin(3. * angle + k);
        vec2 velocity = radius * vec2(-orbit.y, orbit.x);
        velocity.y += .015 * cos(3. * angle + k);
        float nearness = .5 + .5 * orbit.y;
        float size = mix(.012, .023, nearness) * (.82 + .31 * seed);
        vec4 fish = fishIndividual(p, center, atan(velocity.y / FISH_ASPECT, velocity.x),
                                   size, mix(.73, .14, nearness), seed, .55 * sin(18. * phase + k));
        if (fish.a <= 0.) continue;
        if (orbit.y < 0.) {
            fish.a *= 1. - templeAlpha;
        }
        vec3 tint = mix(vec3(.78, 1.22, 1.21), vec3(1.55, 1.16, .69), seed);
        rgb = mix(rgb, fish.rgb * tint, fish.a * (.76 + .24 * nearness));
    }
    return rgb;
}

vec3 wildlifeShot(vec2 p, float seconds) {
    float waterTime = mod(seconds, DETAIL_LOOP_SECONDS);
    float phase = detailPhase(waterTime);
    // The fixed camera lets the masonry and reef share a single color texture.
    float wave = sin(35. * p.x + 7. * p.y + phase);
    vec2 ripple = .0007 * vec2(wave, cos(27. * p.x - 9. * p.y - phase));
    vec3 rgb = texture(scenery, p + ripple * (.3 + .7 * (1. - p.y))).rgb;
    float caustic = sin(67. * p.x + 10. * p.y + 2. * phase + wave);
    rgb *= 1. + .028 * caustic + .025 * wave * (1. - p.y);
    rgb = detailJellies(rgb, p, waterTime);
    rgb = detailVents(rgb, p, waterTime);
    rgb = detailMotes(rgb, p, waterTime);
    rgb = detailSwimmers(rgb, p, waterTime, true);
    rgb = detailSwimmers(rgb, p, waterTime, false);
    rgb = wildlifeSchool(rgb, p, DETAIL_TAU * seconds / WILDLIFE_LOOP_SECONDS);
    // Tall ribbon blades at the two near corners cross in front of the fish.
    vec4 leaves=vec4(0.);
    if(p.y>.49&&(p.x<.23||p.x>.77)){
        float side=p.x<.5?1.:-1.;
        for(int i=0;i<11;i++){
            float k=float(i), seed=hash12(vec2(k,side+9.));
            float fan=(k-5.)/5.;
            vec2 root=vec2(side>0.?.068:.918,.978+.014*seed);
            root.x+=.028*fan;
            vec2 tip=root+vec2(.060*fan+.022*sin(phase+k*.44),
                               -(.17+.24*seed+.047*cos(fan*2.2)));
            rfKelpBlade(leaves,p,root,tip,.005+.006*seed,
                        .013*sin(phase+k*.62)-.009*fan,seed*14.,phase+k*.8,.19+.49*seed);
        }
    }
    return detailOver(rgb,rfFinish(leaves));
}

void main() { color = vec4(wildlifeShot(uv, seconds), 1.); }
