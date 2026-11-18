// The export samples one period at 24 frames per second.
#define DETAIL_LOOP_FRAMES 288
const float DETAIL_LOOP_SECONDS = float(DETAIL_LOOP_FRAMES) / 24.0;
const float DETAIL_TAU = 6.283185307179586;

float detailPhase(float seconds) {
    return DETAIL_TAU * fract(seconds / DETAIL_LOOP_SECONDS);
}

vec2 detailOrbit(float phase) {
    return vec2(cos(phase), sin(phase));
}

// Single-pass shot controls. Time is in seconds and AA is samples per axis.
#ifndef DEBUG_MODE
#define DEBUG_MODE 0
#endif
#ifndef FREEZE_TIME
#define FREEZE_TIME -1.0
#endif
#ifndef START_TIME
#define START_TIME 0.0
#endif
#ifndef AA
#define AA 2
#endif



// Library code below is bundled from shader-skills (MIT): https://github.com/gokayfem/shader-skills
// ---- shader-skills library: hash ----
// PCG-style 1D integer hash.
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
// Map a uint to [0,1) using the top 24 bits, so the result can never round up to 1.0.
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
vec2 uintToUnit(uvec2 h) { return vec2(h >> 8u) * (1.0 / 16777216.0); }
vec3 uintToUnit(uvec3 h) { return vec3(h >> 8u) * (1.0 / 16777216.0); }
vec4 uintToUnit(uvec4 h) { return vec4(h >> 8u) * (1.0 / 16777216.0); }
// Random float in [0,1) for an integer-valued 2D input.
float hash12(vec2 p) {
    uvec2 q = uvec2(ivec2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}
// Random float in [0,1) for an integer-valued 3D input.
float hash13(vec3 p) {
    uvec3 q = uvec3(ivec3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
}

// ---- shader-skills library: noise ----
// Quintic fade 6t^5 - 15t^4 + 10t^3: C2-continuous interpolation weights for lattice noise.
vec2 quinticFade(vec2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
vec3 quinticFade(vec3 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
// Derivative of quinticFade: 30 t^2 (t - 1)^2.
vec2 quinticFadeDeriv(vec2 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
vec3 quinticFadeDeriv(vec3 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
// 2D value noise with analytic derivatives. Returns vec3(value, d/dx, d/dy).
vec3 valueNoiseD(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = quinticFade(f), du = quinticFadeDeriv(f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k3 = a - b - c + d;
    return vec3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
                du * vec2(k1 + k3 * u.y, k2 + k3 * u.x));
}
// 2D value noise.
float valueNoise(vec2 p) { return valueNoiseD(p).x; }
// 3D value noise.
float valueNoise(vec3 p) {
    vec3 i = floor(p), f = fract(p);
    vec3 u = quinticFade(f);
    return mix(mix(mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), u.x),
                   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
               mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
                   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

// ---- shader ----

float sceneSquare(float x){return x*x;}

// A receding surface plane compresses the waves toward the distant waterline.
vec3 waterSurface(vec3 water, vec2 p, float t, float daylight) {
    float depth = max(p.y, 0.0);
    vec2 q = vec2((p.x - .46) * 28.0, depth * 69.0) / max(.40, 1.0 - 4.6 * depth);
#if defined(DETAIL_LOOP_FRAMES)
    float phase = detailPhase(t);
    float swell = valueNoise(q * vec2(.65, .36) + .48 * detailOrbit(phase - .7));
    float wind = valueNoise(q * vec2(1.23, .84) + .55 * detailOrbit(2.0 * phase + 1.1) + 9.3);
    float a = dot(q, vec2(.36, 2.97)) + 7.2 * swell - 3.0 * phase;
    float b = dot(q, vec2(-.96, 4.89)) + 3.9 * wind + 4.0 * phase;
    float c = dot(q, vec2(1.76, 7.13)) - 2.9 * swell - 4.0 * phase;
#else
    float swell = valueNoise(q * vec2(.65, .36) + vec2(-.17, .20) * t);
    float wind = valueNoise(q * vec2(1.23, .84) + vec2(.31, -.27) * t + 9.3);
    float a = dot(q, vec2(.36, 2.97)) + 7.2 * swell - 1.49 * t;
    float b = dot(q, vec2(-.96, 4.89)) + 3.9 * wind + 1.85 * t;
    float c = dot(q, vec2(1.76, 7.13)) - 2.9 * swell - 2.15 * t;
#endif
    float displacement = .54 * sin(a) + .32 * sin(b) + .14 * sin(c);
    float slope = .54 * cos(a) + .35 * cos(b) + .23 * cos(c);
    float openings = smoothstep(.04, .81, displacement + .29 * wind)
                   * (.19 + .81 * smoothstep(.16, .78, wind));
    float glint = smoothstep(.23, .65, displacement)
                 * smoothstep(.03, .24, slope) * (1.0 - smoothstep(.28, .66, slope));
    glint *= smoothstep(.31, .79, wind + .26 * swell);
    float cover = 1.0 - smoothstep(.006, .136, depth);
    float reflection = exp(-14.0 * depth) * cover * (.26 + .74 * daylight);
    water *= 1.0 - reflection * (.13 + .12 * swell) * (1.0 - openings);
    water = mix(water, vec3(.72, .89, .94), reflection * .34 * openings);
#if defined(DETAIL_LOOP_FRAMES)
    vec2 ripple=q*vec2(6.8,5.7)+vec2(1.32,1.58)*detailOrbit(2.0*phase-1.2);
#else
    vec2 ripple=q*vec2(6.8,5.7)+vec2(.66,-.91)*t;
#endif
    float broadFold=valueNoise(ripple*vec2(.37,.71)+vec2(swell,wind)*1.6);
    float fineFold=valueNoise(ripple+vec2(0.,3.5*broadFold));
    float crest=smoothstep(.60,.83,.46*broadFold+.54*fineFold);
    float overhead=exp(-sceneSquare((p.x-.46)/.21)-24.*depth);
    water=mix(water,vec3(.96,.98,1.),overhead*(.14+.70*crest));
#if defined(DETAIL_LOOP_FRAMES)
    float streak=valueNoise(vec2(q.x*15.+2.4*wind,q.y*49.+3.*sin(q.x*5.+2.0*phase))
                           +.75*detailOrbit(2.0*phase-2.1));
    float openingPatch=valueNoise(vec2(q.x*3.1+wind*1.7,q.y*9.4+swell*1.3)
                                 +vec2(.47,.86)*detailOrbit(phase+1.7));
#else
    float streak=valueNoise(vec2(q.x*15.+2.4*wind,q.y*49.+3.*sin(q.x*5.+t))+vec2(t*.34,t*.63));
    float openingPatch=valueNoise(vec2(q.x*3.1+wind*1.7,q.y*9.4+swell*1.3)+vec2(t*.18,-t*.43));
#endif
    float pool=smoothstep(.48,.84,openingPatch)*smoothstep(.26,.79,swell+wind*.21);
    water+=reflection*(.25+.75*daylight)*vec3(.13,.15,.14)*(smoothstep(.53,.87,streak)-.18);
    water=mix(water,vec3(.93,.97,.99),reflection*pool*(.07+.59*daylight*daylight));
    return mix(water, vec3(.99, .997, 1.0), reflection * .91 * glint);
}

vec3 waterColumn(vec2 p, float t) {
    float depth = max(p.y, 0.0);
    float x = p.x - .466;
    float daylight = exp(-pow(abs(x / (.249 + .149 * depth)), 2.18));
    float core = exp(-sceneSquare(x / .089) - 17.0 * depth);
    float transmission = exp(-3.34 * depth);
    vec3 water = mix(vec3(.066, .340, .473), vec3(.038, .130, .213), depth);
    water += daylight * transmission * vec3(.380, .464, .425);
    water += core * vec3(.229, .122, .096);
    float backscatter = (.45 + .55 * smoothstep(.008, .087, depth)) * exp(-1.5 * depth);
    water += backscatter * vec3(.0, .075, .090);
    float rightGlow = exp(-sceneSquare((p.x - .721) / .098) - 5.4 * depth);
    water += rightGlow * vec3(.046, .096, .089);

    // Angular spread and separate scattering envelopes shape each band below the surface.
#if defined(DETAIL_LOOP_FRAMES)
    float phase = detailPhase(t);
    float bend = .012 * sin(p.y * 11.0 + p.x * 13.0 + phase);
    float angle = (x - bend * depth) / (1.0 + .82 * depth);
    float broad = valueNoise(vec2(47.0 * angle + .73 * depth, 3.8 * depth) + .32 * detailOrbit(phase));
    float narrow = valueNoise(vec2(109.0 * (angle + .074 * depth), 6.1 * depth + 3.0)
                             + .38 * detailOrbit(2.0 * phase + .8));
#else
    float bend = .012 * sin(p.y * 11.0 + p.x * 13.0 + t * .29);
    float angle = (x - bend * depth) / (1.0 + .82 * depth);
    float broad = valueNoise(vec2(47.0 * angle + .73 * depth, 3.8 * depth + .14 * t));
    float narrow = valueNoise(vec2(109.0 * (angle + .074 * depth), 6.1 * depth - .18 * t + 3.0));
#endif
    float shafts = .75 * (broad - .49) + .62 * smoothstep(.56, .96, narrow) - .12;
    float scattering = (.24 + .76 * daylight) * exp(-4.0 * depth)
                     * smoothstep(-.023, .037, depth);
    water += scattering * shafts * vec3(.085, .106, .109);
    // Separate refracted bundles follow bright ridges measured at rows
    // 6, 24 and 42 of the 880-pixel reference. Each opening moves locally.
    const vec3 bundles[8]=vec3[8](vec3(307,-.20,3.8),vec3(339,-.23,3.1),
        vec3(355,.09,2.5),vec3(381,.05,3.3),vec3(397,.32,2.8),
        vec3(416,.32,3.6),vec3(440,.22,2.1),vec3(462,-.08,3.4));
    if(p.x>.24&&p.x<.66&&depth<.60){
        float y=depth*376.;
        float glow=0.;
        for(int i=0;i<8;i++){
            vec3 b=bundles[i];
#if defined(DETAIL_LOOP_FRAMES)
            float shift=sin(phase+float(i)*2.1)*1.6+sin(y*.075+2.0*phase+float(i))*.46;
            float shear=.53*sin(y*.064+float(i)*1.7+phase);
            float gate=valueNoise(vec2(float(i)*5.7,y*.042)+.54*detailOrbit(phase+float(i)));
            float beamPulse=sin(float(i)*4.31+phase);
#else
            float shift=sin(t*.85+float(i)*2.1)*1.6+sin(y*.075+t*.44+float(i))*.46;
            float shear=.53*sin(y*.064+float(i)*1.7+t*.46);
            float gate=valueNoise(vec2(float(i)*5.7+t*.41,y*.042+t*.33));
            float beamPulse=sin(float(i)*4.31+t*.57);
#endif
            float distance=(p.x*880.-b.x-y*b.y-shift-shear)/(b.z+y*.049);
            float blade=exp(-distance*distance);
            float filaments=.79+.21*cos(distance*6.6+.68*sin(y*.065+float(i)));
            glow+=blade*(.49+.51*gate)*filaments*(.79+.21*beamPulse);
        }
        water+=vec3(.205,.202,.166)*glow*exp(-y*.012)*smoothstep(-3.,8.,y);
    }

    water += vec3(.093,.059,.039)*daylight*exp(-21.*depth);
    float westShelf=exp(-sceneSquare((p.x-.19)/.18));
    water-=vec3(.030,.052,.043)*westShelf*exp(-13.*depth);
    if (depth < .136) water = waterSurface(water, p, t, daylight);
    return water;
}
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

vec3 bubbleField(vec2 p, float t, vec2 vent, float rise, float lean, float width, float light, float seed, vec3 rgb) {
    float h = vent.y - p.y;
    if (h < -.006 || h > rise || abs(p.x - vent.x) > abs(lean) + 4.0 * width) return rgb;
    float age = max(0.0, h / rise);
    float center = vent.x + lean * age + width * .49 * sin(age * 8.3 + seed - t * .49);
    float spread = width * (.64 + .86 * age);
    float crossStream = (p.x - center) / spread;
    if (abs(crossStream) > 2.8) return rgb;
    float cloud = exp(-.66 * crossStream * crossStream);
    float cutoffs = smoothstep(-.006, .041, h) * (1.0 - smoothstep(.72, 1.0, age));
    float intermittence = .65 + .35 * valueNoise(vec2(age * 12.0 + t * 1.9, seed));
    for (int layer = 0; layer < 3; layer++) {
        float k = float(layer);
        float spacing = .0103 * exp(-k * .92) * (.51 + .49 * light);
        float velocity = .109 - .022 * k + .011 * sin(seed);
        vec2 cellUV = vec2(p.x - center, (.42818 * (p.y + t * velocity))) / spacing + vec2(13.74, 31.52) * (seed + k);
        vec2 cell = floor(cellUV);
        float chance = hash12(cell + vec2(3.7, 5.4) * seed);
        float density = (.12 + .24 * k) * cloud * intermittence;
        if (chance < density) {
            float size = hash12(cell + vec2(15.74, 91.61));
            vec2 wander = vec2(sin(t * 3.9 + size * 62.7), cos(t * 6.3 + size * 71.3));
            vec2 offset = (vec2(hash12(cell + vec2(4.25, 37.9)), hash12(cell + vec2(25.1, 72.0))) - .5) * .29 + .059 * wander;
            vec2 shape = vec2(1.0, 1.05 + size * .24 - .09 * sin(t * 4.3 + size * 58.0));
            float radius = .125 + .138 * size;
            vec2 q = (fract(cellUV) - .5 - offset) * shape / radius;
            rgb = ventBubble(rgb, q, cutoffs * light * (.61 + .34 * size));
        }
    }
    return rgb;
}

vec3 suspendedParticles(vec2 p, float t, vec3 rgb) {
    float waterLight = exp(-sceneSquare((p.x - .47) / .46) - 1.65 * p.y);
    vec2 grid = (p + vec2(-.0009, .003) * t) * vec2(662.0, 283.0);
    vec2 cell = floor(grid);
    float r = hash12(cell + 46.0);
    if (r > .991) {
        vec2 offset = (vec2(hash12(cell + vec2(98.1, 3.7)), hash12(cell + vec2(36.4, 60.9))) - .5) * .56;
        vec2 q = fract(grid) - .5 - offset;
        float flash = .60 + .40 * sin(47.0 * r + t * 1.7);
        float mote = exp(-50.0 * dot(q, q)) * waterLight * flash;
        rgb += .25 * mote * vec3(.54, .78, .88);
    }
    // Nearer marine snow occupies a coarser plane, crosses a fine mote
    // field and catches light differently along the two canyon shoulders.
    vec2 gridNear=(p+vec2(-.0022,.0064)*t)*vec2(152.,65.);
    vec2 id=floor(gridNear);
    float key=hash12(id+vec2(20.,91.));
    if(key>.968){
        vec2 jitter=vec2(hash12(id+9.),hash12(id-8.))-.5;
        vec2 local=fract(gridNear)-.5-jitter*.50;
        local.x+=.034*sin(t*1.57+key*131.);
        float h=exp(-dot(local*vec2(11.,14.),local*vec2(11.,14.)));
        float rim=exp(-dot((local+vec2(.017,.023))*20.,(local+vec2(.017,.023))*20.));
        float depthLight=.39+.61*exp(-sceneSquare((p.x-.42)/.24));
        rgb=mix(rgb,vec3(.55,.69,.72),h*depthLight*.23);
        rgb+=vec3(.09,.105,.102)*rim*(.47+.53*key);
    }
    return rgb;
}

vec3 jellyAndBubbles(vec2 p, float t, vec3 rgb) {
    const vec2 pods[12] = vec2[12](vec2(.125,.142), vec2(.155,.263), vec2(.073,.243), vec2(.351,.142),
        vec2(.346,.216), vec2(.719,.155), vec2(.837,.234), vec2(.858,.256), vec2(.276,.553),
        vec2(.080,.218), vec2(.165,.197), vec2(.508,.175));
    const vec2 velocities[12] = vec2[12](vec2(-.0005,-.0147), vec2(-.0021,-.0140), vec2(.0003,-.0092),
        vec2(-.0009,-.0104), vec2(-.0003,-.0086), vec2(-.0011,-.0107), vec2(-.0009,-.0081),
        vec2(-.0008,-.0121), vec2(.0012,-.0104), vec2(-.0002,-.0120), vec2(-.0005,-.0063), vec2(.0009,-.0112));
    const float radii[12] = float[12](.0100, .0073, .0067, .0071, .0041, .0060, .0046, .0054, .0060, .0035, .0060, .0031);
    const float light[12] = float[12](1.0, 1.0, .52, 1.0, .64, .91, .59, .69, .69, .53, .31, .64);
    for (int i = 0; i < 12; i++) {
        float phase = 1.97 * float(i) + t * (2.7 + .06 * float(i));
        vec2 center = pods[i] + t * velocities[i] + vec2(.0015, .0021) * vec2(sin(phase * .72), cos(phase));
        rgb = jellyBell(p, center, radii[i], phase, light[i], rgb);
    }

    // Each vent specifies an origin, rise, lean, plume width and illumination.
    const vec4 vents[9] = vec4[9](vec4(.235, .894, .340, -.046), vec4(.360, .955, .206, .015),
        vec4(.882, .899, .171, -.012), vec4(.317, .421, .248, -.023), vec4(.200, .433, .120, -.027),
        vec4(.512, .343, .189, -.009), vec4(.659, .243, .208, .018), vec4(.767, .269, .255, .017),
        vec4(.858, .615, .128, -.017));
    const vec2 plume[9] = vec2[9](vec2(.0108, 1.0), vec2(.0046, .46), vec2(.0058, .70),
        vec2(.0039, .77), vec2(.0044, .66), vec2(.0042, .80), vec2(.0044, .48), vec2(.0052, .55),
        vec2(.0050, .47));
    for (int i = 0; i < 9; i++) {
        vec4 vent = vents[i];
        rgb = bubbleField(p, t, vent.xy, vent.z, vent.w, plume[i].x, plume[i].y, float(i + 1), rgb);
    }
    return suspendedParticles(p, t, rgb);
}

// Geometry is projected into the 880 x 376 review camera. All distances
// below are in reference-camera pixels, independent of the render raster.
float plazaSegment(vec2 p,vec2 a,vec2 b){
    vec2 u=b-a; return length(p-a-u*clamp(dot(p-a,u)/dot(u,u),0.,1.));
}
float plazaCross(vec2 p,vec2 a,vec2 b){
    vec2 u=b-a;return dot(p-a,normalize(vec2(-u.y,u.x)));
}
float plazaQuad(vec2 p,vec2 a,vec2 b,vec2 c,vec2 d){
    return min(min(plazaCross(p,a,b),plazaCross(p,b,c)),min(plazaCross(p,c,d),plazaCross(p,d,a)));
}
float stoneNoise(vec2 p){
    return .46*valueNoise(p*.15)+.29*valueNoise(p*.41)+.17*valueNoise(p*1.29)+.08*valueNoise(p*2.8);
}
vec3 plazaStone(vec2 s,float t){
    float n=stoneNoise(s);
    float sand=valueNoise(s*vec2(.091,.24)+vec2(3.2,8.1));
    float wear=valueNoise(s*vec2(.039,.075));
    float grain=hash12(floor(s*2.6));
    vec2 tile=vec2((s.x-495.)*30./(s.y-99.),-8160./(s.y-99.));
    tile+=vec2(.31*valueNoise(s*.23),.22*valueNoise(s*.31));
    tile.x+=.5*mod(floor(tile.y),2.);
    vec2 joint=min(fract(tile),1.-fract(tile));
    float seams=max(exp(-joint.x*27.)*.34,exp(-joint.y*33.)*.68);
    float grit=smoothstep(.71,.90,valueNoise(s*.49)+.2*grain);
    float caustic=sin(s.x*.15+s.y*.29+5.8*valueNoise(s*.07)+t*.44);
    vec3 exposed=mix(vec3(.59,.56,.49),vec3(.96,.92,.83),.59*n+.20*sand+.21*wear);
    exposed+=vec3(.10,.107,.10)*pow(max(0.,caustic),5.);
    exposed*=.98+.055*grain;
    exposed=mix(exposed,vec3(.26,.31,.30),grit*.25);
    return mix(exposed,vec3(.32,.35,.33),seams*smoothstep(.40,.78,wear)*.42);
}
vec3 medallion(vec2 p,vec2 o,vec2 radii,float rot,float phase,int motif,vec3 col){
    vec2 q=p-o;
    q=vec2(q.x*cos(rot)+q.y*sin(rot),-q.x*sin(rot)+q.y*cos(rot))/radii;
    float r=length(q);
    if(r>1.10)return col;
    float theta=atan(q.y,q.x+1.e-6);
    float n=stoneNoise(p*1.4);
    r+=(valueNoise(p*.71)-.5)*.043;
    float turn=r*(motif==0?2.45:1.96)-theta/6.283185+phase;
    float scroll=abs(fract(turn+.5)-.5);
    float gold=1.-smoothstep(.066,.135,scroll);
    float blueMask=1.-smoothstep(.89,1.01,r);
    if(motif==1){
        // A broad band sweeps around an unpaved court inside the arcade.
        blueMask=(1.-smoothstep(.989,1.025,r))*smoothstep(.783,.833,r);
        blueMask*=smoothstep(-.45,-.23,q.y-.14*q.x);
        gold=max(exp(-abs(r-.823)*87.),exp(-abs(r-.992)*86.));
    }else if(motif==2){
        // A secondary curl feeds the broad ribbon and its nested border.
        float inset=length((q-vec2(-.22,-.05))/vec2(.72,.91));
        scroll=abs(fract(inset*1.56-atan(q.y+.05,q.x+.22+1.e-6)/6.283185+phase+.5)-.5);
        gold=mix(1.-smoothstep(.075,.16,scroll),1.,smoothstep(.58,.75,q.x)*(1.-smoothstep(-.27,.15,q.y)));
        gold=max(gold,exp(-abs(r-.943)*81.));
    }else{
        gold=max(gold*(1.-smoothstep(.77,.91,r)),exp(-abs(r-.922)*78.));
        blueMask*=.75+.25*smoothstep(.10,.55,valueNoise(p*.31));
    }
    float row=floor(r*17.);
    float sectors=max(6.,floor((row+1.)*5.));
    float sector=(theta/6.283185+.5)*sectors+.5*mod(row,2.);
    float azimuth=fract(sector);
    float radial=fract(r*17.);
    float grout=max(exp(-min(azimuth,1.-azimuth)*22.),exp(-min(radial,1.-radial)*26.));
    float fragment=hash12(vec2(floor(sector),row));
    float age=valueNoise(p*.26);
    vec3 blue=mix(vec3(.048,.224,.31),vec3(.285,.585,.673),.63*n+.28*fragment+.09*age);
    vec3 ochre=mix(vec3(.47,.34,.18),vec3(.88,.73,.45),n*.66+fragment*.34);
    vec3 tessera=mix(blue,ochre,gold);
    tessera=mix(tessera,vec3(.51,.49,.41),grout*(.33+.30*age));
    float missing=smoothstep(.71,.87,valueNoise(p*.16)+.11*fragment);
    float facet=exp(-radial*13.)*smoothstep(.075,.21,azimuth);
    tessera+=vec3(.14,.15,.14)*facet*(.48+.52*fragment);
    return mix(col,tessera,blueMask*(.96-.66*missing));
}
// A continuous band of inlay bends into a scroll. The turns are evaluated
// in the plane of the floor before projection into the review camera.
float plazaSpiral(vec2 q,float turns,float phase,float outer){
    float radius=length(q);
    float angle=fract((atan(q.y,q.x)+phase)/6.283185);
    float nearest=2.;
    for(int i=0;i<3;i++){
        float f=(angle+float(i))/turns;
        if(f<1.)nearest=min(nearest,abs(radius-(.045+outer*f)));
    }
    return nearest;
}
vec3 courtScroll(vec2 s,vec2 center,vec2 scale,float tilt,vec3 under,int design){
    vec2 d=s-center;
    vec2 q=vec2(d.x,d.y-tilt*d.x)/scale;
    if(abs(q.x)>1.25||abs(q.y)>1.30)return under;
    float r=length(q);
    float wear=stoneNoise(s*1.28);
    float cut=(wear-.5)*.038;
    float body=1.-smoothstep(.95+cut,1.012+cut,r);
    float spiral=plazaSpiral(q,2.08,design==0?1.32:2.58,.90);
    float border=abs(r-.926);
    float band=min(spiral,border);
    float gold=1.-smoothstep(.048,.077,band);
    if(design==1)gold=1.-gold;
    vec2 stone=s*vec2(.64,1.14)+vec2(.82*valueNoise(s*.18),.36*valueNoise(s*.37));
    float row=floor(stone.y);
    stone.x+=.46*mod(row,2.);
    vec2 gap=min(fract(stone),1.-fract(stone));
    float id=hash12(floor(stone));
    float joint=1.-smoothstep(.015,.105,min(gap.x,gap.y));
    float facet=exp(-fract(stone.y)*16.)*(.23+.77*id);
    vec3 lapis=mix(vec3(.106,.293,.397),vec3(.41,.60,.67),.52*wear+.48*id);
    vec3 amber=mix(vec3(.51,.361,.18),vec3(.94,.78,.49),.41*wear+.59*id);
    vec3 inlay=mix(lapis,amber,gold);
    inlay=mix(inlay,vec3(.62,.58,.50),joint*.72)+facet*vec3(.13,.13,.11);
    float incised=exp(-abs(band-.063)*103.);
    inlay*=1.-.32*incised;
    float spall=smoothstep(.76,.93,valueNoise(s*.21)+.12*id);
    return mix(under,inlay,body*(1.-spall*.62));
}

// Landmarks for the main inlay are projected into the floor plane.
// Both the central coil and its sweeping fillet use the same stone field.
float courtCurve(vec2 s,vec2 a,vec2 b,vec2 c,vec2 d){
    vec2 prev=a;
    float dist=100.;
    for(int i=1;i<=8;i++){
        float u=float(i)*.125,v=1.-u;
        vec2 pt=v*v*v*a+3.*v*v*u*b+3.*v*u*u*c+u*u*u*d;
        dist=min(dist,plazaSegment(s,prev,pt));
        prev=pt;
    }
    return dist;
}
vec3 principalInlay(vec2 s,vec3 col){
    if(s.x<488.||s.x>555.||s.y<269.||s.y>300.)return col;
    vec2 q=s-vec2(508.7,281.0);
    float perimeter=(1.-length((s-vec2(520.8,283.2))/vec2(29.5,11.7)))*10.;
    float tail=plazaQuad(s,vec2(494.,284.),vec2(544.,274.),
                         vec2(552.,286.),vec2(501.,299.));
    float age=valueNoise(s*.72);
    float edge=smoothstep(-.23,.42,max(perimeter,tail)+(age-.5)*.66);
    float ring=courtCurve(s,vec2(490.2,281.1),vec2(499.4,270.),vec2(519.8,269.8),vec2(539.3,274.4));
    float sweep=courtCurve(s,vec2(496.3,291.5),vec2(516.2,292.1),vec2(523.9,281.7),vec2(539.4,274.1));
    float band=courtCurve(s,vec2(496.3,292.1),vec2(514.1,290.),vec2(531.3,280.8),vec2(516.2,275.1));
    vec2 coil=vec2(q.x/15.4,q.y/6.8);
    float curl=6.4*plazaSpiral(coil,1.43,-1.33,.86);
    if(q.x>7.5&&q.y<-3.3)curl=99.;
    float dist=min(min(ring,sweep),min(band,curl));
    float line=1.-smoothstep(.33,.88,curl);
    line=max(line,1.-smoothstep(.73,1.31,min(ring,min(band,sweep))));
    vec2 tiles=vec2(s.x*.76+s.y*.32,s.y*1.35-s.x*.14)+.49*valueNoise(s*.65);
    tiles.x+=.49*mod(floor(tiles.y),2.);
    vec2 gap=min(fract(tiles),1.-fract(tiles));
    float tessera=hash12(floor(tiles)),grout=1.-smoothstep(.028,.119,min(gap.x,gap.y));
    float chip=smoothstep(.78,.91,age+.12*tessera);
    vec3 glass=mix(vec3(.15,.295,.392),vec3(.43,.605,.694),tessera);
    vec3 gold=mix(vec3(.53,.354,.166),vec3(.93,.77,.51),.68*tessera+.32*age);
    vec3 face=mix(glass,gold,line);
    face=mix(face,vec3(.43,.44,.412),.49*grout);
    face+=vec3(.22,.214,.168)*exp(-fract(tiles.y)*15.)*(.33+.67*tessera);
    face*=1.-.29*exp(-abs(dist-.90)*4.5);
    return mix(col,face,edge*(1.-.60*chip));
}
// Inclined strata break into unequal blocks at the edge of the chasm.
vec3 plazaBedrock(vec2 s,float below,vec3 wall){
    vec2 q=vec2((s.x+.19*s.y)/8.7,(s.y-.11*s.x)/5.1);
    q+=vec2(.51*valueNoise(s*.087),.58*valueNoise(s*.13+11.));
    vec2 cell=floor(q),f=fract(q),face=vec2(0.);
    float nearest=10.,next=10.,seed=0.;
    for(int iy=-1;iy<=1;iy++)for(int ix=-1;ix<=1;ix++){
        vec2 o=vec2(float(ix),float(iy));
        vec2 id=cell+o;
        vec2 center=o+.16+.68*vec2(hash12(id),hash12(id+27.));
        vec2 v=f-center;
        float distance=dot(v,v);
        if(distance<nearest){
            next=nearest;nearest=distance;face=v;seed=hash12(id+14.);
        }else next=min(next,distance);
    }
    float fissure=next-nearest;
    float n=stoneNoise(s);
    float lobe=smoothstep(.07,.22,fissure);
    float facet=clamp(.41-.61*face.y-.43*face.x+.23*(seed-.5),0.,1.);
    vec3 mineral=mix(vec3(.049,.095,.116),vec3(.31,.36,.34),facet*n*1.58);
    mineral*=.76+.27*seed;
    mineral+=exp(-abs(fissure-.073)*22.)*smoothstep(.16,.67,facet)*vec3(.105,.112,.099);
    float cutoff=exp(-below*.065)*smoothstep(-.2,2.2,below);
    return mix(wall,mineral,cutoff*(.39+.50*lobe));
}

vec4 plaza(vec2 p,float t){
    vec2 s=p*vec2(880.,376.);
    if(s.y<153.||s.x<191.||s.x>740.)return vec4(0.);
    float n=stoneNoise(s);
    float edge=max(plazaQuad(s,vec2(426,197),vec2(491,157),vec2(522,177),vec2(464,221)),
                   plazaQuad(s,vec2(232,235),vec2(476,193),vec2(716,270),vec2(475,314)));
    edge=max(edge,plazaQuad(s,vec2(402,241),vec2(534,219),vec2(679,273),vec2(533,305)));
    edge=max(edge,plazaQuad(s,vec2(507,284),vec2(649,268),vec2(691,288),vec2(623,321)));
    edge=max(edge,plazaQuad(s,vec2(477,296),vec2(543,299),vec2(574,310),vec2(503,318)));
    edge=max(edge,plazaQuad(s,vec2(529,309),vec2(595,298),vec2(658,323),vec2(580,348)));
    float apron=(1.-length((s-vec2(332.,253.)-vec2((s.y-253.)*-.55,0.))/vec2(103.,43.)))*34.;
    edge=max(edge,apron);
    float transverse=min(plazaSegment(s,vec2(476,320),vec2(488,312)),
                     min(plazaSegment(s,vec2(488,312),vec2(507,310)),
                         plazaSegment(s,vec2(507,310),vec2(521,315))));
    float fissure=transverse-1.8-1.9*valueNoise(s*.39);
    float chipped=min(edge+(n-.5)*6.+(valueNoise(s*.13)-.5)*7.,fissure);
    float cliffDepth=mix(48.,15.,smoothstep(438.,677.,s.x));
    float shelfBreak=valueNoise(s*vec2(.067,.016));
    float face=edge+(n-.5)*9.+min(cliffDepth,(s.y-164.)*.40)
               *( .64+.37*shelfBreak );
    if(face<-.65)return vec4(0.);

    vec2 chasm=vec2(s.x+s.y*.18,s.y);
    float striation=valueNoise(chasm*vec2(.20,.045));
    float ledge=valueNoise(chasm*vec2(.074,.21));
    vec3 wall=mix(vec3(.022,.064,.090),vec3(.16,.237,.258),.47*striation+.30*ledge+.23*n);
    float terraces=fract((s.y+.18*s.x+2.6*striation)*.18);
    float cleft=smoothstep(.40,.70,striation+.22*ledge);
    wall*=.63+.59*smoothstep(-cliffDepth,0.,chipped);
    float angular=valueNoise(s*vec2(.19,.031)+vec2(2.*ledge,striation));
    float spurs=smoothstep(.43,.71,angular+.16*ledge)*smoothstep(.32,.66,n);
    wall+=vec3(.074,.105,.112)*cleft*exp(-terraces*10.)*spurs*smoothstep(0.,10.,-chipped);
    wall+=vec3(.082,.117,.13)*spurs*exp(-abs(chipped+4.)*.071);
    wall*=.82+.28*angular;
    wall+=vec3(.057,.12,.15)*smoothstep(-38.,-1.,chipped)*sceneSquare(striation);
    wall+=vec3(.16,.18,.145)*exp(-abs(chipped+1.5)*.68)*(.22+.78*n);
    if(chipped < -1.){
        if(s.y>243.&&s.x>365.&&s.x<678.)wall=plazaBedrock(s,-chipped,wall);
        vec2 fissureGlow=(s-vec2(485.,331.))/vec2(5.,13.);
        wall+=vec3(.015,.080,.12)*exp(-.55*dot(fissureGlow,fissureGlow))*(.68+.32*striation);
        return vec4(wall,smoothstep(-.65,.65,face));
    }

    vec3 c=plazaStone(s,t);
    c=medallion(s,vec2(420,219),vec2(34,9.1),-.06,.19,0,c);
    c=medallion(s,vec2(435,236),vec2(25,10),-.10,.24,2,c);
    c=medallion(s,vec2(458,253),vec2(20,7),-.17,.32,2,c);
    c=medallion(s,vec2(548,248),vec2(63,23),.18,.0,1,c);
    // Two abutting fields meet along a tapered gold fillet. The small
    // ochre counter-scroll points back into the blue of the larger field.
    c=principalInlay(s,c);
    c=medallion(s,vec2(485,270),vec2(9.7,4.6),-.05,.29,0,c);
    c=courtScroll(s,vec2(480.4,299.8),vec2(17.0,7.2),.08,c,0);
    c=courtScroll(s,vec2(463.1,310.1),vec2(14.2,7.8),-.45,c,1);
    c=courtScroll(s,vec2(527.7,294.5),vec2(11.6,5.1),-.21,c,1);
    c=courtScroll(s,vec2(625,292.8),vec2(45.7,14.1),.195,c,0);

    // Cast shadows extend across the floor from the footings and the rotunda garden.
    vec2 feet[8]=vec2[8](vec2(510,218),vec2(539,249),vec2(552,289),vec2(580,300),
                          vec2(607,267),vec2(635,269),vec2(661,257),vec2(687,255));
    float shade=0.;
    for(int i=0;i<8;i++){
        vec2 projection=vec2(20.+float(i)*3.5,9.+float(i)*1.3);
        float dist=plazaSegment(s,feet[i],feet[i]+projection);
        shade=max(shade,1.-smoothstep(2.5,7.+.55*float(i),dist));
    }
    float arcade=exp(-dot((s-vec2(625.,269.))/vec2(69.,14.),(s-vec2(625.,269.))/vec2(69.,14.)));
    float court=exp(-dot((s-vec2(555.,247.))/vec2(28.,17.),(s-vec2(555.,247.))/vec2(28.,17.)));
    float garden=1.-smoothstep(.89,1.16,length((s-vec2(333.,261.))/vec2(107.,37.)));
    float eastShadow=exp(-sceneSquare((s.x-610.)/68.)-sceneSquare((s.y-269.)/32.));
    c*=1.-.51*max(shade,.60*arcade)-.36*court-.58*garden;
    // The front gallery blocks direct skylight across its apron and
    // onto the slab below it. The east face keeps the blue water fill.
    float underGallery=exp(-sceneSquare((s.x-605.)/52.)-sceneSquare((s.y-293.)/47.));
    c*=mix(vec3(1.),vec3(.62,.71,.76),eastShadow);
    c*=mix(vec3(1.),vec3(.68,.73,.80),underGallery);
    float stairPool=exp(-sceneSquare((s.x-410.)/64.)-sceneSquare((s.y-211.)/23.));
    c+=vec3(.15,.14,.11)*stairPool;
    c=mix(c,vec3(.105,.224,.268),.23*arcade+.12*shade);
    float shear=abs(s.y-307.2+.19*(s.x-508.)+1.2*sin(s.x*.49)+1.1*valueNoise(s*.32));
    float fissurePatch=exp(-sceneSquare((s.x-526.)/46.));
    c=mix(c,vec3(.21,.23,.221),fissurePatch*(1.-smoothstep(.19,.73,shear))*.76);
    float fractured=smoothstep(.40,.73,valueNoise(s*.15)+.16*valueNoise(s*.49));
    float margin=1.-smoothstep(-.4,9.,chipped);
    vec3 crust=mix(vec3(.11,.185,.20),vec3(.42,.44,.35),n);
    c=mix(c,crust,margin*(.32+.57*fractured));

    // Fallen column drums and angular fragments sit above the tesserae.
    vec2 stones[9]=vec2[9](vec2(466,216),vec2(475,232),vec2(572,321),vec2(453,239),
                            vec2(545,273),vec2(498,299),vec2(431,248),vec2(551,314),vec2(607,325));
    vec2 axes[9]=vec2[9](vec2(28,-24),vec2(21,-12),vec2(23,1),vec2(5,7),
                         vec2(6,7),vec2(9,7),vec2(6,5),vec2(6,7),vec2(9,4));
    for(int i=0;i<9;i++){
        vec2 a=stones[i],u=axes[i];
        if(any(greaterThan(abs(s-a-.5*u),.5*abs(u)+vec2(13.))))continue;
        vec2 v=s-a;
        float along=dot(v,u)/dot(u,u);
        float lengthwise=dot(v,normalize(vec2(-u.y,u.x)));
        float w=i<3?mix(2.2,6.4,clamp(along,0.,1.)):3.9;
        if(i==2)continue; // The fallen fluted drum is projected with the near causeway.
        float side=lengthwise/w;
        float cap=abs(along-.5)*2.;
        float contact=plazaSegment(s-vec2(2.8,3.5),a,a+u);
        c*=1.-.60*(1.-smoothstep(w*.5,w+4.4,contact));
        float shape=max(abs(side),cap+.12*side*side);
        if(i>=3)shape=max(abs(side+.26*along),cap*.94+abs(side)*.27)+(n-.5)*.33;
        float gleam=clamp(.53-side*.55,0.,1.);
        vec3 rock=mix(vec3(.19,.21,.19),vec3(.69,.63,.50),gleam)*(.73+.53*n);
        if(i<3){
            float trim=exp(-abs(along-.86)*72.)+exp(-abs(along-.95)*95.);
            float flutes=exp(-abs(fract(side*2.8+along*.13)-.5)*8.);
            rock+=vec3(.24,.18,.088)*trim*(.45+.55*gleam)-.075*flutes;
        }else{
            float facet=smoothstep(-.04,.10,side+.32*along);
            rock=mix(rock,vec3(.22,.27,.256)*(.68+.68*n),facet*.71);
            rock+=vec3(.24,.25,.208)*exp(-abs(side+.32*along)*15.)*gleam;
        }
        c=mix(c,rock,1.-smoothstep(.88,1.06,shape));
    }
    vec2 warped=s+vec2(4.1*valueNoise(s*.17),3.2*valueNoise(s*.20+9.));
    vec2 pebbleSpace=mat2(.84,.54,-.54,.84)*warped*vec2(.44,.55);
    vec2 pebbleID=floor(pebbleSpace);
    float scatter=hash12(pebbleID);
    vec2 pebble=fract(pebbleSpace)-vec2(.26+.48*scatter,.29+.42*hash12(pebbleID+19.));
    float debris=length(pebble*vec2(.72,1.));
    float clusters=valueNoise(s*.085)+.19*margin+.16*arcade;
    if(scatter>.66&&clusters>.61){
        float size=.075+.19*hash12(pebbleID+37.)*smoothstep(.52,.79,clusters);
        float shadow=1.-smoothstep(size*.22,size+.16,length((pebble-vec2(.12,.20))*vec2(.76,1.)));
        c*=1.-.31*shadow;
        vec3 rock=mix(vec3(.101,.145,.156),vec3(.51,.52,.46),(1.-smoothstep(-.26,.22,pebble.y+pebble.x*.27)));
        c=mix(c,rock*(.68+.56*n),1.-smoothstep(size-.07,size+.06,debris));
    }
    return vec4(mix(wall,c,smoothstep(-.65,.65,chipped)),smoothstep(-.65,.65,face));
}
// Signed distance to a projected stone or plate with a hand-placed broken edge.
float rotundaOutline(vec2 p,vec2 vertices[8]){
    float edge=1.e4;
    float inside=-1.;
    for(int i=0;i<8;i++){
        vec2 a=vertices[i],b=vertices[(i+1)%8];
        vec2 d=b-a;
        if(dot(d,d)<.001)continue;
        edge=min(edge,plazaSegment(p,a,b));
        if((a.y>p.y)!=(b.y>p.y) && p.x<a.x+(p.y-a.y)*d.x/d.y)inside=-inside;
    }
    return edge*inside;
}
void rotundaShard(inout vec3 color,vec2 p,vec2 vertices[8],float light,float weather,float seed){
    float e=rotundaOutline(p,vertices);
    if(e< -2.4)return;
    // A raised lip throws a narrow shadow onto the plate below it.
    color*=1.-.32*smoothstep(-2.3,-.58,e)*(1.-smoothstep(-.62,.16,e));
    float n=stoneNoise(p+seed);
    e+=(n-.55)*.86;
    if(e<-.48)return;
    vec2 q=p-vertices[0];
    vec2 grainAxis=normalize(vertices[2]-vertices[0]);
    vec2 grainNormal=vec2(-grainAxis.y,grainAxis.x);
    vec2 grainUV=vec2(dot(q,grainAxis),dot(q,grainNormal));
    float hammer=valueNoise(grainUV*vec2(.69,1.72)+seed);
    float coarseness=valueNoise(grainUV*vec2(.18,.54)-seed);
    float oxide=.72*valueNoise((p+seed)*.25)+.26*valueNoise(grainUV*vec2(.54,1.3)-seed)+.24*coarseness;
    float specks=valueNoise(p*2.6+seed);
    float crust=smoothstep(.63,.93,oxide+.22*specks+.22*weather);
    float scratch=valueNoise(grainUV*vec2(.14,3.8)+seed);
    float glint=light*(.69+.31*smoothstep(.21,.77,valueNoise(p*vec2(.18,.27))));
    vec3 bronze=mix(vec3(.158,.121,.110),vec3(.593,.459,.353),glint);
    vec3 mineral=mix(vec3(.118,.166,.182),vec3(.319,.382,.339),.18+.64*light);
    vec3 plate=mix(bronze,mineral,crust*.83)*(.72+.33*n+.24*hammer+.09*specks);
    plate*=1.-.33*smoothstep(.62,.94,scratch)*(.47+.53*coarseness);
    float stripped=exp(-abs(e-.56)*1.9)*smoothstep(.48,.82,.45*hammer+.55*coarseness+.22*n);
    float chip=exp(-abs(e-.35)*3.8)*smoothstep(.40,.79,hammer+.21*n);
    plate+=vec3(.36,.28,.20)*chip*light;
    plate=mix(plate,vec3(.46,.339,.213)*(.60+.61*hammer),stripped*.44);
    float pits=smoothstep(.48,.85,oxide)*smoothstep(.73,.92,specks);
    plate-=vec3(.14,.110,.09)*pits;
    plate+=vec3(.31,.27,.215)*smoothstep(.58,.89,hammer)*smoothstep(.5,.73,oxide)*light*.39;
    vec2 beam=(p-vec2(296.3,236.2))/vec2(6.7,9.4);
    plate+=vec3(.35,.27,.171)*exp(-dot(beam,beam))*light*(.31+.69*hammer);
    color=mix(color,plate,smoothstep(-.38,.35,e));
}
void rotundaRubble(inout vec3 color,vec2 p,vec2 center,vec2 scale,float angle,float light,float seed){
    vec2 d=p-center;
    if(any(greaterThan(abs(d),vec2(max(scale.x,scale.y)*1.65))))return;
    vec2 q=vec2(dot(d,vec2(cos(angle),sin(angle))),dot(d,vec2(-sin(angle),cos(angle))))/scale;
    float bias=hash12(vec2(seed,8.))-.5;
    vec2 shape[8]=vec2[8](vec2(-1.,-.45+bias*.48),vec2(-.58,-.84),vec2(.20+bias,-.69),vec2(.70,-.92),
                           vec2(1.,.11+bias*.54),vec2(.53,.79),vec2(-.58+bias*.34,1.),vec2(-.70,.20));
    float e=rotundaOutline(q,shape)*min(scale.x,scale.y);
    if(e< -1.6)return;
    float n=stoneNoise(p*1.33+seed);
    float toe=smoothstep(-.16,.98,q.y)*smoothstep(-1.50,-.36,e)*(1.-smoothstep(-.32,.27,e));
    color*=1.-toe*.68;
    e+=(n-.48)*.52;
    if(e<-.35)return;
    float rib=q.x-.33*q.y+bias*.46;
    float ledge=q.y+.34-q.x*(.36+bias*.44)+.37*max(rib-.29,0.)+(.5-n)*.15;
    float top=1.-smoothstep(-.037,.027,ledge);
    float dark=smoothstep(.10,.18,rib);
    float lamina=q.y+.35*q.x+(.5-n)*.057;
    float cleavage=q.x*.89+q.y*(.33+bias)+bias+(.5-n)*.13;
    float fault=exp(-abs(cleavage)*18.)*smoothstep(-.37,.40,q.y);
    float layered=valueNoise(vec2(rib*3.1,lamina*18.6)+seed);
    float lighting=(.21+.62*top+.19*(1.-dark))*light;
    vec3 rock=mix(vec3(.040,.078,.095),vec3(.369,.438,.442),lighting);
    rock*=.61+.49*n+.19*layered+.20*valueNoise(p*2.63+seed);
    rock*=1.-.55*fault-.09*dark;
    float bevel=exp(-abs(ledge+.017)*26.);
    rock+=vec3(.27,.296,.27)*light*(exp(-abs(e-.28)*3.9)*top*.68+bevel*.52)*(.37+.63*n);
    rock+=vec3(.069,.099,.113)*exp(-abs(cleavage+.083)*14.)*smoothstep(-.37,.14,q.y)*light;
    color=mix(color,rock,smoothstep(-.29,.28,e));
}

// Projected faces of the displaced blocks that still have a recognizable fracture plane.
float rotundaFace(vec2 p,vec2 a,vec2 b,vec2 c,vec2 d){
    vec2 u=b-a,v=d-a;
    if(u.x*v.y-u.y*v.x<0.)return plazaQuad(p,d,c,b,a);
    return plazaQuad(p,a,b,c,d);
}
void rotundaFragment(inout vec3 color,vec2 p,vec2 a,vec2 b,vec2 c,vec2 d,vec2 shift,float light,float seed){
    if(any(lessThan(p,min(min(a,b),min(c,d))-3.))||
       any(greaterThan(p,max(max(a,b),max(c,d))+abs(shift)+3.)))return;
    float n=stoneNoise(p*1.53+seed);
    float side=rotundaFace(p,d,c,c+shift,d+shift)+(n-.51)*.77;
    float dark=rotundaFace(p,b,c,c+shift,b+shift)+(n-.51)*.56;
    float face=rotundaFace(p,a,b,c,d)+(n-.51)*.66;
    // Face normals snap at the surviving corners. Toward the bottom, the stone sinks into shadow.
    float dip=clamp(dot(p-a,normalize(d-a))/max(1.,distance(a,d)),0.,1.);
    vec2 axis=normalize(b-a);
    float layer=valueNoise(vec2(dot(p-a,axis)*.51,dot(p-a,vec2(-axis.y,axis.x))*2.8)+seed);
    float scuff=exp(-abs(dot(p-a,normalize(vec2(.4,-.8)))-1.9+(n-.5)*.31)*2.1);
    float outline=max(face,max(side,dark));
    color*=1.-.48*smoothstep(-1.8,-.2,outline)*(1.-smoothstep(-.18,.36,outline));
    vec3 cool=vec3(.090,.154,.172)*(.62+.58*n);
    vec3 warm=mix(cool,vec3(.416,.470,.451),light*(.66+.34*n));
    color=mix(color,cool*.75,smoothstep(-.25,.26,dark));
    color=mix(color,cool*(.72+.29*layer),smoothstep(-.23,.25,side));
    vec3 front=warm*(.67+.27*layer+.16*n)*(1.-.24*smoothstep(.36,.99,dip));
    front+=vec3(.15,.196,.19)*light*scuff;
    front+=vec3(.26,.28,.255)*exp(-abs(face-.28)*3.8)*light*smoothstep(.23,.77,layer);
    color=mix(color,front,smoothstep(-.23,.25,face));
}
vec3 rotundaPile(vec3 color,vec2 p){
    // Rear masonry sits behind the displaced blocks and gravel on the sill.
    const vec4 rocks[23]=vec4[23](
        vec4(336,241,13.4,6.4),vec4(351,239,4.9,5.1),vec4(325,243,4.7,4.2),
        vec4(316,249,4.4,5.6),vec4(320,254,3.5,4.7),vec4(327,251,5.1,3.4),
        vec4(325,255,4.7,4.1),vec4(330,256,3.3,5.5),vec4(328,261,3.9,4.7),
        vec4(336,263,3.1,3.4),vec4(342,259,3.3,2.6),vec4(346,262,3.0,6.2),
        vec4(351,263,3.9,4.0),vec4(355,261,3.3,3.6),vec4(358.7,259.1,3.6,4.3),
        vec4(337,270,5.2,1.6),vec4(331,272,3.1,2.0),vec4(342,269,2.4,2.1),
        vec4(367,264,2.0,3.1),vec4(371,266,2.6,1.8),vec4(304,263,5.2,4.4),
        vec4(309,269,4.2,2.5),vec4(318.5,266,4.9,2.3));
    const vec2 facing[23]=vec2[23](vec2(-.31,.21),vec2(.22,.32),vec2(.39,.29),
        vec2(.20,.47),vec2(-.24,.51),vec2(.18,.79),vec2(-.38,.73),vec2(.43,.70),
        vec2(-.25,.51),vec2(.58,.42),vec2(-.39,.53),vec2(.17,.62),vec2(-.34,.47),
        vec2(.46,.51),vec2(-.35,.41),vec2(-.21,.48),vec2(.50,.55),vec2(.13,.51),
        vec2(.33,.59),vec2(-.36,.51),vec2(.12,.48),vec2(.19,.47),vec2(-.18,.66));
    for(int i=0;i<23;i++){
        vec4 stone=rocks[i];
        rotundaRubble(color,p,stone.xy,stone.zw,facing[i].x,facing[i].y,float(i)+9.);
    }
    // Half-buried vertical block and the thin slabs that landed across the center.
    rotundaFragment(color,p,vec2(322.7,247.9),vec2(328.4,248.6),vec2(331.6,252.6),
                    vec2(329.8,254.5),vec2(1.9,1.8),.64,52.);
    rotundaFragment(color,p,vec2(329.8,253.6),vec2(334.1,252.9),vec2(335.7,257.1),
                    vec2(328.7,259.2),vec2(1.1,2.5),.36,61.);
    rotundaFragment(color,p,vec2(339.1,257.3),vec2(345.4,256.2),vec2(347.7,261.2),
                    vec2(341.3,264.7),vec2(.5,1.9),.43,72.);
    rotundaFragment(color,p,vec2(346.6,257.7),vec2(350.6,260.2),vec2(349.1,268.7),
                    vec2(343.8,269.1),vec2(1.4,1.1),.34,77.);
    return color;
}
void rotundaRib(inout vec3 color,vec2 p,vec2 a,vec2 b,vec2 c,vec2 d,vec2 width,float light,float seed){
    vec2 low=min(min(a,b),min(c,d))-3.;
    vec2 high=max(max(a,b),max(c,d))+3.;
    if(any(lessThan(p,low))||any(greaterThan(p,high)))return;
    vec2 pts[4]=vec2[4](a,b,c,d);
    float dist=1.e4,across=0.,position=0.;
    for(int i=0;i<3;i++){
        vec2 u=pts[i+1]-pts[i];
        vec2 q=p-pts[i];
        float t=clamp(dot(q,u)/max(.001,dot(u,u)),0.,1.);
        float dp=length(q-t*u);
        if(dp<dist){
            dist=dp;
            across=dot(q,normalize(vec2(-u.y,u.x)));
            position=(float(i)+t)/3.;
        }
    }
    float grain=stoneNoise(p*1.58+seed);
    float t=position;
    float w=mix(width.x,width.y,t)*(.85+.30*valueNoise(p*.86+seed));
    if(dist>w+1.7)return;
    color*=1.-.54*(1.-smoothstep(w*.64,w+1.65,dist));
    float edge=dist-w+(grain-.54)*.27;
    float broad=1.-smoothstep(-.13,.31,edge);
    float side=clamp(across/max(.3,w),-1.,1.);
    float flash=pow(max(0.,.48+.52*sin(dot(p,vec2(.27,.46))+seed+grain*1.6)),2.9);
    float shoulder=exp(-abs(side+.71)*11.4);
    float recess=smoothstep(.18,.82,side);
    float strip=valueNoise(vec2(t*22.5,side*.48)+seed);
    float pits=smoothstep(.52,.74,valueNoise(vec2(t*43.1,side*4.4)+seed*1.6));
    vec3 copper=mix(vec3(.105,.096,.087),vec3(.467,.338,.226),light)*(.56+.58*grain);
    copper*=.82+.23*clamp(-side+.73,0.,1.)-.32*recess;
    copper=mix(copper,vec3(.117,.188,.167),pits*(.22+.17*recess));
    copper+=vec3(.63,.51,.33)*light*(.79*shoulder+.25*flash)*(.47+.53*strip);
    color=mix(color,copper,broad);
}
vec4 rotundaFooting(vec2 s,float n){
    vec2 q=s-vec2(332.,264.2);
    q.y+=q.x*.086;
    q.x+=q.y*.34;
    vec2 plane=q/vec2(96.,32.7);
    float r=length(plane);
    float sideR=length((q-vec2(3.1,7.7))/vec2(96.,32.7));
    float a=atan(plane.y,plane.x);
    float silt=valueNoise(s*.095)+.42*valueNoise(s*.317);
    float chip=(n-.52)*.025+(valueNoise(s*.82)-.5)*.012;
    float edge=r+chip;
    float face=1.-smoothstep(.993,1.023,sideR+chip);
    float paving=1.-smoothstep(.983,1.012,edge);
    float front=smoothstep(.35,3.4,q.y);
    float segment=a*8.4+.14*sin(a*9.)+.069*(n-.46);
    float ashlar=hash12(vec2(floor(segment),12.4));
    float join=exp(-abs(fract(segment)-.5)*28.);
    float brick=exp(-abs(sideR-.955)*130.)+.66*exp(-abs(sideR-.868)*155.);
    vec3 wall=mix(vec3(.048,.111,.148),vec3(.158,.258,.285),n)*(.58+.30*front+.24*ashlar);
    wall+=vec3(.092,.158,.181)*brick*(.6+.4*n);
    wall*=1.-.39*join;
    vec3 top=mix(vec3(.18,.245,.265),vec3(.58,.578,.48),.24+.52*n);
    top=mix(top,vec3(.079,.146,.131),smoothstep(.49,1.05,silt)*.68);
    top*=.82+.22*valueNoise(s*.63);
    float coping=smoothstep(.88,.951,edge);
    float reflected=smoothstep(.32,.75,valueNoise(s*vec2(.18,.33))+.32*valueNoise(s*.78));
    top=mix(top,mix(vec3(.158,.251,.263),vec3(.57,.625,.591),reflected)*(.70+.48*n),coping*.86);
    top*=1.-join*mix(.11,.49,coping);
    top*=1.-.37*smoothstep(.59,1.04,silt)*smoothstep(.78,.94,edge);
    float nick=exp(-abs(edge-.985)*170.)*smoothstep(.48,.77,valueNoise(s*2.56));
    top+=vec3(.12,.15,.13)*nick*ashlar;
    top+=vec3(.21,.24,.23)*exp(-abs(edge-.987)*160.)*(.11+.67*reflected);
    top*=1.-.51*(1.-smoothstep(.55,.93,r));
    vec4 footing=vec4(mix(wall,top,paving),max(paving,face*front));
    if(s.x<266.&&s.y>273.){
        float spur=plazaQuad(s,vec2(225,302),vec2(256,276),vec2(265,276),vec2(234,308));
        float cap=smoothstep(-.36,.42,spur+(n-.51)*1.25);
        float depth=smoothstep(-.36,.42,spur+2.3);
        float seam=exp(-abs(fract(dot(s,vec2(.146,-.121)))-.5)*17.);
        vec3 stone=mix(vec3(.071,.142,.173),vec3(.29,.40,.419),n);
        stone*=.69+.27*smoothstep(1.,2.8,spur)-.24*seam;
        stone+=vec3(.10,.14,.13)*exp(-abs(spur-.79)*2.2);
        footing=vec4(mix(footing.rgb,mix(wall*.73,stone,cap),depth),max(footing.a,depth));
    }
    return footing;
}
vec4 brokenRotunda(vec2 p,float t){
    vec2 s=p*vec2(880.,376.);
    if(s.x<224.||s.x>435.||s.y<204.||s.y>311.)return vec4(0.);
    float n=stoneNoise(s);
    vec4 base=rotundaFooting(s,n);
    if(s.x<249.||s.x>408.||s.y>284.)return base;
    // Backlit holes between surviving sheets can expose the water above the crown.
    float shell=max(
        rotundaOutline(s,vec2[8](vec2(253,252),vec2(269,234),vec2(288,220),vec2(307,211),
                          vec2(323,210),vec2(347,215),vec2(357,272),vec2(290,278))),
        rotundaOutline(s,vec2[8](vec2(315,219),vec2(329,211),vec2(344,210.6),vec2(367,214),
                          vec2(386,225),vec2(402,244),vec2(393,268),vec2(320,281))));
    float crown=max(
        rotundaOutline(s,vec2[8](vec2(298,217),vec2(310,210),vec2(314,210.8),vec2(318,208.7),
                          vec2(325,208.4),vec2(323,210.3),vec2(326,211.7),vec2(317,218))),
        rotundaOutline(s,vec2[8](vec2(326,214),vec2(329,208),vec2(335,207.8),vec2(338,209.6),
                          vec2(341,208.2),vec2(346,208.9),vec2(357,213),vec2(343,216))));
    shell=max(shell,crown);
    float opening=(stoneNoise(s*.94)-.55)*.72+shell;
    if(opening<-.7)return base;
    float facets=valueNoise(s*vec2(.17,.31));
    vec3 chamber=mix(vec3(.028,.052,.061),vec3(.104,.159,.184),.30*n+.40*facets);
    chamber+=vec3(.048,.080,.096)*exp(-length((s-vec2(337.,242.))/vec2(28.,12.)))*facets;
    float exitLight=1.-smoothstep(.0,4.3,shell);
    chamber+=vec3(.036,.064,.065)*exitLight*(.45+.55*n);
    if(s.y>235.)chamber=rotundaPile(chamber,s);
    if(s.y<233.&&s.x>308.&&s.x<357.){
        rotundaRubble(chamber,s,vec2(326,216.6),vec2(8.6,2.6),-.13,.83,11.);
        rotundaRubble(chamber,s,vec2(336.6,220),vec2(5.4,2.9),.21,.61,13.);
        rotundaRubble(chamber,s,vec2(345.1,220.5),vec2(6.2,2.9),-.51,.93,21.);
        rotundaRubble(chamber,s,vec2(350.9,218.8),vec2(3.6,2.1),-.46,.76,17.);
        rotundaRubble(chamber,s,vec2(332,227.9),vec2(5.7,1.5),.21,.46,29.);
    }
    vec2 bounce=(s-vec2(334.,250.))/vec2(30.,20.);
    float exposed=.44+.56*smoothstep(.047,.144,dot(chamber,vec3(.213,.715,.072)));
    chamber+=vec3(.056,.071,.082)*exp(-dot(bounce,bounce))*exposed;
    if(s.x<323.){
        rotundaShard(chamber,s,vec2[8](vec2(273.4,246.3),vec2(280.7,235.4),vec2(287.3,232.5),vec2(284.4,237.8),
            vec2(281.6,239.3),vec2(282.0,240.6),vec2(277.3,244.6),vec2(274.5,248.5)),.30,.78,10.);
        rotundaShard(chamber,s,vec2[8](vec2(254.9,255),vec2(266.1,237.4),vec2(280,226.9),vec2(297.5,218.2),
            vec2(299,222.0),vec2(286.4,229.2),vec2(272.4,243.7),vec2(263.5,261.4)),.74,.86,6.);
        rotundaShard(chamber,s,vec2[8](vec2(266.1,258.8),vec2(276.8,240.6),vec2(292.1,228.4),vec2(305.4,220.8),
            vec2(311.4,220.4),vec2(303.8,227.5),vec2(287.9,241.1),vec2(274.8,263.9)),.76,.60,13.);
        rotundaShard(chamber,s,vec2[8](vec2(283.6,249.7),vec2(294.3,233.3),vec2(302.7,228.6),vec2(307.8,231.1),
            vec2(305.9,233),vec2(305.3,236.5),vec2(301,241.6),vec2(297.1,248.1)),.98,.15,18.);
        rotundaShard(chamber,s,vec2[8](vec2(278.7,263.2),vec2(286,251.1),vec2(291.1,249.9),vec2(295.4,251.3),
            vec2(292.8,254.4),vec2(290.9,255.3),vec2(286.3,259),vec2(285.1,264.4)),.54,.53,21.);
        rotundaShard(chamber,s,vec2[8](vec2(290.9,251),vec2(297.4,251.8),vec2(300.4,254),vec2(305.7,255.4),
            vec2(313.7,259.8),vec2(309.7,260.6),vec2(299.7,267.1),vec2(292.9,267.8)),.36,.44,29.);
        rotundaShard(chamber,s,vec2[8](vec2(289.5,224.5),vec2(299.3,216.9),vec2(308.7,212.6),vec2(310.6,214.1),
            vec2(306,215.7),vec2(305.5,218.3),vec2(299.5,220.7),vec2(296.4,222.5)),.82,.43,34.);
        rotundaShard(chamber,s,vec2[8](vec2(305.9,214.1),vec2(309.9,211.8),vec2(314.2,211.9),vec2(316.8,210.7),
            vec2(319.1,211.4),vec2(316.1,214.0),vec2(311.4,214.4),vec2(309.4,215.5)),.55,.58,31.);
        rotundaRib(chamber,s,vec2(258,251.6),vec2(268.8,237.3),vec2(279.6,228.4),vec2(291.5,221.6),vec2(.65,.44),.61,2.);
        rotundaRib(chamber,s,vec2(270.2,257.4),vec2(280.8,241.4),vec2(289.2,233.6),vec2(298.4,226.7),vec2(.86,.50),.70,3.);
        rotundaRib(chamber,s,vec2(298.4,224.8),vec2(297.2,222.3),vec2(297.4,218.3),vec2(300,215.4),vec2(.59,.39),.65,5.);
        rotundaRib(chamber,s,vec2(278.2,266.4),vec2(287.7,268.9),vec2(294.3,270.4),vec2(300.8,270.7),vec2(.53,.40),.55,6.);
        rotundaRib(chamber,s,vec2(298.2,252.2),vec2(303.8,256.2),vec2(309.5,258.1),vec2(313.7,259.7),vec2(.36,.49),.78,7.);
    }
    if(s.x>346.){
        rotundaShard(chamber,s,vec2[8](vec2(369.7,237.9),vec2(378.2,233.0),vec2(384.1,237.2),vec2(382.4,240.4),
            vec2(378.4,241.3),vec2(376.4,244.1),vec2(373.9,244.9),vec2(372.0,242.3)),.26,.69,39.);
        rotundaShard(chamber,s,vec2[8](vec2(350,212.1),vec2(368.8,216.1),vec2(385,224.1),vec2(395.6,236.1),
            vec2(399.9,244),vec2(398.6,248.8),vec2(393.8,242.5),vec2(372.2,224.6)),.57,.72,33.);
        rotundaShard(chamber,s,vec2[8](vec2(349.2,226.7),vec2(357.2,220.8),vec2(366.3,222.7),vec2(376.9,229.5),
            vec2(382.8,235.4),vec2(380.8,239.2),vec2(370.1,245.6),vec2(360.1,232.9)),.72,.49,41.);
        rotundaShard(chamber,s,vec2[8](vec2(371.4,245.7),vec2(377.6,242.7),vec2(382.5,238.8),vec2(386.7,239.2),
            vec2(393.6,247.1),vec2(389.4,253.4),vec2(386.3,259.),vec2(377.2,262.4)),.49,.44,44.);
        rotundaShard(chamber,s,vec2[8](vec2(356.7,220.6),vec2(362.1,218.5),vec2(370.2,221.2),vec2(378.2,226.6),
            vec2(375.7,229.6),vec2(378.,232.7),vec2(371.6,231.1),vec2(363.9,224.1)),.64,.72,46.);
        rotundaShard(chamber,s,vec2[8](vec2(382.1,227.6),vec2(389.0,233.1),vec2(395.4,240.1),vec2(398.7,247.6),
            vec2(395.2,254.9),vec2(392.4,254.7),vec2(390.8,244.5),vec2(380.4,231.3)),.50,.61,53.);
        rotundaRib(chamber,s,vec2(348.5,226.2),vec2(356.6,228.8),vec2(363.7,236.7),vec2(370.4,246.6),vec2(.68,.81),.68,9.);
        rotundaRib(chamber,s,vec2(371.4,248.2),vec2(374.6,253.1),vec2(377.9,261.3),vec2(378.7,266.),vec2(.72,.49),.54,10.);
        rotundaRib(chamber,s,vec2(380.1,224.6),vec2(389.9,233.1),vec2(397.2,241.9),vec2(399.7,250.1),vec2(.45,.78),.73,11.);
        rotundaRib(chamber,s,vec2(400.0,244.0),vec2(401.1,250.2),vec2(397.6,257.2),vec2(392.7,260.8),vec2(.54,.62),.66,12.);
    }
    rotundaRib(chamber,s,vec2(298.4,226.2),vec2(306.9,228.9),vec2(315.3,230.1),vec2(325.7,230.9),vec2(.70,.54),.94,16.);
    rotundaRib(chamber,s,vec2(319.75,230.5),vec2(318.3,235.2),vec2(316.7,240.3),vec2(315.6,244.),vec2(1.26,1.14),.94,17.);
    rotundaRib(chamber,s,vec2(315.4,244.8),vec2(314.1,250.1),vec2(312.5,256.2),vec2(310.8,263.2),vec2(1.07,.66),.75,18.);
    rotundaRib(chamber,s,vec2(330.3,233.4),vec2(335.7,233.1),vec2(341.5,233.5),vec2(347.1,233.7),vec2(.42,.55),.61,20.);
    rotundaRib(chamber,s,vec2(328,209.3),vec2(335.5,207.9),vec2(343.7,208.4),vec2(350.7,209.8),vec2(.46,.63),.86,22.);
    rotundaRib(chamber,s,vec2(352.1,210.5),vec2(361,212.1),vec2(371.8,215.7),vec2(381.4,221.2),vec2(.46,.42),.73,23.);
    rotundaRib(chamber,s,vec2(253.2,252.9),vec2(253.6,258.4),vec2(257.2,263.3),vec2(263.7,267.7),vec2(1.05,.65),.76,25.);

    // Front collar shows lifted joints, a chipped top edge and a lower threaded rail.
    vec2 collar=s-vec2(328.1,248.7);
    collar.y+=collar.x*.062;
    float rc=length(collar/vec2(77.1,31.7));
    float theta=atan(collar.y,collar.x);
    float rim=rc+(n-.51)*.017;
    float brokenLip=smoothstep(.47,.79,valueNoise(s*vec2(.53,.29)))*.042;
    vec2 sunk=(s-vec2(336.9,272.6))/vec2(7.2,3.0);
    brokenLip+=.088*exp(-dot(sunk,sunk)*1.45);
    float band=(1.-smoothstep(.998,1.024,rim))*smoothstep(.85,.89,rim-brokenLip)*smoothstep(247.,253.,s.y);
    float joint=exp(-abs(fract(theta*9.9+.19)-.5)*18.);
    vec3 collarColor=mix(vec3(.064,.103,.114),vec3(.265,.316,.297),n);
    float wear=valueNoise(s*vec2(.61,.34));
    collarColor*=1.-.42*joint-.23*smoothstep(.53,.82,wear);
    collarColor+=vec3(.35,.294,.21)*(exp(-abs(rim-.960)*162.)*.64+exp(-abs(rim-.882-brokenLip)*141.)*.79)*(.34+.66*n);
    collarColor+=vec3(.101,.166,.189)*exp(-abs(rim-1.)*145.)*(.52+.48*wear);
    chamber=mix(chamber,collarColor,band);
    float opacity=smoothstep(-.43,.42,opening);
    return vec4(mix(base.rgb,chamber,opacity),max(opacity,base.a));
}

// Hand-placed projection of masonry, carved stone, and oxidized copper.
float ctHash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float ctNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(ctHash(i), ctHash(i + vec2(1, 0)), u.x),
               mix(ctHash(i + vec2(0, 1)), ctHash(i + 1.0), u.x), u.y);
}

float ctStoneNoise(vec2 p) {
    return 0.46 * ctNoise(p * 0.069)
        + 0.29 * ctNoise(p * vec2(0.23, 0.32))
        + 0.17 * ctNoise(p * 0.75)
        + 0.08 * ctHash(floor(p * 2.0));
}

float ctSquare(float x) {
    return x * x;
}

float ctCross(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

bool ctBounds(vec2 p, vec2 lo, vec2 hi) {
    return all(greaterThanEqual(p, lo)) && all(lessThanEqual(p, hi));
}

float ctRamp(float x, float width) {
    return smoothstep(-width, width, x);
}

void ctPut(inout vec4 layer, vec3 color, float opacity) {
    layer = vec4(mix(layer.rgb, color, opacity), mix(layer.a, 1.0, opacity));
}

vec3 ctMasonry(vec2 p, vec2 tiles, float light, float haze) {
    vec2 tile = floor(tiles + vec2(0.50 * mod(floor(tiles.y), 2.0), 0));
    vec2 joint = fract(tiles + vec2(0.50 * mod(tile.y, 2.0), 0));
    float grain = ctStoneNoise(p);
    float seam = min(min(joint.x, 1.0 - joint.x) * 1.7, min(joint.y, 1.0 - joint.y));
    float chip = 0.04 * ctNoise(p * 0.28);
    float bed = mix(0.53, 1.0, smoothstep(0.012, 0.075, seam + chip));
    float glint = (1.0 - smoothstep(0.015, 0.105, joint.y)) * 0.13;
    float block = 0.72 + 0.36 * ctHash(tile + 71.31);
    float shade = (0.48 + grain * 0.88) * bed * block;
    vec3 face = mix(vec3(0.153, 0.232, 0.226), vec3(0.685, 0.649, 0.543), light);
    face *= shade;
    face += glint * vec3(0.40, 0.43, 0.37) * light;
    float patina = smoothstep(0.49, 0.75, ctNoise(p * vec2(0.08, 0.027))) * 0.55;
    face = mix(face, vec3(0.102, 0.174, 0.151) * (0.85 + grain * 0.5), patina);
    return mix(face, vec3(0.097, 0.288, 0.355), haze);
}

vec2 ctQuadUV(vec2 p, vec2 a, vec2 b, vec2 d) {
    vec2 ab = b - a;
    vec2 ad = d - a;
    float det = ctCross(ab, ad);
    if (abs(det) < 0.002) return vec2(-2.0);
    return vec2(ctCross(p - a, ad), ctCross(ab, p - a)) / det;
}

// Invert the planar projective map of all four corners. Fronts, return
// walls and sloping floors share their boundary edges in image space.
vec2 ctProjectedUV(vec2 p,vec2 a,vec2 b,vec2 c,vec2 d){
    vec2 bx=b-c,dy=d-c,k=a+c-b-d;
    float det=ctCross(bx,dy);
    if(abs(det)<.01)return ctQuadUV(p,a,b,d);
    float g=ctCross(k,dy)/det,h=ctCross(bx,k)/det;
    // A triangle encoded with a midpoint on one edge has no invertible
    // quadrilateral homography. Its remaining three corners define the face.
    if(min(min(abs(1.+g),abs(1.+h)),abs(1.+g+h))<.0001)
        return ctQuadUV(p,a,b,d);
    vec2 u=b-a+g*(b-p),v=d-a+h*(d-p);
    float area=ctCross(u,v);
    if(abs(area)<.01)return ctQuadUV(p,a,b,d);
    return vec2(ctCross(p-a,v),ctCross(u,p-a))/area;
}
// Shared downward vertical convergence of the two flank buildings, estimated
// from their visible upright axes in the 1760 x 754 reference projection.
vec2 ctFlankFoot(vec2 top,float drop){
    return top+(vec2(865.,3150.)-top)*(drop/(3150.-top.y));
}

float ctQuadMask(vec2 p, vec2 a, vec2 b, vec2 c, vec2 d) {
    float s = sign(ctCross(b - a, d - a));
    float h = min(min(ctCross(b - a, p - a) / max(length(b - a), 0.01) * s,
                      ctCross(c - b, p - b) / max(length(c - b), 0.01) * s),
                  min(ctCross(d - c, p - c) / max(length(d - c), 0.01) * s,
                      ctCross(a - d, p - d) / max(length(a - d), 0.01) * s));
    return ctRamp(h, 0.72);
}

void ctPanel(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 c, vec2 d,
             vec2 blocks, float light, float haze) {
    if (!ctBounds(p, min(min(a, b), min(c, d)) - 1.0, max(max(a, b), max(c, d)) + 1.0)) return;
    float mask = ctQuadMask(p, a, b, c, d);
    if (mask <= 0.001) return;
    vec2 uv = ctProjectedUV(p, a, b, c, d);
    ctPut(layer, ctMasonry(p, uv * blocks, light, haze), mask);
}

void ctBand(inout vec4 layer, vec2 p, vec2 a, vec2 b, float h, float light, float haze) {
    if (!ctBounds(p, min(a, b) - 2.0, max(a, b) + vec2(2, h + 2.0))) return;
    vec2 down = vec2(0, h);
    float mask = ctQuadMask(p, a, b, b + down, a + down);
    if (mask <= 0.001) return;
    vec2 uv = ctQuadUV(p, a, b, a + down);
    vec3 rock = ctMasonry(p, uv * vec2(length(b - a) / 14.0, 2.0), light, haze);
    float profile = 0.67 + 0.44 * exp(-ctSquare((uv.y - 0.17) * 10.0))
        + 0.25 * exp(-ctSquare((uv.y - 0.70) * 12.0));
    float triglyphs = fract(uv.x * length(b - a) / max(3.5, h * 0.65));
    float carvings = smoothstep(0.29, 0.38, triglyphs) * (1.0 - smoothstep(0.63, 0.79, triglyphs));
    rock *= profile * (1.0 - carvings * smoothstep(0.27, 0.33, uv.y) * (1.0 - smoothstep(0.55, 0.65, uv.y)) * 0.28);
    ctPut(layer, rock, mask);
}

void ctColumn(inout vec4 layer, vec2 p, vec2 a, vec2 b, float width, float light, float haze, float seed) {
    if (!ctBounds(p, min(a, b) - vec2(width * 1.15 + 1.0, 2.0),
                      max(a, b) + vec2(width * 1.15 + 1.0, 2.0))) return;
    vec2 axis = b - a;
    float columnLength = length(axis);
    vec2 dir = axis / max(columnLength, 0.1);
    vec2 normal = vec2(dir.y, -dir.x);
    vec2 v = p - a;
    float y = dot(v, dir);
    float u = clamp(y / columnLength, 0.0, 1.0);
    float dx = dot(v, normal);
    float cap = 1.0 - smoothstep(0.045, 0.142, u);
    float plinth = smoothstep(0.84, 0.973, u);
    float shaft = 0.59 + 0.12 * u + 0.32 * cap + 0.28 * plinth;
    float rough = ctNoise(p * 0.25 + seed) * 0.45 + ctNoise(p * vec2(0.13, 0.038) + seed) * 0.47;
    float mask = ctRamp(min(min(y, columnLength - y), width * shaft - abs(dx) + rough - 0.56), 0.64);
    if (mask <= 0.001) return;
    float cyl = clamp(dx / max(width * shaft, 0.05), -0.999, 0.999);
    float theta = asin(cyl);
    float falloff = 0.37 + 0.68 * max(0.0, cos(theta + 0.46));
    float flute = 0.69 + 0.31 * pow(0.5 + 0.5 * cos(theta * 14.0 + seed), 0.54);
    float texture = ctStoneNoise(p + seed * 3.1);
    float seams = smoothstep(0.045, 0.15, fract(u * (2.0 + floor(columnLength / 18.0))));
    float rim = max(cap, plinth);
    float grooves = 0.73 + 0.27 * cos(y * (0.49 + 1.4 / max(width, 1.0))) * cos(y * 0.29);
    float patina = smoothstep(0.42, 0.74, ctNoise(p * vec2(0.19, 0.041) + seed)) * 0.52;
    vec3 color = mix(vec3(0.149, 0.224, 0.218), vec3(0.734, 0.700, 0.601), light);
    color *= falloff * mix(flute * mix(0.62, 1.0, seams), grooves, rim) * (0.55 + 0.83 * texture);
    color = mix(color, vec3(0.127, 0.198, 0.155) * (0.52 + 0.52 * texture), patina);
    color += vec3(0.17, 0.115, 0.064) * rim * smoothstep(0.43, 0.78, rough) * light;
    ctPut(layer, mix(color, vec3(0.094, 0.282, 0.347), haze), mask);
}

void ctColonnade(inout vec4 layer, vec2 p, vec2 a, vec2 b, float dropA, float dropB,
                int count, float width, float light, float haze) {
    vec2 c = ctFlankFoot(b,dropB);
    vec2 d = ctFlankFoot(a,dropA);
    if (!ctBounds(p, min(min(a, b), min(c, d)) - vec2(width + 3.0), max(max(a, b), max(c, d)) + vec2(width + 16.0))) return;
    vec2 depthShift = vec2(3, -3);
    ctPanel(layer, p, a + depthShift, b + depthShift, c + depthShift, d + depthShift,
            vec2(float(count) * 2.5, 6), light * 0.17, haze * 0.85);
    vec2 uv = ctProjectedUV(p, a, b, c, d);
    if (all(greaterThanEqual(uv, vec2(0.0, 0.02))) && all(lessThanEqual(uv, vec2(1, 0.985)))) {
        float brick = fract(uv.x * float(count - 1));
        float arch = 0.21 + pow(abs(brick * 2.0 - 1.0), 2.2) * 0.36;
        float hole = ctRamp(0.36 - abs(brick - 0.5), 0.025) * ctRamp(uv.y - arch, 0.033);
        vec3 interior = mix(vec3(0.034, 0.088, 0.101), vec3(0.099, 0.278, 0.337), haze);
        ctPut(layer, interior * (0.66 + 0.34 * ctNoise(p * 0.12)), hole * 0.88);
        float glow = exp(-ctSquare((brick - 0.48) * 12.6) - ctSquare((uv.y - 0.76) * 12.0));
        float pin = step(0.68, ctHash(vec2(floor(uv.x * float(count - 1)), floor(a.x)))) * glow;
        ctPut(layer, interior + vec3(0.064, 0.59, 0.60) * glow, pin * (1.0 - haze) * 0.83);
    }
    for (int i = 0; i < 12; ++i) {
        if (i >= count) break;
        float u = float(i) / float(count - 1);
        float projected=u*dropA/mix(dropB,dropA,u);
        vec2 top = mix(a, b, projected);
        vec2 foot = mix(d, c, projected);
        ctColumn(layer, p, top, foot, width * (0.92 + 0.14 * u), light, haze, float(i) + a.x);
    }
    ctBand(layer, p, d - vec2(3, 4), c + vec2(3, -4), 6.0 + width * 0.38, light * 0.79, haze);
    ctBand(layer, p, a - vec2(5, 5), b + vec2(5, -5), 6.0 + width * 0.58, light, haze);
}

void ctRoof(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 c, vec2 d, float height, float light, float haze) {
    vec2 rise = vec2(0, -height);
    vec2 midpoint = (a + b) * 0.5 + rise;
    vec2 ridge = (d + c) * 0.5 + rise;
    ctPanel(layer, p, a, midpoint, ridge, d, vec2(3, 6), light * 0.81, haze);
    ctPanel(layer, p, midpoint, b, c, ridge, vec2(3, 7), light * 0.56, haze);
    ctPanel(layer, p, midpoint, b, (a + b) * 0.5, a, vec2(9, 2), light, haze);
}

void ctDome(inout vec4 layer, vec2 p, vec2 center, vec2 radius, float tilt, float light, float haze) {
    if (!ctBounds(p, center - radius - vec2(1, abs(tilt) + 5.0), center + vec2(radius.x + 1.0, 0.40 * radius.y + abs(tilt) + 14.0))) return;
    vec2 q = (p - center) / radius;
    q.y -= q.x * tilt / radius.y;
    float rim = 0.26 * sqrt(max(0.0, 1.0 - q.x * q.x));
    float d = max(length(vec2(q.x, min(q.y, 0.0))) - 1.0, q.y - rim - 0.07);
    float mask = 1.0 - smoothstep(-0.022, 0.022, d);
    if (mask <= 0.001) return;
    float sphere = sqrt(max(0.001, 1.0 - q.x * q.x - min(q.y, 0.0) * min(q.y, 0.0)));
    vec3 normal = normalize(vec3(q.x, -q.y, sphere));
    float lambert = 0.17 + 0.81 * max(0.0, dot(normal, normalize(vec3(-0.52, 0.57, 0.61))));
    float reflected = pow(max(0.0, dot(normal, normalize(vec3(-0.46, 0.48, 0.81)))), 33.0);
    float meridian = atan(q.x, max(0.028, sphere));
    float seam = 1.0 - smoothstep(0.055, 0.21, abs(sin(meridian * 7.1)));
    float ring = 1.0 - smoothstep(0.04, 0.12, abs(sin(q.y * 8.3 + sphere * 1.5)));
    float grit = ctStoneNoise(p + 32.1);
    float rust = ctNoise(p * 0.15) * 0.66 + ctNoise(p * 0.042) * 0.34;
    vec3 copper = mix(vec3(0.105, 0.180, 0.161), vec3(0.605, 0.399, 0.237), smoothstep(0.34, 0.74, rust));
    vec3 color = copper * lambert * (0.59 + 0.80 * grit) * (0.83 + 0.17 * light);
    color *= 0.85 + 0.27 * ring + 0.28 * seam;
    color += vec3(0.62, 0.37, 0.18) * reflected * (0.37 + grit * 0.71) * light;
    color = mix(color, vec3(0.077, 0.177, 0.186), smoothstep(rim - 0.022, rim + 0.07, q.y) * 0.65);
    float lip = exp(-ctSquare((q.y - rim + 0.018) * 37.0));
    color += vec3(0.44, 0.38, 0.25) * lip * light;
    ctPut(layer, mix(color, vec3(0.095, 0.283, 0.347), haze), mask);
    vec2 knob = center - vec2(0, radius.y);
    ctColumn(layer, p, knob - vec2(0, radius.y * 0.12), knob + vec2(0, 1.1), max(1.2, radius.x * 0.051), light * 0.85, haze, 18.0);
}

void ctRotunda(inout vec4 layer, vec2 p, vec2 center, vec2 roof, float height,
               float tilt, float light, float haze) {
    if (!ctBounds(p, center - vec2(roof.x + 8.0, roof.y + 5.0), center + vec2(roof.x + 8.0, height + tilt + 24.0))) return;
    vec2 a = center + vec2(-roof.x * 0.90, -tilt);
    vec2 b = center + vec2(roof.x * 0.90, tilt);
    vec2 down = vec2(-0.055 * height, height);
    ctPanel(layer, p, a, b, b + down, a + down, vec2(12, 7), light * 0.19, haze);
    for (int i = 0; i < 7; ++i) {
        float angle = (float(i) / 6.0 - 0.5) * 2.60;
        float x = sin(angle);
        float h = cos(angle) * roof.y * 0.26;
        vec2 top = center + vec2(x * roof.x * 0.945, h + x * tilt);
        vec2 e = top + down * (0.92 + 0.09 * cos(angle));
        ctColumn(layer, p, top, e, roof.x * 0.081 * (0.68 + 0.32 * cos(angle)),
                 light * (0.95 - angle * 0.18), haze, float(i) * 1.8);
    }
    for (int i = 0; i < 8; ++i) {
        float ax = (float(i) / 8.0 - 0.5) * 2.84;
        float bx = (float(i + 1) / 8.0 - 0.5) * 2.84;
        vec2 left = center + vec2(sin(ax) * roof.x, cos(ax) * roof.y * 0.26 + sin(ax) * tilt);
        vec2 right = center + vec2(sin(bx) * roof.x, cos(bx) * roof.y * 0.26 + sin(bx) * tilt);
        ctBand(layer, p, left, right, max(3.2, roof.x * 0.113), light * (0.91 - ax * 0.16), haze);
        ctBand(layer, p, left + down, right + down, max(2.6, roof.x * 0.065), light * 0.51, haze);
    }
    ctDome(layer, p, center, roof, tilt, light, haze);
}

void ctStairs(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 c, vec2 d, float light, float haze) {
    if (!ctBounds(p, min(min(a, b), min(c, d)) - 2.0, max(max(a, b), max(c, d)) + vec2(5, 10))) return;
    vec2 low = vec2(3, 8);
    vec2 upperDrop = vec2(2, min(34.0, length(c - b) * 0.21));
    ctPanel(layer, p, d, c, c + low, d + low, vec2(8, 2), light * 0.70, haze);
    ctPanel(layer, p, b, c, c + low, b + upperDrop, vec2(11, 3.3), light * 0.32, haze);
    float mask = ctQuadMask(p, a, b, c, d);
    if (mask <= 0.001) return;
    float fromTop = ctCross(normalize(b - a), p - a);
    float fromFoot = ctCross(normalize(c - d), d - p);
    float depth = clamp(fromTop / max(abs(fromTop + fromFoot), 0.01), 0.0, 1.0);
    vec2 left = mix(a, d, depth);
    vec2 span = mix(b - a, c - d, depth);
    float across = clamp(dot(p - left, span) / dot(span, span), 0.0, 1.0);
    float stepCount = max(3.0, floor(length((d + c - a - b) * 0.5) / 5.3));
    float stepPosition = fract(depth * stepCount);
    float riser = smoothstep(0.56, 0.75, stepPosition);
    float lip = exp(-ctSquare((stepPosition - 0.56) * 10.5));
    float edging = 1.0 - smoothstep(0.080, 0.115, min(across, 1.0 - across));
    float grain = ctStoneNoise(p);
    float course = ctHash(vec2(floor(depth * stepCount), floor(a.x)));
    vec3 stone = mix(vec3(0.17, 0.26, 0.26), vec3(0.75, 0.71, 0.60), light);
    stone *= (0.77 + 0.40 * grain + 0.12 * course) * (0.99 - 0.39 * riser + 0.30 * lip);
    vec3 curb = ctMasonry(p, vec2(across * 2.0 + 0.2, depth * stepCount * 0.52), light * 0.96, haze);
    stone = mix(mix(stone * .79, vec3(0.097, 0.288, 0.355), haze), curb * .96, edging);
    ctPut(layer, stone, mask);
}

void ctObelisk(inout vec4 layer, vec2 p, vec2 a, vec2 b, float width, float light, float haze) {
    if (!ctBounds(p, min(a, b) - vec2(width * 1.8 + 2.0, width * 1.5), max(a, b) + vec2(width * 1.8 + 2.0, 12))) return;
    vec2 waxis = normalize(vec2(b.y - a.y, a.x - b.x));
    vec2 aa = a - waxis * width * 0.59;
    vec2 ab = a + waxis * width * 0.38;
    vec2 ba = b - waxis * width;
    vec2 bb = b + waxis * width * 0.50;
    vec2 depth = vec2(width * 0.58, -width * 0.28);
    ctPanel(layer, p, ab, ab + depth, bb + depth, bb, vec2(1, 9), light * 0.38, haze);
    ctPanel(layer, p, aa, ab, bb, ba, vec2(1, 11), light, haze);
    vec2 peak = a - vec2(-width * 0.08, width * 1.10);
    ctPanel(layer, p, peak, ab + depth, ab, aa, vec2(1.5, 1.0), light * 0.88, haze);
    ctBand(layer, p, ba - vec2(3, 0), bb + depth + vec2(2, 0), width * 0.32, light * 0.92, haze);
    vec2 uv = ctQuadUV(p, aa, ab, ba);
    if (ctQuadMask(p, aa, ab, bb, ba) < 0.98) return;
    float u = clamp(uv.y, 0.0, 1.0);
    uv.x = (uv.x + 0.33 * u) / (1.0 + 0.54 * u);
    vec2 q = vec2((uv.x - 0.50) * 2.8, fract(uv.y * 8.5) * 2.0 - 1.0);
    float digit = floor(uv.y * 8.5);
    float notch = mix(abs(q.x + q.y * 0.50), abs(q.x - q.y * 0.53), step(0.0, q.y));
    notch = min(notch, abs(abs(q.y - 0.1) - 0.52) + 0.12 * abs(q.x));
    float border = abs(abs(q.x) - 0.97);
    float glyph = max(1.0 - smoothstep(0.08, 0.21, min(notch, border)), 0.0)
                  * (1.0 - smoothstep(0.50, 0.65, abs(q.x))) * (1.0 - smoothstep(0.73, 0.92, abs(q.y)));
    glyph *= step(0.05, ctHash(vec2(digit, a.x)));
    ctPut(layer, mix(vec3(0.185, 0.150, 0.099), vec3(0.10, 0.28, 0.34), haze), glyph * 0.58);
}

void ctCoralCoil(inout vec4 layer, vec2 p, vec2 top, vec2 foot, float radius) {
    if (!ctBounds(p, min(top, foot) - vec2(radius * 1.7), max(top, foot) + vec2(radius * 1.7))) return;
    float y = (p.y - top.y) / (foot.y - top.y);
    float turn = y * 15.2;
    float side = sin(turn);
    float x = mix(top.x, foot.x, y) + radius * side;
    float spread = (0.96 + 0.45 * y) * (0.74 + 0.28 * cos(turn));
    float fronds = ctNoise(p * 0.37) * 0.56 + ctHash(floor(p * 0.91)) * 0.44;
    float distance = abs(p.x - x) - (5.0 + fronds * 11.0) * spread;
    float fade = ctRamp(min(y - 0.14, 0.98 - y), 0.025);
    float facesFront = smoothstep(-0.18, 0.26, cos(turn));
    float mask = (1.0 - smoothstep(-1.0, 1.0, distance)) * fade *
                 max(facesFront, step(radius * 0.63, abs(p.x - mix(top.x, foot.x, y))));
    vec3 rust = mix(vec3(0.208, 0.071, 0.041), vec3(0.80, 0.307, 0.169), pow(fronds, 1.8));
    ctPut(layer, rust * (0.88 + 0.27 * facesFront), mask);
}

vec3 ctDistrictStone(vec2 p, vec2 tile, float light, float haze) {
    vec3 stone = ctMasonry(p, tile, light, haze * 0.70);
    float erosion = ctNoise(p * vec2(0.095, 0.041));
    float silt = smoothstep(0.35, 0.76, erosion * 0.65 + 0.35 * ctStoneNoise(p * 1.2));
    stone = mix(stone, vec3(0.045, 0.103, 0.105), silt * 0.57);
    return mix(stone, vec3(0.062, 0.20, 0.254), haze * 0.53);
}

void ctDistrictTerrace(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 back,
                       float height, float light, float haze) {
    vec2 down = ctFlankFoot((a+b)*.5,height)-(a+b)*.5;
    vec2 lo = min(min(a, b), min(a + back, b + back)) - vec2(17, 6);
    vec2 hi = max(max(a, b), max(a + back, b + back)) + vec2(8, height + 17.0);
    if (!ctBounds(p, lo, hi)) return;
    float span = length(b - a);
    float side = sign(back.x);
    vec2 outer = side > 0.0 ? b : a;
    vec2 jag = vec2(ctNoise(p * vec2(0.17, 0.11)) - 0.5,
                    ctNoise(p * vec2(0.091, 0.37) + a.x) - 0.5) * 7.0;
    ctPanel(layer, p + jag, outer, outer + back, outer + back + down * 0.66, outer + down,
            vec2(4.5, height / 6.5), light * 0.35, haze);
    vec2 q = ctQuadUV(p, a, b, a + down);
    float taper = ctNoise(vec2(p.x * 0.033, a.y * 0.14));
    float wall = ctQuadMask(p + jag, a, b, b + down * (0.68 + 0.44 * taper), a + down * (0.56 + 0.45 * taper));
    if (wall > 0.002) {
        vec3 stone = ctDistrictStone(p, q * vec2(span / 15.0, height / 7.0), light * 0.46, haze);
        float courses = smoothstep(0.04, 0.15, fract(q.y * height / 8.3));
        float undercut = smoothstep(0.07, 0.39, q.y) * (1.0 - smoothstep(0.50, 0.97, q.y));
        float vertical = ctNoise(p * vec2(0.22, 0.035));
        stone *= (0.74 + 0.26 * courses) * (1.0 - undercut * (0.14 + 0.34 * vertical));
        ctPut(layer, stone, wall * (1.0 - smoothstep(0.48 + 0.12 * taper, 0.97, q.y) * 0.82));
    }
    float mask = ctQuadMask(p + jag * 0.59, a + back, b + back, b, a);
    if (mask < 0.001) return;
    vec2 uv = ctQuadUV(p, a + back, b + back, a);
    vec3 stone = ctDistrictStone(p, uv * vec2(span / 11.0, 3.0), light, haze);
    float paving = abs(fract(uv.y * 2.4 + 0.18) - 0.5);
    float edge = (1.0 - smoothstep(0.08, 0.27, abs(uv.y - 0.89))) * (0.50 + 0.50 * taper);
    stone += vec3(0.079, 0.095, 0.082) * edge * light;
    stone *= 0.86 + 0.14 * smoothstep(0.03, 0.15, paving);
    ctPut(layer, stone, mask * (0.73 + 0.25 * taper));
}

void ctDistrictRuin(inout vec4 layer, vec2 p, vec2 base, vec2 size, float slope,
                    float kind, float light, float haze) {
    if (!ctBounds(p, base - vec2(size.x * 0.66 + 8.0, size.y * 1.58 + 15.0),
                      base + vec2(size.x * 0.93 + 10.0, 18.0))) return;
    vec2 a = base + vec2(-size.x * 0.53, -size.y);
    vec2 b = base + vec2(size.x * 0.47, -size.y + slope);
    vec2 depth = vec2(size.x * 0.32, -size.y * 0.31);
    vec2 c = ctFlankFoot(b,size.y);
    vec2 d = ctFlankFoot(a,size.y);
    float seed = base.x + base.y;
    float damage = ctHash(base * 0.127);
    if (kind > 2.5) {
        ctRotunda(layer, p, vec2(base.x, base.y - size.y), vec2(size.x * 0.49, size.y * 0.41),
                  size.y, slope * 0.35, light * 0.82, haze);
        return;
    }
    ctDistrictTerrace(layer, p, d + vec2(-5, 6), c + vec2(13, 4), depth * 0.86, 13.0, light * 0.75, haze);
    if (kind < 0.5) {
        vec2 q = ctQuadUV(p, a, b, d);
        float roofline = 0.07 + 0.38 * ctNoise(vec2(p.x * 0.098, seed)) +
                         0.13 * ctHash(vec2(floor(p.x * 0.24), seed));
        float mask = ctQuadMask(p, a, b, c, d) * smoothstep(roofline, roofline + 0.05, q.y);
        if (mask > 0.001) {
            vec3 stone = ctDistrictStone(p, q * vec2(size.x / 11.0, size.y / 5.9), light * 0.75, haze);
            ctPut(layer, stone, mask);
        }
        ctColumn(layer, p, mix(a, b, 0.27) - vec2(0, size.y * 0.16), mix(d, c, 0.27), 2.6, light, haze, seed);
        ctColumn(layer, p, mix(a, b, 0.79) + vec2(2, size.y * 0.28), mix(d, c, 0.79), 3.35, light * 0.80, haze, seed + 8.0);
        return;
    }
    vec2 q = ctQuadUV(p, a, b, d);
    float span = kind < 1.5 ? 0.60 + 0.20 * damage : 1.0;
    vec2 end = mix(a, b, span);
    vec2 endFoot = mix(d, c, span);
    ctPanel(layer, p, end, end + depth, endFoot + depth, endFoot,
            vec2(3.5, size.y / 7.0), light * 0.28, haze);
    float mask = ctQuadMask(p, a, end, endFoot, d);
    if (mask > 0.001) {
        float bays = max(2.0, floor(size.x / 13.0));
        vec3 stone = ctDistrictStone(p, q * vec2(bays * 2.0, size.y / 6.0), light * 0.49, haze);
        float local = (fract(q.x * bays) - 0.5) * 2.0;
        float vault = length(vec2(local * 1.33, min(0.0, q.y * 3.56 - 1.54)));
        float opening = (1.0 - smoothstep(0.89, 1.02, vault)) * (1.0 - smoothstep(0.88, 1.02, q.y));
        vec3 dark = mix(vec3(0.027, 0.077, 0.083), vec3(0.060, 0.186, 0.222), 0.65 * haze);
        ctPut(layer, mix(stone, dark, opening * (0.66 + 0.32 * ctNoise(p * 0.11))), mask);
        float pillar = floor(q.x * bays + 0.5);
        if (pillar / bays <= span) {
            float remaining = step(0.22, ctHash(vec2(pillar, seed)));
            vec2 start = mix(a, b, pillar / bays);
            start.y += (1.0 - remaining) * size.y * 0.47;
            ctColumn(layer, p, start, mix(d, c, pillar / bays), 1.6 + size.x * 0.023,
                     light * 0.83, haze, seed + pillar);
        }
    }
    ctBand(layer, p, a - vec2(4, 3), end + vec2(2, -2), 3.0 + size.y * 0.075, light * 0.86, haze);
    if (kind < 1.5) {
        ctPanel(layer, p, a - vec2(4, 4), end - vec2(0, 2), end + depth - vec2(4, 4),
                a + depth - vec2(3, 5), vec2(6, 2), light * 0.77, haze);
        ctColumn(layer, p, b + vec2(3, size.y * 0.36), c + vec2(1, 4), 2.1, light * 0.74, haze, seed);
    } else {
        ctRoof(layer, p, a - vec2(5, 4), b + vec2(4, -3), b + depth, a + depth - vec2(3, 4),
               size.y * 0.15, light * 0.87, haze);
    }
}

void ctFarDistrict(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(-15, 152), vec2(1775, 581))) return;

    // The far streets follow the two cliff shoulders and disappear behind the temple.
    ctDistrictTerrace(layer, p, vec2(-23, 253), vec2(244, 251), vec2(52, -19), 35.0, 0.36, 0.78);
    ctDistrictTerrace(layer, p, vec2(209, 252), vec2(406, 258), vec2(48, -17), 32.0, 0.37, 0.75);
    ctDistrictTerrace(layer, p, vec2(419, 263), vec2(634, 259), vec2(55, -11), 31.0, 0.45, 0.79);
    ctDistrictTerrace(layer, p, vec2(641, 263), vec2(932, 278), vec2(39, -15), 27.0, 0.45, 0.88);
    ctDistrictTerrace(layer, p, vec2(1189, 271), vec2(1485, 251), vec2(-37, -13), 33.0, 0.44, 0.78);
    ctDistrictTerrace(layer, p, vec2(1477, 248), vec2(1635, 229), vec2(-29, -23), 33.0, 0.41, 0.70);
    ctDistrictTerrace(layer, p, vec2(1604, 221), vec2(1779, 190), vec2(-19, -13), 34.0, 0.47, 0.65);
    ctDistrictRuin(layer, p, vec2(45, 245), vec2(49, 23), 1.5, 0.0, 0.36, 0.84);
    ctDistrictRuin(layer, p, vec2(162, 247), vec2(60, 25), -2.0, 1.0, 0.35, 0.84);
    ctDistrictRuin(layer, p, vec2(312, 249), vec2(38, 19), 3.5, 0.0, 0.39, 0.82);
    ctDistrictRuin(layer, p, vec2(375, 251), vec2(44, 18), -2.0, 1.0, 0.39, 0.82);
    ctDistrictRuin(layer, p, vec2(508, 252), vec2(60, 41), 3.0, 2.0, 0.43, 0.78);
    ctDistrictRuin(layer, p, vec2(697, 260), vec2(41, 20), 1.0, 0.0, 0.49, 0.89);
    ctDistrictRuin(layer, p, vec2(823, 269), vec2(52, 17), 2.0, 1.0, 0.51, 0.89);
    ctDistrictRuin(layer, p, vec2(1247, 259), vec2(49, 25), -1.0, 1.0, 0.43, 0.84);
    ctDistrictRuin(layer, p, vec2(1383, 255), vec2(42, 26), 4.0, 0.0, 0.44, 0.78);
    ctDistrictRuin(layer, p, vec2(1442, 242), vec2(28, 24), -2.0, 3.0, 0.53, 0.74);
    ctDistrictRuin(layer, p, vec2(1535, 230), vec2(37, 25), -2.0, 2.0, 0.48, 0.68);
    ctDistrictRuin(layer, p, vec2(1681, 204), vec2(51, 22), -2.0, 0.0, 0.44, 0.67);
    ctDistrictRuin(layer, p, vec2(1736, 198), vec2(55, 21), 2.0, 1.0, 0.60, 0.63);

    // Lower footings turn down toward the ravine and leave passages between blocks.
    ctDistrictTerrace(layer, p, vec2(-34, 311), vec2(195, 296), vec2(60, -22), 51.0, 0.47, 0.66);
    ctDistrictTerrace(layer, p, vec2(195, 297), vec2(343, 321), vec2(60, -22), 41.0, 0.49, 0.63);
    ctDistrictTerrace(layer, p, vec2(381, 314), vec2(550, 292), vec2(49, -23), 47.0, 0.55, 0.61);
    ctDistrictTerrace(layer, p, vec2(604, 334), vec2(826, 304), vec2(38, -27), 42.0, 0.55, 0.68);
    ctDistrictTerrace(layer, p, vec2(1270, 315), vec2(1484, 326), vec2(-53, -30), 41.0, 0.57, 0.62);
    ctDistrictTerrace(layer, p, vec2(1537, 300), vec2(1780, 262), vec2(-43, -27), 41.0, 0.55, 0.56);
    ctDistrictRuin(layer, p, vec2(98, 293), vec2(59, 18), -6.0, 0.0, 0.57, 0.63);
    ctDistrictRuin(layer, p, vec2(254, 303), vec2(111, 19), -5.0, 1.0, 0.61, 0.65);
    ctDistrictRuin(layer, p, vec2(450, 296), vec2(71, 36), -6.0, 1.0, 0.63, 0.60);
    ctDistrictRuin(layer, p, vec2(672, 313), vec2(45, 19), -2.0, 0.0, 0.60, 0.70);
    ctDistrictRuin(layer, p, vec2(741, 301), vec2(58, 23), -5.0, 1.0, 0.52, 0.71);
    ctDistrictRuin(layer, p, vec2(1314, 308), vec2(63, 27), 5.0, 0.0, 0.51, 0.64);
    ctDistrictRuin(layer, p, vec2(1411, 311), vec2(70, 26), 5.0, 2.0, 0.56, 0.58);
    ctDistrictRuin(layer, p, vec2(1557, 290), vec2(59, 34), -8.0, 1.0, 0.56, 0.57);
    ctDistrictRuin(layer, p, vec2(1732, 262), vec2(52, 27), -3.0, 0.0, 0.53, 0.49);

    ctDistrictTerrace(layer, p, vec2(-26, 394), vec2(97, 411), vec2(53, -31), 60.0, 0.54, 0.47);
    ctDistrictTerrace(layer, p, vec2(133, 419), vec2(254, 397), vec2(63, -25), 49.0, 0.53, 0.43);
    ctDistrictTerrace(layer, p, vec2(297, 468), vec2(367, 425), vec2(-28, -37), 55.0, 0.59, 0.38);
    ctDistrictTerrace(layer, p, vec2(402, 392), vec2(554, 365), vec2(56, -29), 52.0, 0.61, 0.47);
    ctDistrictTerrace(layer, p, vec2(1512, 408), vec2(1610, 380), vec2(-45, -39), 58.0, 0.57, 0.39);
    ctDistrictTerrace(layer, p, vec2(1650, 366), vec2(1796, 343), vec2(-32, -30), 73.0, 0.59, 0.40);
    ctDistrictRuin(layer, p, vec2(64, 388), vec2(64, 22), 5.0, 1.0, 0.60, 0.50);
    ctDistrictRuin(layer, p, vec2(390, 393), vec2(62, 37), -6.0, 0.0, 0.58, 0.46);
    ctDistrictRuin(layer, p, vec2(1531, 385), vec2(56, 25), -7.0, 0.0, 0.52, 0.43);
    ctDistrictRuin(layer, p, vec2(1742, 335), vec2(48, 28), -6.0, 1.0, 0.55, 0.47);
}

vec3 ctTempleStone(vec2 p, float light, float haze) {
    float vein = ctNoise(p * vec2(0.055, 0.18) + 12.1);
    float grain = ctStoneNoise(p + vec2(30.4, 2.6));
    float grit = ctHash(floor(p * 1.43));
    float crust = ctNoise(p * vec2(0.18, 0.091));
    vec3 shadow = mix(vec3(0.073, 0.138, 0.17), vec3(0.19, 0.24, 0.23), crust);
    vec3 ivory = mix(vec3(0.51, 0.50, 0.45), vec3(0.77, 0.732, 0.638), vein);
    vec3 color = mix(shadow, ivory, light) * (0.76 + 0.33 * grain + 0.10 * grit);
    float algae = smoothstep(0.58, 0.78, ctNoise(p * vec2(0.082, 0.037) + 11.0));
    color = mix(color, vec3(0.22, 0.26, 0.163) * (0.46 + 0.54 * light), algae * 0.53);
    return mix(color, vec3(0.104, 0.273, 0.337), haze);
}

void ctTempleSlab(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 c, vec2 d,
                  vec2 courses, float light, float haze) {
    if (!ctBounds(p, min(min(a, b), min(c, d)) - 1.0, max(max(a, b), max(c, d)) + 1.0)) return;
    float face = ctQuadMask(p, a, b, c, d);
    if (face <= 0.001) return;
    vec2 uv = ctProjectedUV(p, a, b, c, d);
    float erosion = ctNoise(p * 0.36);
    float chip = ctHash(floor(p * 1.6));
    vec2 tile = uv * courses;
    tile.x += 0.48 * mod(floor(tile.y), 2.0);
    float joint = min(abs(fract(tile.x) - 0.5), abs(fract(tile.y + 0.5) - 0.5));
    float cut = 1.0 - smoothstep(0.014, 0.056, joint + 0.025 * erosion);
    float sporadic = smoothstep(0.24, 0.72, erosion * 0.65 + chip * 0.35);
    float variation = 0.88 + 0.23 * ctHash(floor(tile + vec2(0.50, 0.0)) + a);
    vec3 color = ctTempleStone(p, light, haze) * (variation - cut * (0.17 + 0.2 * sporadic));
    ctPut(layer, color, face);
}

// The broken edge has its own projection, separate from the carved face.
void ctTempleCornice(inout vec4 layer, vec2 p, vec2 a, vec2 b, float height,
                     float light, float haze, float damage) {
    if (!ctBounds(p, min(a, b) - vec2(3, 6), max(a, b) + vec2(3, height + 5.0))) return;
    vec2 axis = b - a;
    float span = length(axis);
    float u = dot(p - a, axis) / span;
    float y = ctCross(axis / span, p - a);
    float chip = pow(ctNoise(vec2(u * 0.21, a.x * 0.16)), 3.7) * 4.0 * damage;
    float granule = ctHash(floor(p * 1.4));
    float rubble = ctNoise(vec2(u * 0.61, a.y * 0.55));
    float brokenLip = 0.87 * rubble + chip - 0.5;
    float flake = pow(ctNoise(vec2(u * 0.17 + 2.2, b.x * 0.13)), 4.2) * damage;
    float base = height - (0.36 + flake * 2.1) * rubble;
    float opacity = ctRamp(min(min(u, span - u), min(y - brokenLip, base - y)), 0.53);
    if (opacity <= 0.001) return;
    float phase = y / height;
    float crest = exp(-ctSquare((phase - 0.14) * 15.0));
    float ledge = exp(-ctSquare((phase - 0.69) * 17.0));
    float shadow = exp(-ctSquare((phase - 0.31) * 17.0)) + 0.67 * exp(-ctSquare((phase - 0.82) * 19.0));
    float soffit = smoothstep(0.77, 0.97, phase);
    float metric = u / max(3.1, height * 0.48);
    float stonelet = floor(metric);
    vec2 carving = vec2((fract(metric) - 0.5) * 2.4, (phase - 0.50) * 9.3);
    float relief = 1.0 - smoothstep(0.45, 0.93, max(abs(carving.x), abs(carving.y + 0.21 * rubble)));
    float survive = smoothstep(0.16, 0.68, ctHash(vec2(stonelet, b.x)));
    float cut = smoothstep(0.73, 0.95, abs(carving.x + rubble * 0.23)) * relief;
    float edgeChip = exp(-abs(y - brokenLip - 0.5) * 1.53);
    vec3 color = ctTempleStone(p, light, haze);
    color *= 0.87 + 0.23 * crest + 0.19 * ledge - 0.26 * shadow + relief * survive * 0.17 - cut * 0.12;
    color = mix(color, color * 0.48 + vec3(0.019, 0.040, 0.050), soffit * (0.62 + 0.34 * rubble));
    color += vec3(0.11, 0.076, 0.044) * (crest * 0.57 + relief * survive * 0.43) * light;
    color += vec3(0.14, 0.13, 0.102) * edgeChip * granule * damage * light;
    ctPut(layer, color, opacity);
}

void ctTemplePier(inout vec4 layer, vec2 p, vec2 capital, vec2 foot, float width,
                  float light, float haze, float seed) {
    if (!ctBounds(p, min(capital, foot) - vec2(width * 1.19 + 2.0, 2.0),
                     max(capital, foot) + vec2(width * 1.19 + 2.0, 2.0))) return;
    vec2 axis = normalize(foot - capital);
    vec2 q = p - capital;
    float height = length(foot - capital);
    float y = dot(q, axis);
    float lateral = ctCross(q, axis);
    float n = clamp(y / height, 0.0, 1.0);
    float crown = 1.0 - smoothstep(0.049, 0.153, n);
    float base = smoothstep(0.82, 0.985, n);
    float notch = ctNoise(vec2(y * 0.31, seed)) * ctNoise(p * 0.46);
    float spall = smoothstep(0.37, 0.68, notch);
    float abacus = 1.0 - smoothstep(0.035, 0.060, n);
    float neck = exp(-ctSquare((n - 0.105) * 38.0));
    float edge = width * (0.64 + 0.10 * sin(n * 2.74) + 0.23 * crown + 0.12 * abacus + 0.09 * neck + 0.23 * base)
               - spall * (0.41 + 0.67 * light);
    float mask = ctRamp(min(min(y, height - y), edge - abs(lateral)), 0.59);
    if (mask <= 0.001) return;
    float theta = asin(clamp(lateral / max(0.3, edge), -0.997, 0.997));
    float lambert = 0.18 + 0.82 * max(0.0, cos(theta + 0.61));
    float flute = 0.81 + 0.19 * smoothstep(-1.0, 0.66, cos(theta * (12.4 + 1.7 * fract(seed * 0.127))));
    float line = abs(fract(y / (13.0 + mod(seed, 6.0)) + 0.10 * notch) - 0.5);
    float joint = (1.0 - smoothstep(0.015, 0.052, line)) * smoothstep(0.09, 0.52, notch);
    float collar = exp(-ctSquare((n - 0.051) * 72.0)) + 0.64 * neck + 0.75 * exp(-ctSquare((n - 0.953) * 49.0));
    float groove = exp(-ctSquare((n - 0.074) * 69.0)) + 0.75 * exp(-ctSquare((n - 0.131) * 69.0))
                 + 0.70 * exp(-ctSquare((n - 0.91) * 51.0));
    float split = exp(-abs(lateral + width * (0.22 + 0.28 * ctNoise(vec2(y * 0.19, seed)))) * 2.1);
    split *= smoothstep(0.25, 0.55, ctNoise(vec2(y * 0.027, seed * 0.77))) * smoothstep(0.24, 0.65, n);
    float capLight = mix(lambert, mix(1.0, 0.46, smoothstep(0.40, 0.54, lateral / edge)), abacus * 0.72);
    vec3 color = ctTempleStone(p, light * (0.11 + 0.89 * capLight), haze);
    color *= mix(flute, 1.0, max(crown, base)) * (1.0 - 0.26 * joint - 0.24 * split - 0.20 * groove);
    color += vec3(0.20, 0.147, 0.072) * collar * light * lambert;
    ctPut(layer, color, mask);
}

void ctTempleColonnade(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 da, vec2 db,
                      int count, float width, float light, float haze, float openness) {
    vec2 d = a + da;
    vec2 c = b + db;
    if (!ctBounds(p, min(min(a, b), min(c, d)) - vec2(width + 7.0),
                     max(max(a, b), max(c, d)) + vec2(width + 8.0))) return;
    float screen = ctQuadMask(p, a, b, c, d);
    if (screen > 0.001) {
        vec2 uv = ctProjectedUV(p, a, b, c, d);
        float across = fract(uv.x * float(count - 1));
        float index = floor(uv.x * float(count - 1));
        float baySeed = ctHash(vec2(index + 0.34, a.x * 0.47));
        float soffit = 1.0 - smoothstep(0.05, 0.26, uv.y + 0.09 * sin(across * 3.14159));
        float atRear = uv.x * float(count - 1) + 0.27 + 0.12 * uv.y;
        float ribWidth = (0.105 + baySeed * 0.08) / (0.81 + uv.y * 0.19);
        float rib = 1.0 - smoothstep(ribWidth - 0.04, ribWidth + 0.06, abs(fract(atRear) - 0.5));
        float wall = 1.0 - smoothstep(0.12, 0.91, uv.y);
        float opening = ctRamp(0.33 - abs(fract(atRear + 0.08) - 0.5), 0.068)
                      * smoothstep(0.16, 0.34, uv.y)
                      * (1.0 - smoothstep(0.83, 0.96, uv.y));
        opening *= smoothstep(0.33, 0.88, baySeed + 0.56 * openness);
        if (openness > 0.75 && index < 0.5)
            opening = max(opening, ctRamp(0.40 - abs(across - 0.50), 0.07) * smoothstep(0.06, 0.25, uv.y));
        float threshold = smoothstep(0.81 + 0.04 * baySeed, 0.98, uv.y);
        float bed = ctNoise(p * 0.19) * (0.74 + 0.26 * (1.0 - wall));
        vec3 atBack = ctTempleStone(p, light * (0.032 + 0.12 * rib), haze * 0.51);
        atBack *= (0.49 + 0.25 * bed + 0.12 * rib) * (1.0 - soffit * 0.35);
        atBack += vec3(0.022, 0.047, 0.056) * wall;
        float scatter = smoothstep(0.44, 0.82, openness) * (0.32 + 0.68 * uv.y);
        atBack += vec3(0.096, 0.18, 0.189) * scatter * (0.58 + 0.42 * bed) * (1.0 - soffit);
        vec3 thresholdStone = ctTempleStone(p, 0.23 * light, haze);
        atBack = mix(atBack, thresholdStone, threshold * 0.76);
        float coverage = screen * (1.0 - opening * openness * (1.0 - rib));
        ctPut(layer, atBack, coverage);
        if (openness < 0.28 && baySeed > 0.62) {
            vec2 q = vec2((across - 0.47 - 0.15 * baySeed) * 7.1, (uv.y - 0.78) * 10.3);
            float halo = exp(-dot(q, q) * 1.05) * screen;
            float wick = pow(halo, 6.8) * (0.67 + 0.33 * ctNoise(p * 0.92));
            ctPut(layer, vec3(0.06, 0.37, 0.44), halo * 0.53);
            ctPut(layer, vec3(0.24, 0.76, 0.80), wick * 0.85);
        }
    }

    for (int i = 0; i < 12; ++i) {
        if (i >= count) break;
        float seed = ctHash(vec2(float(i), a.x));
        float u = float(i) / float(count - 1);
        float gap = float(i * (count - 1 - i) > 0) * (seed - 0.50) * 0.092;
        vec2 cap = mix(a, b, u + gap);
        vec2 foot = mix(d, c, u + gap) + vec2((seed - 0.50) * 1.5, -0.6);
        ctTemplePier(layer, p, cap, foot, width * (0.84 + seed * 0.29), light * (0.84 + seed * 0.23), haze, float(i) + a.x);
    }
    ctTempleCornice(layer, p, d - vec2(4, 3), c + vec2(4, -3), 5.0 + width * 0.23, light * 0.65, haze, 0.66);
    ctTempleCornice(layer, p, a - vec2(4, 5), b + vec2(4, -5), 5.0 + width * 0.51, light, haze, 0.47);
}

void ctTempleChip(inout vec4 layer, vec2 p, vec2 center, vec2 radius, float angle, float light, float haze) {
    float reach = length(radius) * 1.22 + 1.0;
    if (!ctBounds(p, center - reach, center + reach)) return;
    vec2 r = p - center;
    vec2 direction = vec2(cos(angle), sin(angle));
    vec2 q = vec2(dot(r, direction), ctCross(direction, r)) / radius;
    float grit = ctNoise(p * 0.37);
    float bevel = max(abs(q.x + 0.26 * q.y), abs(q.y - 0.22 * q.x));
    float corner = abs(q.x - q.y) * 0.72;
    float border = max(bevel, corner) + 0.13 * grit;
    float shape = 1.0 - smoothstep(0.91, 1.03, border);
    if (shape <= 0.001) return;
    float facet = smoothstep(-0.34, -0.28, q.y + 0.34 * q.x);
    float split = smoothstep(0.44, 0.51, q.x + q.y * 0.45);
    vec3 color = ctTempleStone(p, light * (0.96 - 0.48 * facet - 0.21 * split), haze);
    color += vec3(0.13, 0.12, 0.096) * exp(-abs(border - 0.90) * 26.0) * light * (1.0 - facet);
    ctPut(layer, color, shape);
}

void ctTempleCopper(inout vec4 layer, vec2 p, vec2 center, vec2 radius, float tilt, float light, float haze) {
    if (!ctBounds(p, center - radius - vec2(4, abs(tilt) + 8.0),
                     center + vec2(radius.x + 3.0, radius.y * 0.38 + abs(tilt) + 3.0))) return;
    vec2 q = (p - center) / radius;
    q.y -= q.x * tilt / radius.y;
    float rim = 0.25 * sqrt(max(0.0, 1.0 - q.x * q.x));
    float edge = max(length(vec2(q.x, min(q.y, 0.0))) - 1.0, q.y - rim - 0.05);
    float mask = 1.0 - smoothstep(-0.021, 0.021, edge);
    if (mask > 0.001) {
        float latitude = min(0.0, q.y);
        float z = sqrt(max(0.001, 1.0 - q.x * q.x - latitude * latitude));
        vec3 normal = normalize(vec3(q.x, -q.y, z));
        float azimuth = atan(q.x, max(0.014, z));
        float lambert = 0.18 + 0.82 * max(0.0, dot(normal, vec3(-0.58, 0.51, 0.633)));
        float sheen = pow(max(0.0, dot(normal, vec3(-0.48, 0.55, 0.684))), 10.0);
        float gloss = pow(max(0.0, dot(normal, vec3(-0.61, 0.51, 0.605))), 55.0);
        float rib = abs(sin(azimuth * 6.35 + 0.12));
        float seam = 1.0 - smoothstep(0.028, 0.093, rib);
        float join = 1.0 - smoothstep(0.018, 0.073, abs(sin(azimuth * 6.35 - 0.076)));
        float course = 1.0 - smoothstep(0.026, 0.108, abs(sin((q.y - 0.13 * z) * 7.1 + 0.25)));
        float grit = ctHash(floor(p * 1.13));
        float weather = 0.39 * ctNoise(p * 0.084) + 0.40 * ctNoise(p * 0.41) + 0.21 * grit;
        float runoff = smoothstep(0.44, 0.74, ctNoise(vec2(p.x * 0.193, p.y * 0.087) + 37.0));
        float patina = 0.55 * runoff + 0.23 * smoothstep(0.28, 0.75, ctNoise(p * 0.16));
        vec3 bronze = mix(vec3(0.43, 0.28, 0.163), vec3(0.67, 0.50, 0.34), weather);
        bronze = mix(bronze, vec3(0.185, 0.249, 0.219), patina);
        vec3 color = bronze * lambert * (0.52 + 0.48 * light) * (0.87 + 0.29 * weather - 0.28 * seam - 0.16 * course);
        color += vec3(0.76, 0.66, 0.49) * light * sheen * (0.28 + 0.32 * weather);
        color += vec3(0.32, 0.30, 0.24) * sheen * (1.0 - 0.37 * sheen) * light * light;
        color += vec3(0.41, 0.25, 0.111) * gloss * light * (0.16 + 0.21 * grit);
        color += vec3(0.23, 0.158, 0.084) * join * lambert * light;
        float base = q.y - rim;
        float metalLip = exp(-ctSquare((base + 0.050) * 52.0)) * (0.54 + grit * 0.46);
        color = mix(color, vec3(0.122, 0.255, 0.26) * (0.64 + 0.48 * weather), smoothstep(-0.041, -0.015, base) * 0.94);
        color += vec3(0.32, 0.235, 0.128) * metalLip * (0.25 + 0.75 * lambert) * light;
        ctPut(layer, mix(color, vec3(0.10, 0.275, 0.329), haze), mask);
    }

    vec2 finial = center - vec2(0, radius.y + 0.8);
    float reach = max(1.5, radius.x * 0.124);
    float plate = 1.0 - smoothstep(0.81, 1.07, length((p - finial + vec2(0.0, 0.4)) / vec2(reach, reach * 0.28 + 0.5)));
    float crown = 1.0 - smoothstep(0.70, 1.10, length((p - finial + vec2(0.0, 2.4)) / vec2(reach * 0.44, reach * 0.41 + 0.6)));
    if (max(plate, crown) > 0.001) {
        vec3 clasp = ctTempleStone(p, light * 0.79, haze) * vec3(1.02, 0.83, 0.60);
        ctPut(layer, clasp, max(plate, crown));
    }
}

void ctTempleRotunda(inout vec4 layer, vec2 p, vec2 center, vec2 roof, float height,
                    float tilt, float light, float haze, float aperture) {
    if (!ctBounds(p, center - vec2(roof.x + 8.0, roof.y + 9.0),
                     center + vec2(roof.x + 8.0, height + tilt + 21.0))) return;
    for (int i = 0; i < 6; ++i) {
        float l = float(i) * 0.49 - 1.47;
        float r = l + 0.49;
        vec2 a = center + vec2(sin(l) * roof.x, cos(l) * roof.y * 0.25 + sin(l) * tilt);
        vec2 b = center + vec2(sin(r) * roof.x, cos(r) * roof.y * 0.25 + sin(r) * tilt);
        vec2 down = vec2(-0.028 * height + sin(l) * 1.6, height * (0.955 + 0.040 * cos(l)));
        vec2 downRight = vec2(-0.028 * height + sin(r) * 1.6, height * (0.955 + 0.040 * cos(r)));
        float shade = light * (0.94 - 0.20 * l);
        float screen = ctQuadMask(p, a, b, b + downRight, a + down);
        if (screen > 0.001) {
            vec2 uv = ctQuadUV(p, a, b, a + down);
            float arch = ctRamp(0.31 - abs(uv.x - 0.46), 0.10) * smoothstep(0.13, 0.25, uv.y);
            float pillar = smoothstep(0.55, 0.74, uv.x) * (1.0 - smoothstep(0.80, 0.95, uv.x));
            float across = ctNoise(p * 0.11);
            vec3 color = ctTempleStone(p, shade * (0.05 + 0.12 * pillar), haze * 0.61);
            color *= 0.48 + 0.41 * across + 0.23 * smoothstep(0.64, 1.0, uv.y);
            ctPut(layer, color, screen * (1.0 - aperture * arch * (1.0 - 0.6 * pillar)));
            if (aperture < 0.56 && (i == 2 || i == 4)) {
                vec2 lamp = (uv - vec2(0.46, 0.74)) * vec2(5.9, 7.5);
                float hazeGlow = exp(-dot(lamp, lamp)) * screen;
                float wick = pow(hazeGlow, 7.7) * (0.64 + 0.36 * ctNoise(p * 0.51));
                ctPut(layer, vec3(0.035, 0.35, 0.40), hazeGlow * 0.62);
                ctPut(layer, vec3(0.16, 0.61, 0.63), wick * 0.86);
            }
        }
        ctTemplePier(layer, p, a + vec2(0.0, roof.y * 0.28), a + down,
                     roof.x * (0.079 + 0.03 * cos(l)), shade, haze, 28.7 + float(i) * 1.8);
        ctTempleCornice(layer, p, a + down - vec2(0, 2), b + downRight - vec2(0, 2),
                        max(2.8, roof.x * 0.091), shade * 0.76, haze, 0.51);
    }
    vec2 edge = center + vec2(sin(1.47) * roof.x, cos(1.47) * roof.y * 0.25 + sin(1.47) * tilt);
    ctTemplePier(layer, p, edge + vec2(0.0, roof.y * 0.28), edge + vec2(-0.028, 0.957) * height,
                 roof.x * 0.086, light * 0.62, haze, 10.8);
    ctTempleCopper(layer, p, center, roof, tilt, light, haze);
    for (int i = 0; i < 8; ++i) {
        float l = float(i) * 0.375 - 1.5;
        float r = l + 0.375;
        vec2 a = center + vec2(sin(l) * roof.x, cos(l) * roof.y * 0.25 + sin(l) * tilt);
        vec2 b = center + vec2(sin(r) * roof.x, cos(r) * roof.y * 0.25 + sin(r) * tilt);
        float shade = light * (0.95 - 0.19 * l);
        ctTempleCornice(layer, p, a + vec2(0.0, roof.y * 0.088), b + vec2(0.0, roof.y * 0.088),
                        max(3.0, roof.x * 0.19), shade, haze, 0.76);
    }
}

float ctTempleStroke(vec2 p, vec2 a, vec2 b, float width) {
    vec2 line = b - a;
    float u = clamp(dot(p - a, line) / dot(line, line), 0.0, 1.0);
    return 1.0 - smoothstep(width * 0.63, width * 1.38, length(p - a - line * u));
}

void ctTempleGarden(inout vec4 layer, vec2 p, vec2 a, vec2 b, float size, float haze) {
    if (!ctBounds(p, min(a, b) - vec2(3, size * 1.62), max(a, b) + vec2(4, size * 1.38))) return;
    vec2 along = normalize(b - a);
    vec2 v = p - a;
    float x = dot(v, along);
    float y = ctCross(along, v);
    float span = length(b - a);
    if (x < -2.0 || x > span + 2.0) return;
    float grain = ctStoneNoise(p);
    float fringe = ctNoise(vec2(x * 0.21, a.x * 0.046));
    float fray = ctNoise(vec2(x * 0.53 + 0.82 * y, a.y * 0.058));
    float downward = size * 0.91 * pow(fringe, 2.7) * (0.29 + 0.71 * fray);
    float loam = ctRamp(min(y + 1.2 + size * fringe * 0.39, 0.9 + downward - y), 0.85);
    vec3 moss = mix(vec3(0.084, 0.117, 0.067), vec3(0.37, 0.39, 0.15), grain + 0.25 * fray);
    ctPut(layer, mix(moss, vec3(0.09, 0.29, 0.34), haze), loam * smoothstep(0.32, 0.57, fringe) * 0.88);

    float spacing = size * 1.04;
    float id = floor(x / spacing);
    for (int k = -1; k <= 1; ++k) {
        float cell = id + float(k);
        float seed = ctHash(vec2(cell + 0.5, a.x + a.y));
        float root = (cell + 0.20 + seed * 0.60) * spacing;
        if (root < 0.0 || root > span) continue;
        float variant = ctHash(vec2(cell + 5.0, b.x));
        vec2 q = vec2((x - root) / size, (y + variant * size * 0.15) / size);
        float rubble = max(abs(q.x + 0.08 + 0.25 * q.y) / (0.36 + variant * 0.16),
                           abs(q.y + 0.13 * q.x) / (0.17 + 0.15 * seed));
        vec3 rock = mix(vec3(0.112, 0.142, 0.131), vec3(0.37, 0.31, 0.22), grain - q.y * 1.1);
        ctPut(layer, mix(rock, vec3(0.092, 0.266, 0.314), haze), 0.64 * (1.0 - smoothstep(0.58, 0.90, rubble + grain * 0.36)));
        float height = (0.38 + 0.64 * seed) * (0.64 + 0.36 * smoothstep(0.32, 0.62, fringe));
        if (seed < 0.16 || q.y > 0.095 || q.y < -height - 0.1 || abs(q.x) > 0.78) continue;

        vec3 dark = vec3(0.24, 0.125, 0.10);
        vec3 tips = vec3(0.74, 0.40, 0.27);
        if (variant > 0.40) {
            dark = vec3(0.13, 0.22, 0.16);
            tips = vec3(0.59, 0.60, 0.28);
        }
        if (variant > 0.66) {
            dark = vec3(0.074, 0.199, 0.239);
            tips = vec3(0.345, 0.575, 0.655);
        }
        if (variant > 0.83) {
            dark = vec3(0.28, 0.162, 0.207);
            tips = vec3(0.65, 0.485, 0.51);
        }
        float silhouette = 0.0;
        float lightSide = 0.0;
        for (int i = 0; i < 5; ++i) {
            float branch = float(i) - 2.0;
            float jitter = ctHash(vec2(cell + 0.64, float(i) + a.x));
            vec2 joint = vec2(branch * (0.07 + jitter * 0.015), -height * (0.40 + jitter * 0.21));
            vec2 tip = vec2(branch * (0.15 + jitter * 0.090) + (seed - 0.5) * 0.27,
                            -height * (0.83 + jitter * 0.15 - 0.12 * abs(branch)));
            float width = (0.017 + variant * 0.020) * (0.8 + 0.35 * jitter);
            float body = max(ctTempleStroke(q, vec2(0.0), joint, width * 1.27),
                             ctTempleStroke(q, joint, tip, width));
            vec2 sprig = mix(joint, tip, 0.44);
            vec2 side = sprig + vec2(sign(branch + 0.12) * (0.12 + jitter * 0.09), -0.11 - 0.04 * jitter);
            body = max(body, ctTempleStroke(q, sprig, side, width * 0.69));
            silhouette = max(silhouette, body);
            lightSide = max(lightSide, body * (0.23 + 0.77 * jitter));
        }
        float tint = clamp(-q.y / height * 0.35 + 0.23 * lightSide + 0.42 * grain, 0.0, 1.0);
        ctPut(layer, mix(mix(dark, tips, tint), vec3(0.10, 0.255, 0.32), haze), silhouette * 0.98);
    }
}

void ctTemplePortico(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(936, 233), vec2(997, 322))) return;
    vec2 a = vec2(943, 253), b = vec2(991, 256);
    vec2 d = vec2(940, 316), c = vec2(988, 314);
    ctTempleSlab(layer, p, a, b, c, d, vec2(4, 7), 0.26, 0.088);
    ctTempleSlab(layer, p, a + vec2(8, 7), b + vec2(-8, 6), c + vec2(-7, 0), d + vec2(9, 0),
                 vec2(3, 5), 0.09, 0.025);
    if (ctBounds(p, vec2(951, 263), vec2(981, 315))) {
        float door = ctQuadMask(p, vec2(954, 263), vec2(980, 265), vec2(977, 314), vec2(951, 315));
        float depth = smoothstep(0.0, 1.0, (p.x - 952.0) / 26.0);
        vec3 black = mix(vec3(0.026, 0.062, 0.076), vec3(0.074, 0.116, 0.116), depth);
        float stoneJamb = exp(-ctSquare((p.x - 953.0 + (p.y - 265.0) * 0.035) * 0.64));
        ctPut(layer, black + vec3(0.134, 0.112, 0.074) * stoneJamb, door * 0.92);
    }
    ctTemplePier(layer, p, a + vec2(1, 5), d, 4.5, 0.68, 0.071, 7.0);
    ctTemplePier(layer, p, b + vec2(-2, 3), c, 4.1, 0.41, 0.086, 12.0);
    ctTempleCornice(layer, p, a - vec2(2, 3), b + vec2(3, -3), 10.9, 0.77, 0.075, 0.85);
    vec2 left = vec2(940, 252), apex = vec2(968, 235), right = vec2(994, 253);
    ctTempleSlab(layer, p, left, apex - vec2(0.8, 0), apex + vec2(0.8, 0), right,
                 vec2(7, 2), 0.31, 0.081);
    ctTempleCornice(layer, p, left, apex, 3.6, 0.90, 0.078, 0.62);
    ctTempleCornice(layer, p, apex, right, 3.6, 0.61, 0.080, 0.88);
    ctTempleChip(layer, p, apex + vec2(4.6, 3.8), vec2(4.8, 1.5), 0.48, 0.54, 0.09);
    ctTempleCornice(layer, p, d + vec2(-3, -1), c + vec2(3, -2), 4.6, 0.66, 0.073, 0.62);
}

void ctTempleStair(inout vec4 layer, vec2 p) {
    vec2 a = vec2(903, 322), b = vec2(946, 315);
    vec2 c = vec2(832, 425), d = vec2(781, 430);
    if (!ctBounds(p, vec2(774, 310), vec2(954, 453))) return;
    vec2 toe = vec2(2, 8);
    vec2 deep = vec2(3, 38);
    vec2 landingLeft = a + vec2(13, -9);
    vec2 landingRight = b + vec2(14, -7);
    ctTempleSlab(layer, p, landingLeft, landingRight, b + vec2(1, 1), a + vec2(-1, 2),
                 vec2(5, 2), 0.58, 0.064);
    float side = ctQuadMask(p, b, c, c + toe, b + deep);
    if (side > 0.001) {
        vec2 uv = ctProjectedUV(p, b, c, c + toe, b + deep);
        float step = floor(max(0.0, uv.x) * 7.3);
        vec2 q = vec2((fract(uv.x * 7.3) - 0.55) * 2.44, (uv.y - 0.59) * 3.30);
        float arch = 1.0 - smoothstep(0.93, 1.08, length(vec2(q.x, min(q.y, 0.0))));
        arch *= smoothstep(0.48, 0.78, uv.y + uv.x * 0.20) * (1.0 - smoothstep(0.31, 0.77, uv.x));
        vec3 stone = ctTempleStone(p, 0.27 - 0.11 * uv.y, 0.064);
        stone *= 0.80 + 0.33 * ctHash(vec2(step, floor(uv.y * 2.8)));
        float stoneJoint = 1.0 - smoothstep(0.020, 0.078, abs(fract(uv.x * 7.3) - 0.04));
        stone *= 1.0 - 0.18 * stoneJoint;
        ctPut(layer, mix(stone, vec3(0.03, 0.066, 0.071), arch * 0.76), side);
    }
    vec2 floorLeft = d + vec2(-5, 10);
    vec2 floorRight = c + vec2(4, 9);
    ctTempleSlab(layer, p, d, c, floorRight, floorLeft, vec2(5, 1), 0.56, 0.046);
    ctTempleCornice(layer, p, floorLeft, floorRight, 2.5, 0.33, 0.055, 0.91);
    float shape = ctQuadMask(p, a, b, c, d);
    if (shape > 0.001) {
        vec2 uv = ctProjectedUV(p, a, b, c, d);
        float cross = uv.x;
        float f = ctNoise(p * vec2(0.44, 0.25));
        float distance = 32.4 * uv.y + 0.077 * f;
        float treadRow = floor(distance);
        float worn = ctHash(vec2(treadRow + 11.0, 3.0));
        float step = fract(distance + (worn - 0.5) * 0.075 * sin(cross * 8.9));
        float remnant = smoothstep(0.22, 0.73, f);
        float profile = 0.80 + 0.31 * exp(-ctSquare((step - 0.14) * 5.8))
                      - 0.29 * exp(-ctSquare((step - 0.84) * 7.0));
        float tread = (0.86 + 0.16 * ctHash(vec2(treadRow, floor(cross * 2.0)))) * profile;
        tread *= 1.0 - 0.16 * exp(-abs(cross - 0.16 - f * 0.15) * 29.0) * worn;
        float width = 0.105 + 0.025 * remnant;
        float edge = min(cross, 1.0 - cross) + 0.031 * ctNoise(vec2(p.x * 0.26, p.y * 0.47));
        float curb = 1.0 - smoothstep(width - 0.03, width + 0.023, edge);
        float moss = smoothstep(0.43, 0.72, 0.74 * ctNoise(vec2(uv.y * 38.0, cross * 2.0)) + 0.26 * f);
        vec3 stone = ctTempleStone(p, 0.85, 0.052);
        float divide = 1.0 - smoothstep(0.018, 0.085, abs(fract(distance * 0.23 + f * 0.064) - 0.5));
        vec3 rim = ctTempleStone(p + 11.7, 0.88, 0.055) * (0.73 + 0.40 * remnant - 0.27 * divide);
        rim = mix(rim, vec3(0.24, 0.278, 0.13), moss * 0.74);
        ctPut(layer, mix(stone * tread, rim, curb), shape);
    }
    ctTempleChip(layer, p, d + vec2(0, 5), vec2(4.8, 2.3), 0.38, 0.51, 0.047);
    ctTempleChip(layer, p, c + vec2(3, 4), vec2(5.1, 2.1), -0.26, 0.54, 0.050);

    vec2 lampOrigin = vec2(933, 351);
    vec2 q = (p - lampOrigin) / vec2(4.1, 6.8);
    float glow = exp(-dot(q, q) * 0.68);
    float wick = exp(-dot(q, q) * 4.1) * (0.62 + 0.38 * ctNoise(p * 1.1));
    ctPut(layer, vec3(0.052, 0.327, 0.388), glow * 0.62);
    ctPut(layer, vec3(0.23, 0.69, 0.70), wick * 0.89);
}

float ctTempleGlyph(vec2 q, int glyph) {
    if (glyph == 0) {
        return max(max(ctTempleStroke(q, vec2(-0.73, 0.72), vec2(0.02, -0.78), 0.094),
                       ctTempleStroke(q, vec2(0.02, -0.78), vec2(0.73, 0.70), 0.094)),
                   ctTempleStroke(q, vec2(-0.73, 0.72), vec2(0.73, 0.70), 0.094));
    }
    if (glyph == 1) {
        float diamond = abs(abs(q.x) + abs(q.y * 0.83) - 0.76);
        float inner = abs(abs(q.x + 0.02) + abs(q.y * 0.97 - 0.08) - 0.46);
        return 1.0 - smoothstep(0.051, 0.112, min(diamond, inner));
    }
    if (glyph == 2) {
        float outer = abs(max(abs(q.x), abs(q.y)) - 0.73);
        float inner = abs(max(abs(q.x + 0.12), abs(q.y - 0.02)) - 0.43) +
                      smoothstep(0.21, 0.31, q.x) * smoothstep(-0.37, -0.22, q.y);
        float bar = abs(q.x - 0.14) + max(0.0, abs(q.y + 0.062) - 0.30);
        return 1.0 - smoothstep(0.066, 0.13, min(min(outer, inner), bar));
    }
    float cross = abs(abs(q.y * 0.66) - abs(q.x * 0.79));
    return (1.0 - smoothstep(0.055, 0.105, cross)) * (1.0 - smoothstep(0.63, 0.87, max(abs(q.x), abs(q.y))));
}

void ctTempleObelisk(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(947, 253), vec2(999, 388))) return;
    vec2 a = vec2(972, 268), b = vec2(981, 268), c = vec2(976, 369), d = vec2(953, 365);
    vec2 summit = vec2(979, 254);
    vec2 bc = vec2(989, 267), cc = vec2(991, 361);
    ctTempleSlab(layer, p, d - vec2(3, 2), c + vec2(4, -1), cc + vec2(1, 4), vec2(959, 376),
                 vec2(3, 2), 0.39, 0.062);
    ctTempleSlab(layer, p, b, bc, cc, c, vec2(2, 7), 0.23, 0.056);
    ctTempleSlab(layer, p, summit - vec2(0.7, -0.5), summit + vec2(1.0, 0), bc, b, vec2(1, 2), 0.31, 0.055);
    ctTempleSlab(layer, p, a, summit - vec2(0.7, -0.5), summit + vec2(1.0, 0), b, vec2(1, 2), 0.71, 0.045);
    float face = ctQuadMask(p, a, b, c, d);
    if (face > 0.001) {
        vec2 uv = ctQuadUV(p, a, b, d);
        float span = 1.0 + 1.46 * uv.y;
        float lx = uv.x / span;
        vec3 color = ctTempleStone(p, 0.60 - 0.17 * smoothstep(0.52, 0.95, lx), 0.051);
        float bevel = exp(-min(abs(lx), abs(lx - 1.0)) * 17.0);
        color += vec3(0.074, 0.059, 0.039) * bevel;
        float v = uv.y * 7.0;
        int band = int(floor(v));
        int symbol = band == 1 || band == 4 ? 1 : (band == 3 || band == 6 ? 2 : (band == 0 ? 3 : 0));
        float age = ctNoise(p * 0.45);
        float chip = ctNoise(p * 0.91);
        vec2 q = vec2((lx - 0.50) * 2.36, (fract(v) - 0.50) * 2.29);
        q += vec2(age - 0.5, chip - 0.5) * (0.037 + uv.y * 0.047);
        float inscription = band > 6 ? 0.0 : ctTempleGlyph(q, symbol);
        float wall = band > 6 ? 0.0 : ctTempleGlyph(q - vec2(0.065, 0.055), symbol);
        float floor = max(0.0, inscription - wall * 0.72);
        float crest = max(0.0, wall - inscription);
        float blunt = smoothstep(0.27, 0.72, age);
        color *= 1.0 - (0.50 - blunt * 0.23) * floor - 0.22 * inscription;
        color += vec3(0.20, 0.162, 0.099) * crest * (0.47 + 0.53 * blunt);
        float fracture = exp(-abs(uv.y - 0.70 - 0.075 * lx - 0.026 * ctNoise(p * 0.28)) * 288.0);
        float spall = exp(-abs(lx - 0.68 - 0.16 * age) * 19.0) * smoothstep(0.49, 0.74, age);
        ctPut(layer, color * (1.0 - 0.30 * fracture - 0.15 * spall), face);
    }
    ctTempleCornice(layer, p, d - vec2(3, -1), c + vec2(3, 1), 7.0, 0.66, 0.068, 0.76);
}

void ctTempleFallenDrum(inout vec4 layer, vec2 p, vec2 a, vec2 b) {
    if (!ctBounds(p, min(a, b) - vec2(17), max(a, b) + vec2(17))) return;
    vec2 along = normalize(b - a);
    vec2 q = p - a;
    float distance = dot(q, along);
    float radial = ctCross(along, q);
    float span = length(b - a);
    float u = clamp(distance / span, 0.0, 1.0);
    float ridge = exp(-ctSquare((u - 0.10) * 19.0)) + 0.67 * exp(-ctSquare((u - 0.19) * 24.0));
    float radius = 11.7 - 6.4 * u + 2.6 * ridge;
    float crack = 1.0 + ctNoise(p * 0.81) * 2.8 + 2.2 * sin(radial * 0.71);
    float m = ctRamp(min(min(distance + 0.26 * radial, span - distance - crack), radius - abs(radial)), 0.6);
    if (m <= 0.001) return;
    float theta = asin(clamp(radial / radius, -0.996, 0.996));
    float shine = 0.21 + 0.79 * max(0.0, cos(theta - 0.84));
    float flute = 0.94 + 0.11 * cos(theta * 21.0) * smoothstep(0.01, 0.08, abs(u - 0.16));
    float ring = exp(-ctSquare((u - 0.072) * 69.0)) + exp(-ctSquare((u - 0.21) * 73.0));
    vec3 stone = ctTempleStone(p, 0.75 * shine, 0.045) * mix(vec3(0.96, 0.83, 0.71), vec3(1.04, 0.94, 0.80), u);
    stone *= flute * (0.78 + ridge * 0.19 + ring * 0.21);
    stone *= mix(1.0, 0.71, smoothstep(0.87, 0.995, u));
    ctPut(layer, stone, m);
}

void ctMainTemple(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(749, 24), vec2(1280, 483))) return;

    ctTemplePier(layer, p, vec2(811, 215), vec2(812, 346), 8.2, 0.51, 0.30, 7.0);
    ctTemplePier(layer, p, vec2(848, 219), vec2(849, 352), 6.2, 0.43, 0.31, 3.0);
    ctTemplePier(layer, p, vec2(1186, 201), vec2(1172, 329), 10.8, 0.54, 0.18, 10.0);
    ctTemplePier(layer, p, vec2(1247, 251), vec2(1238, 318), 5.7, 0.25, 0.23, 2.0);
    ctTemplePier(layer, p, vec2(1229, 229), vec2(1224, 316), 5.3, 0.37, 0.20, 8.0);

    // Downhill retaining gallery and the two worn surfaces of its coping.
    ctTempleSlab(layer, p, vec2(1081, 350), vec2(1236, 339), vec2(1228, 387), vec2(1087, 409),
                 vec2(14, 4), 0.12, 0.091);
    ctTempleSlab(layer, p, vec2(863, 348), vec2(1081, 350), vec2(1087, 409), vec2(878, 391),
                 vec2(16, 5), 0.20, 0.081);
    ctTempleCornice(layer, p, vec2(1086, 405), vec2(1230, 383), 5.4, 0.27, 0.10, 0.73);
    ctTempleColonnade(layer, p, vec2(1106, 305), vec2(1242, 287), vec2(-7, 70), vec2(-6, 76),
                      8, 7.6, 0.36, 0.11, 0.24);
    ctTempleColonnade(layer, p, vec2(870, 290), vec2(1106, 305), vec2(-9, 86), vec2(-5, 73),
                      11, 8.6, 0.52, 0.105, 0.12);
    ctTempleSlab(layer, p, vec2(1100, 301), vec2(1242, 284), vec2(1227, 276), vec2(1088, 288),
                 vec2(13, 3), 0.53, 0.13);
    ctTempleSlab(layer, p, vec2(870, 288), vec2(1100, 301), vec2(1090, 289), vec2(884, 268),
                 vec2(21, 3), 0.62, 0.11);
    ctTempleCornice(layer, p, vec2(1105, 301), vec2(1248, 284), 11.2, 0.46, 0.119, 0.57);
    ctTempleCornice(layer, p, vec2(867, 286), vec2(1106, 301), 11.7, 0.69, 0.092, 0.66);
    ctTempleSlab(layer, p, vec2(1066, 222), vec2(1185, 270), vec2(1181, 295), vec2(1060, 251),
                 vec2(10, 4), 0.42, 0.14);
    ctTempleCornice(layer, p, vec2(1066, 222), vec2(1185, 270), 4.7, 0.54, 0.14, 0.77);

    ctTempleSlab(layer, p, vec2(1104, 249), vec2(1164, 254), vec2(1176, 279), vec2(1098, 259),
                 vec2(5, 3), 0.21, 0.134);
    ctTempleColonnade(layer, p, vec2(1082, 224), vec2(1147, 217), vec2(-5, 60), vec2(-4, 50),
                      5, 4.5, 0.37, 0.135, 0.34);
    ctTempleRotunda(layer, p, vec2(1138, 202), vec2(31, 17), 55.0, 1.4, 0.38, 0.16, 0.22);
    ctTempleRotunda(layer, p, vec2(1146, 161), vec2(20, 11), 47.0, 1.1, 0.40, 0.21, 0.94);
    ctTemplePier(layer, p, vec2(944, 153), vec2(941, 215), 7.0, 0.61, 0.16, 1.0);
    ctTemplePier(layer, p, vec2(936, 182), vec2(935, 218), 3.3, 0.54, 0.15, 26.0);

    // Upper procession follows the corner down to the darker east face.
    ctTempleColonnade(layer, p, vec2(1055, 133), vec2(1123, 138), vec2(-4, 62), vec2(-9, 54),
                      5, 5.3, 0.37, 0.164, 0.68);
    ctTempleColonnade(layer, p, vec2(963, 136), vec2(1055, 133), vec2(-2, 55), vec2(-4, 62),
                      6, 6.8, 0.77, 0.125, 0.82);
    ctTempleSlab(layer, p, vec2(957, 118), vec2(1058, 117), vec2(1125, 126), vec2(1047, 95),
                 vec2(12, 3), 0.68, 0.15);
    ctTempleSlab(layer, p, vec2(969, 117), vec2(1055, 106), vec2(1103, 122), vec2(969, 123),
                 vec2(11, 2), 0.44, 0.121);
    ctTempleCornice(layer, p, vec2(1058, 118), vec2(1127, 127), 14.6, 0.40, 0.15, 0.61);
    ctTempleCornice(layer, p, vec2(956, 120), vec2(1059, 117), 15.7, 0.74, 0.126, 0.66);
    ctTempleSlab(layer, p, vec2(975, 111), vec2(1044, 110), vec2(1081, 116), vec2(969, 117),
                 vec2(5, 1), 0.65, 0.12);
    ctTempleSlab(layer, p, vec2(981, 107), vec2(1052, 103), vec2(1075, 110), vec2(976, 113),
                 vec2(7, 1), 0.63, 0.131);
    ctTempleSlab(layer, p, vec2(992, 102), vec2(1056, 96), vec2(1068, 104), vec2(982, 108),
                 vec2(7, 1), 0.58, 0.135);
    ctTempleCornice(layer, p, vec2(997, 99), vec2(1054, 93), 6.1, 0.63, 0.133, 0.73);
    ctTempleSlab(layer, p, vec2(1052, 94), vec2(1089, 100), vec2(1100, 117), vec2(1056, 115),
                 vec2(4, 3), 0.28, 0.15);
    ctTempleChip(layer, p, vec2(1019, 106), vec2(7.0, 3.8), 0.56, 0.76, 0.12);
    ctTempleChip(layer, p, vec2(1035, 106), vec2(7.8, 4.3), -0.34, 0.70, 0.135);
    ctTempleChip(layer, p, vec2(1058, 100), vec2(9.8, 4.6), -0.62, 0.62, 0.124);
    ctTempleChip(layer, p, vec2(1095, 107), vec2(4.6, 3.2), 1.20, 0.37, 0.149);
    ctTempleChip(layer, p, vec2(962, 116), vec2(5.1, 2.1), 1.51, 0.68, 0.124);
    ctTempleChip(layer, p, vec2(1122, 124), vec2(6.9, 2.3), -1.48, 0.42, 0.12);

    ctTempleColonnade(layer, p, vec2(1052, 49), vec2(1089, 58), vec2(-3, 46), vec2(-3, 48),
                      4, 4.6, 0.36, 0.171, 0.37);
    ctTempleColonnade(layer, p, vec2(1004, 58), vec2(1052, 49), vec2(-3, 41), vec2(-4, 47),
                      5, 4.5, 0.78, 0.126, 0.77);
    ctTempleSlab(layer, p, vec2(1000, 48), vec2(1038, 35), vec2(1050, 35), vec2(1055, 44),
                 vec2(4, 2), 0.78, 0.133);
    ctTempleSlab(layer, p, vec2(1045, 32), vec2(1054, 34), vec2(1094, 52), vec2(1052, 44),
                 vec2(5, 2), 0.43, 0.144);
    ctTempleCornice(layer, p, vec2(1050, 43), vec2(1095, 53), 10.7, 0.47, 0.158, 0.73);
    ctTempleCornice(layer, p, vec2(997, 48), vec2(1052, 41), 11.9, 0.83, 0.126, 0.66);
    ctTempleChip(layer, p, vec2(1005, 45), vec2(3.8, 2.2), -1.40, 0.69, 0.133);
    ctTempleChip(layer, p, vec2(1035, 37), vec2(6.7, 3.0), -0.54, 0.77, 0.128);
    ctTempleChip(layer, p, vec2(1042, 32), vec2(3.7, 2.3), -1.14, 0.73, 0.122);
    ctTempleChip(layer, p, vec2(1049, 34), vec2(4.6, 2.1), 1.03, 0.61, 0.139);
    ctTempleChip(layer, p, vec2(1073, 43), vec2(4.7, 2.0), -1.39, 0.52, 0.141);

    ctTempleSlab(layer, p, vec2(957, 190), vec2(1051, 194), vec2(1049, 219), vec2(952, 215),
                 vec2(9, 3), 0.50, 0.143);
    ctTempleSlab(layer, p, vec2(1051, 194), vec2(1113, 195), vec2(1107, 224), vec2(1049, 219),
                 vec2(7, 3), 0.29, 0.155);
    ctTempleCornice(layer, p, vec2(955, 188), vec2(1054, 192), 8.7, 0.65, 0.133, 0.66);
    ctTempleCornice(layer, p, vec2(1054, 192), vec2(1114, 193), 7.5, 0.37, 0.147, 0.78);
    ctTempleGarden(layer, p, vec2(948, 188), vec2(1057, 193), 9.6, 0.16);
    ctTempleGarden(layer, p, vec2(1041, 194), vec2(1103, 197), 10.1, 0.158);
    ctTempleChip(layer, p, vec2(1066, 205), vec2(6.4, 3.3), -0.75, 0.55, 0.13);

    // Nave and small vaulted appendages: a recessed portal faces the staircase.
    ctTempleRotunda(layer, p, vec2(901, 216), vec2(19.7, 14.3), 63.0, 1.5, 0.74, 0.12, 0.25);
    ctTempleColonnade(layer, p, vec2(918, 225), vec2(1068, 227), vec2(-4, 65), vec2(-8, 71),
                      8, 7.7, 0.75, 0.086, 0.08);
    ctTempleCopper(layer, p, vec2(991, 211), vec2(43, 24.9), 0.7, 0.97, 0.069);
    ctTempleCornice(layer, p, vec2(916, 218), vec2(1074, 220), 12.4, 0.81, 0.068, 0.59);
    ctTempleRotunda(layer, p, vec2(1080, 225), vec2(23.1, 14.8), 69.0, 0.6, 0.69, 0.115, 0.28);
    ctTempleGarden(layer, p, vec2(908, 217), vec2(952, 219), 8.1, 0.095);
    ctTempleGarden(layer, p, vec2(1029, 219), vec2(1072, 220), 9.3, 0.101);
    ctTempleGarden(layer, p, vec2(869, 285), vec2(943, 290), 13.6, 0.085);
    ctTempleGarden(layer, p, vec2(990, 299), vec2(1086, 302), 11.7, 0.09);
    ctTempleGarden(layer, p, vec2(1099, 301), vec2(1241, 286), 13.5, 0.12);
    ctTempleGarden(layer, p, vec2(1106, 293), vec2(1190, 281), 10.4, 0.15);
    ctTemplePortico(layer, p);

    ctTempleRotunda(layer, p, vec2(855, 284), vec2(34.2, 23.2), 86.0, -0.85, 0.78, 0.091, 0.32);
    ctTempleGarden(layer, p, vec2(816, 375), vec2(880, 370), 10.6, 0.085);
    ctTempleStair(layer, p);
    ctTempleGarden(layer, p, vec2(784, 425), vec2(904, 323), 5.1, 0.065);
    ctTempleGarden(layer, p, vec2(833, 424), vec2(942, 320), 5.0, 0.067);
    ctTempleChip(layer, p, vec2(850, 387), vec2(11.8, 4.2), -0.35, 0.61, 0.082);
    ctTempleChip(layer, p, vec2(855, 382), vec2(7.1, 4.7), -0.58, 0.64, 0.08);
    ctTempleObelisk(layer, p);
    ctTempleGarden(layer, p, vec2(908, 386), vec2(997, 388), 9.8, 0.08);

    ctTempleRotunda(layer, p, vec2(1068, 298), vec2(46.2, 27.2), 143.0, 0.1, 0.91, 0.060, 0.30);
    ctTempleFallenDrum(layer, p, vec2(997, 386), vec2(936, 442));
    ctTempleChip(layer, p, vec2(942, 434), vec2(8.9, 3.4), 0.63, 0.71, 0.066);
    ctTempleChip(layer, p, vec2(948, 442), vec2(7.8, 4.4), -0.22, 0.68, 0.068);
    ctTempleFallenDrum(layer, p, vec2(757, 389), vec2(789, 429));
}

void ctLamp(inout vec4 layer, vec2 p, vec2 c, float size) {
    if (!ctBounds(p, c - vec2(size * 2.0), c + vec2(size * 2.0))) return;
    vec2 q = (p - c) / vec2(size * 0.57, size);
    float f = length(q);
    float k = exp(-3.0 * f * f);
    float shape = ctRamp(0.66 - f, 0.18);
    ctPut(layer, vec3(0.01, 0.32, 0.36), k * 0.53);
    float cages = smoothstep(0.17, 0.44, abs(cos(q.x * 6.3)));
    ctPut(layer, vec3(0.08, 0.83, 0.79) * (0.57 + 0.43 * k), (0.31 + 0.52 * cages) * shape);
}

float ctArcadeOpening(vec2 uv, float offset, float width, float shoulder, bool rectangular) {
    float x = (uv.x - offset) / width;
    if (rectangular) return max(abs(x) - 1.0, (shoulder - uv.y) / max(0.12, shoulder));
    float y = (uv.y - shoulder) / (shoulder - 0.09);
    return length(vec2(x, min(y, 0.0))) - 1.0;
}

void ctArcadeCoping(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 backA, vec2 backB,
                   float thickness, float light, float haze, float damage) {
    if (!ctBounds(p, min(min(a, b), min(backA, backB)) - 5.0,
                     max(max(a, b), max(backA, backB)) + vec2(5.0, thickness * 2.8))) return;
    vec2 along = normalize(b - a);
    float x = dot(p - a, along);
    float span = length(b - a);
    float y = ctCross(along, p - a) * (along.x < 0.0 ? -1.0 : 1.0);
    float edge = ctNoise(p * vec2(0.44, 0.18));
    float breakup = ctNoise(vec2(p.x * 0.16, a.y * 0.07));
    float lost = damage * pow(ctNoise(vec2(x * 0.235, a.y * 0.34)), 3.1);
    float bottom = thickness - (1.2 * edge + thickness * 0.33 * lost);
    float field = max(edge, 0.35 + 0.65 * breakup);
    float slab = ctQuadMask(p, a, b, backB, backA);
    if (slab > 0.001) {
        vec2 uv = ctProjectedUV(p, a, b, backB, backA);
        float block = span / 9.0;
        float joint = abs(fract(uv.x * block + (edge - 0.5) * 0.095) - 0.5);
        float gaps = 1.0 - smoothstep(0.019, 0.071, joint);
        float facet = 0.83 + 0.24 * ctHash(vec2(floor(uv.x * block + 0.5), a.x));
        float stain = smoothstep(0.42, 0.72, ctNoise(p * vec2(0.194, 0.12)));
        float cut = smoothstep(0.52, 0.88, uv.y + (edge - 0.46) * 0.12);
        vec3 rock = ctTempleStone(p, light * 1.08, haze) * (facet - 0.28 * gaps - 0.13 * cut);
        rock += vec3(0.09, 0.105, 0.094) * exp(-abs(y + 0.83) * 1.6) * light * (1.0 - lost);
        ctPut(layer, mix(rock, vec3(0.22, 0.263, 0.148), stain * 0.63), slab);
    }
    float supporting = ctRamp(min(min(x - 1.0, span - x - 1.0), min(y - bottom + 0.9, thickness * 1.22 - y)), 0.58);
    if (supporting > 0.001)
        ctPut(layer, ctTempleStone(p, light * 0.18, haze) * (0.63 + 0.16 * edge), supporting);
    float lip = ctRamp(min(min(x, span - x), min(y + 0.6 - edge * damage, bottom - y)), 0.65);
    if (lip > 0.001) {
        vec3 fascia = ctTempleStone(p, light * 0.57, haze);
        float tone = 0.81 + 0.22 * exp(-ctSquare((y - thickness * 0.17) * 0.86))
                           + 0.27 * exp(-ctSquare((y - thickness * 0.66) * 0.74))
                           - 0.31 * exp(-ctSquare((y - thickness * 0.82) * 0.66));
        float joint = 1.0 - smoothstep(0.21, 0.67, abs(fract((x + 0.48 * edge) * 0.114) - 0.5) * 9.0);
        ctPut(layer, fascia * (tone - 0.17 * joint), lip);
    }
    float strands = ctNoise(vec2(x * 0.62 + y * 0.10, a.y * 0.095));
    float reach = damage * (thickness * 0.34 + 30.0 * pow(breakup, 2.7)) * (0.47 + 0.63 * strands);
    float moss = ctRamp(min(min(x, span - x), min(y + 1.7, reach - y)), 0.76);
    moss *= smoothstep(0.53, 0.73, field * 0.61 + 0.39 * strands);
    if (moss > 0.001) {
        vec3 algae = mix(vec3(0.072, 0.103, 0.061), vec3(0.38, 0.39, 0.157), edge * (0.68 + 0.32 * light));
        ctPut(layer, mix(algae, vec3(0.085, 0.236, 0.289), haze), moss * 0.94);
    }
}

void ctArcadeBay(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 c, vec2 d,
                 vec2 recede, float width, float shoulder, float light, float haze, bool rectangular) {
    if (!ctBounds(p, min(min(a, b), min(c, d)) - 2.0, max(max(a, b), max(c, d)) + 2.0)) return;
    float face = ctQuadMask(p, a, b, c, d);
    if (face <= 0.001) return;
    vec2 uv = ctProjectedUV(p, a, b, c, d);
    vec2 back = ctProjectedUV(p - recede, a, b, c, d);
    float grit = ctNoise(p * 0.31);
    float seed = ctHash(a * 0.22 + b * 0.051);
    float bias = (seed - 0.5) * 0.14;
    float damaged = 1.0 - smoothstep(0.05, 0.20, haze);
    float spall = (grit - 0.40) * (0.042 + 0.068 * damaged);
    float brokenEdge = pow(ctNoise(p * 0.127 + a * 0.054), 3.3) * damaged;
    float arch = ctArcadeOpening(uv, 0.50 + bias * (1.0 - uv.y * 0.63), width, shoulder, rectangular);
    float rearArch = ctArcadeOpening(back, 0.50 + bias * 0.70, width * (0.91 + seed * 0.14), shoulder + 0.014, rectangular);
    float frontStone = ctRamp(arch + spall - 0.19 * brokenEdge, 0.032);
    float rearMaterial = ctRamp(rearArch, 0.038);
    vec3 interior = ctTempleStone(p + recede, light * 0.22, haze);
    float underVault = 1.0 - smoothstep(shoulder - 0.16, shoulder + 0.10, uv.y);
    interior *= 0.70 + 0.36 * smoothstep(shoulder - 0.15, shoulder + 0.38, uv.y) - 0.28 * underVault;
    float backLine = exp(-abs(rearArch - 0.025) * 13.1);
    interior += vec3(0.058, 0.087, 0.091) * backLine;
    ctPut(layer, interior, face * (1.0 - frontStone) * rearMaterial);

    vec3 stone = ctTempleStone(p, light * mix(0.78, 1.0, 1.0 - smoothstep(0.0, 0.22, uv.y)), haze);
    float shoulderStone = 1.0 - smoothstep(0.26, 0.39, abs(uv.y - shoulder));
    float archivolt = exp(-abs(arch - 0.066) * 12.8) * shoulderStone;
    float molding = exp(-abs(arch - 0.025) * 37.0) * shoulderStone;
    float undercut = exp(-abs(arch - 0.157) * 21.0) * shoulderStone;
    float angle = atan(uv.x - 0.50 - bias * (1.0 - uv.y * 0.63), max(0.013, shoulder - uv.y));
    float pairedJoints = 1.0 - smoothstep(0.06, 0.26, abs(fract(angle * 3.65 + 0.51) - 0.5));
    float blocks = 1.0 - smoothstep(0.020, 0.062, abs(fract(uv.y * 7.4 + grit * 0.064) - 0.5));
    float lower = smoothstep(0.43, 0.93, uv.y);
    float shadow = 0.82 - 0.25 * lower * ctNoise(p * 0.10);
    float profile = rectangular ? 0.04 : archivolt * (0.35 - 0.37 * pairedJoints);
    stone *= shadow + profile - blocks * 0.21 - 0.14 * undercut + 0.18 * brokenEdge;
    stone += vec3(0.23, 0.155, 0.075) * molding * light;
    ctPut(layer, stone, face * frontStone);
}

void ctArcadeCrackedPier(inout vec4 layer, vec2 p, vec2 a, vec2 b, float width,
                        float light, float haze, float broken) {
    if (!ctBounds(p, min(a, b) - vec2(width * 1.45 + 2.0, 3.0),
                     max(a, b) + vec2(width * 1.45 + 2.0, 5.0))) return;
    vec2 axis = normalize(b - a);
    float span = length(b - a);
    float y = dot(p - a, axis);
    float x = ctCross(p - a, axis);
    float u = clamp(y / span, 0.0, 1.0);
    float crown = 1.0 - smoothstep(0.045, 0.16, u);
    float base = smoothstep(0.85, 0.98, u);
    float step = smoothstep(0.36, 0.49, u) * (1.0 - smoothstep(0.61, 0.79, u));
    x -= broken * width * 0.11 * step;
    float grain = ctNoise(p * 0.15);
    float abacus = 1.0 - smoothstep(0.032, 0.062, u);
    float echinus = exp(-ctSquare((u - 0.100) * 38.0));
    float radius = width * (0.73 + 0.13 * crown + 0.14 * abacus + 0.09 * echinus + 0.31 * base + 0.07 * u);
    float silhouette = ctRamp(min(min(y, span - y), radius - abs(x) - 0.58 * grain), 0.64);
    if (silhouette <= 0.001) return;
    float theta = asin(clamp(x / radius, -0.998, 0.998));
    float spall = smoothstep(0.26, 0.64, ctNoise(p * 0.45));
    float fracture = min(abs(u - 0.285 + 0.008 * x + 0.038 * grain),
                         abs(u - 0.575 - 0.009 * x + 0.042 * spall));
    float fault = broken * exp(-fracture * (57.0 + 88.0 * spall)) * (0.48 + 0.52 * spall);
    float surface = 0.21 + 0.79 * max(0.0, cos(theta + 0.64));
    float grooves = 0.85 + 0.15 * cos(theta * 15.0 + 1.0);
    float band = exp(-ctSquare((u - 0.061) * 58.0)) + 0.72 * echinus
               + 0.88 * exp(-ctSquare((u - 0.945) * 49.0));
    float joint = exp(-ctSquare((u - 0.126) * 51.0));
    vec3 stone = ctTempleStone(p, light * surface, haze);
    stone *= mix(grooves, 1.0, max(crown, base)) * (1.0 - fault * 0.73 - joint * 0.18);
    stone += vec3(0.26, 0.16, 0.075) * band * surface * light;
    ctPut(layer, stone, silhouette * (1.0 - fault * smoothstep(0.42, 0.89, abs(x / radius))));
}

void ctInnerTerrace(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(1116, 330), vec2(1356, 422))) return;
    const vec2 rim[8] = vec2[8](vec2(1121, 395), vec2(1177, 391), vec2(1229, 387), vec2(1283, 381),
                               vec2(1329, 367), vec2(1347, 354), vec2(1340, 346), vec2(1321, 341));
    for (int i = 6; i >= 0; --i) {
        vec2 a = rim[i];
        vec2 b = rim[i + 1];
        vec2 rear = vec2(-3.0, -9.0 + float(i) * 0.52);
        vec2 depth = vec2(-2.0, 14.0 + float(6 - i));
        ctTempleSlab(layer, p, a, b, b + depth, a + depth,
                     vec2(max(2.0, length(b - a) / 11.0), 2.0), 0.25, 0.105);
        ctArcadeCoping(layer, p, a, b, a + rear, b + rear, 5.0, 0.63, 0.09, 0.57);
        if (i <= 3) ctTempleGarden(layer, p, a + vec2(0, -3), b + vec2(0, -3), 11.1, 0.103);
    }
}

void ctArcadeLantern(inout vec4 layer, vec2 p, vec2 center) {
    if (!ctBounds(p, center - vec2(15, 22), center + vec2(15, 20))) return;
    vec2 q = p - center;
    float radius = length(q / vec2(9.3, 10.3));
    float glow = exp(-ctSquare(length(q / vec2(10.0, 12.5))) * 2.1);
    float taper = smoothstep(-1.58, -0.91, q.y / 10.3) * (1.0 - smoothstep(0.43, 0.83, q.y / 10.3));
    ctPut(layer, vec3(0.054, 0.33, 0.35), glow * 0.71);
    vec3 metal = ctTempleStone(p, 0.66 * (0.40 + 0.60 * exp(-ctSquare((q.x + 3.0) * 0.22))), 0.054);
    metal *= vec3(1.02, 0.79, 0.51);
    float roof = 1.0 - smoothstep(0.78, 1.08, length((q + vec2(0.0, 7.8)) / vec2(9.9, 8.8)));
    ctPut(layer, metal, roof);
    float glass = (1.0 - smoothstep(0.75, 1.02, radius)) * taper;
    float bars = smoothstep(0.28, 0.62, abs(sin(q.x * 0.56)));
    ctPut(layer, mix(vec3(0.068, 0.245, 0.249), vec3(0.243, 0.742, 0.738), (0.21 + 0.65 * bars) * glow),
          glass * 0.97);
    ctPut(layer, metal * 0.69, 1.0 - smoothstep(0.78, 1.05, length((q - vec2(0.0, 7.8)) / vec2(10.2, 3.1))));
    ctTempleChip(layer, p, center - vec2(0, 17.2), vec2(2.8, 1.6), 0.42, 0.51, 0.056);
}

void ctArcadeFoot(inout vec4 layer, vec2 p, vec2 foot, float width, float shade) {
    if (!ctBounds(p, foot - vec2(width * 1.40, width * 0.79), foot + vec2(width * 1.50, width * 0.91))) return;
    vec2 a = foot + vec2(-width, -4);
    vec2 b = foot + vec2(width, 1);
    vec2 rear = vec2(width * 0.33, -width * 0.60);
    vec2 drop = vec2(-1, width * 0.49);
    vec2 shadow = (p - foot - vec2(width * 0.10, width * 0.26)) / vec2(width * 1.20, width * 0.68);
    ctPut(layer, vec3(0.074, 0.104, 0.105), exp(-dot(shadow, shadow) * 2.3) * 0.43);
    ctTempleSlab(layer, p, b, b + rear, b + rear + drop, b + drop, vec2(2, 2), shade * 0.47, 0.068);
    ctTempleSlab(layer, p, a, b, b + drop, a + drop, vec2(3, 2), shade * 0.62, 0.058);
    ctArcadeCoping(layer, p, a, b, a + rear, b + rear, width * 0.14, shade, 0.059, 0.50);
}

void ctArcadeBridge(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(516, 300), vec2(828, 445))) return;
    const vec2 rim[6] = vec2[6](vec2(551, 345), vec2(603, 337), vec2(645, 334),
                                vec2(666, 330), vec2(729, 324), vec2(805, 317));
    const vec2 foot[6] = vec2[6](vec2(560, 428), vec2(606, 424), vec2(650, 428),
                                 vec2(675, 419), vec2(735, 398), vec2(804, 379));
    for (int i = 0; i < 5; ++i) {
        if (i == 2) continue;
        vec2 a = rim[i];
        vec2 b = rim[i + 1];
        vec2 rear = vec2(5.0 + float(i) * 0.4, -7.3);
        float width = 0.38 + 0.033 * ctHash(vec2(a.x, b.x));
        float shoulder = 0.12 + 0.079 * ctHash(vec2(a.y, b.x));
        ctArcadeBay(layer, p, a + vec2(0, 7), b + vec2(0, 7), foot[i + 1], foot[i], rear,
                    width, shoulder, 0.62, 0.098 + float(i) * 0.012, true);
        ctArcadeCoping(layer, p, a, b, a + rear, b + rear, 10.1 - float(i) * 0.87, 0.67,
                      0.11, 0.55 + 0.28 * ctHash(a));
    }
    for (int i = 0; i < 6; ++i) {
        float light = 0.59 - float(i) * 0.012;
        ctArcadeCrackedPier(layer, p, rim[i] + vec2(0, 7), foot[i], 10.3 - float(i) * 0.47,
                            light, 0.10 + 0.011 * float(i), 0.61);
    }
    ctArcadeCoping(layer, p, vec2(527, 347), rim[0], vec2(534, 337), rim[0] + vec2(6, -7),
                  10.2, 0.73, 0.105, 0.77);
    ctTempleChip(layer, p, vec2(541, 356), vec2(6, 3.4), 0.66, 0.52, 0.11);
    ctTempleGarden(layer, p, vec2(541, 344), vec2(642, 332), 6.3, 0.116);
    ctTempleGarden(layer, p, vec2(664, 327), vec2(727, 323), 7.0, 0.115);
}

void ctArcadeEastBack(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(1283, 303), vec2(1474, 448))) return;
    const vec2 rim[7] = vec2[7](vec2(1292, 317), vec2(1338, 321), vec2(1372, 325), vec2(1404, 334),
                                vec2(1430, 341), vec2(1450, 352), vec2(1460, 363));
    const vec2 feet[7] = vec2[7](vec2(1287, 364), vec2(1334, 380), vec2(1366, 389), vec2(1397, 405),
                                 vec2(1421, 415), vec2(1441, 426), vec2(1450, 433));
    for (int i = 0; i < 6; ++i) {
        vec2 a = rim[i];
        vec2 b = rim[i + 1];
        vec2 rear = vec2(4.3 + float(i) * 0.35, -5.7 - float(i) * 0.43);
        float light = 0.44 + float(i) * 0.028;
        float haze = 0.23 - float(i) * 0.010;
        ctArcadeBay(layer, p, a + vec2(0, 4), b + vec2(0, 4), feet[i + 1], feet[i], rear,
                    0.368 + 0.031 * ctHash(b), 0.43, light, haze, false);
        ctArcadeCoping(layer, p, a, b, a + rear, b + rear, 5.6, light + 0.14, haze, 0.46);
    }
}

void ctArcadeEastFront(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(1131, 346), vec2(1474, 634))) return;
    const vec2 rim[8] = vec2[8](vec2(1162, 414), vec2(1237, 407), vec2(1294, 398), vec2(1344, 387),
                                vec2(1394, 376), vec2(1432, 366), vec2(1451, 358), vec2(1460, 363));
    const vec2 feet[8] = vec2[8](vec2(1155, 586), vec2(1227, 523), vec2(1282, 513), vec2(1332, 497),
                                 vec2(1381, 480), vec2(1420, 452), vec2(1441, 435), vec2(1450, 433));
    const vec2 back[8] = vec2[8](vec2(1159, 404), vec2(1233, 396), vec2(1288, 387), vec2(1335, 377),
                                 vec2(1383, 366), vec2(1420, 356), vec2(1452, 349), vec2(1460, 355));
    for (int i = 6; i >= 0; --i) {
        vec2 a = rim[i];
        vec2 b = rim[i + 1];
        vec2 d = feet[i];
        vec2 c = feet[i + 1];
        if (i == 0) a.x += 9.0;
        float light = 0.56 - 0.020 * float(i);
        float haze = 0.056 + 0.020 * float(i);
        vec2 rear = vec2(-6.5 - float(i) * 0.30, -5.1);
        float shoulder = 0.38 + 0.11 * ctHash(vec2(a.x, b.y));
        ctArcadeBay(layer, p, a + vec2(0, 10), b + vec2(0, 8), c, d, rear,
                    0.37 + 0.058 * ctHash(vec2(b.x, a.y)), shoulder, light, haze, false);
        if (i > 0 && i < 5) {
            vec2 spring = mix(a, d, shoulder + 0.017);
            float size = 10.8 - 1.24 * float(i);
            ctArcadeCrackedPier(layer, p, spring, d, size, light * 1.02, haze, 0.66);
            ctTempleCornice(layer, p, spring - vec2(size * 0.85, 1.0), spring + vec2(size * 0.78, -0.6),
                            size * 0.55, light * 1.02, haze, 0.58);
        }
        ctArcadeCoping(layer, p, rim[i], b, back[i], back[i + 1],
                      12.1 - float(i) * 1.18, 0.76 - 0.027 * float(i), haze, 0.78);
        if (i == 0 || i == 2 || i == 4) {
            ctTempleGarden(layer, p, rim[i] - vec2(0, 6), b - vec2(0, 6), 7.1 - 0.48 * float(i), haze);
        }
    }
    ctArcadeFoot(layer, p, vec2(1155, 593), 23.6, 0.67);
    ctArcadeCrackedPier(layer, p, vec2(1173, 426), vec2(1155, 589), 16.0, 0.75, 0.046, 0.99);
    ctTempleChip(layer, p, vec2(1164, 419), vec2(10, 5), -0.40, 0.68, 0.046);
    ctTempleChip(layer, p, vec2(1141, 597), vec2(11, 6), 0.26, 0.54, 0.047);
}

void ctArcadeBrokenFront(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(1019, 343), vec2(1158, 621))) return;
    const vec2 rim[4] = vec2[4](vec2(1048, 355), vec2(1084, 371), vec2(1110, 388), vec2(1139, 412));
    const vec2 inside[4] = vec2[4](vec2(1062, 351), vec2(1097, 367), vec2(1126, 384), vec2(1150, 405));
    const vec2 feet[4] = vec2[4](vec2(1043, 465), vec2(1073, 500), vec2(1093, 536), vec2(1112, 571));
    ctArcadeBay(layer, p, rim[0] + vec2(0, 6), rim[1] + vec2(0, 7), feet[1], feet[0],
                vec2(10, -3.6), 0.33, 0.44, 0.62, 0.053, false);
    ctArcadeBay(layer, p, rim[1] + vec2(0, 6), rim[3] + vec2(0, 7), feet[3], feet[1],
                vec2(11.2, -5.1), 0.39, 0.44, 0.60, 0.047, false);
    ctArcadeCrackedPier(layer, p, vec2(1054, 366), vec2(1043, 461), 9.1, 0.67, 0.052, 0.61);
    ctArcadeCrackedPier(layer, p, vec2(1085, 382), vec2(1073, 500), 10.4, 0.63, 0.048, 0.78);
    ctArcadeFoot(layer, p, vec2(1110, 573), 14.2, 0.53);
    ctArcadeCrackedPier(layer, p, vec2(1137, 422), vec2(1112, 574), 15.4, 0.64, 0.046, 0.93);
    for (int i = 0; i < 3; ++i) {
        ctArcadeCoping(layer, p, rim[i], rim[i + 1], inside[i], inside[i + 1],
                       8.3 + 1.2 * float(i), 0.81, 0.049, 0.89);
    }
    ctTempleChip(layer, p, vec2(1137, 421), vec2(13, 5.1), -0.44, 0.76, 0.051);
    ctTempleChip(layer, p, vec2(1120, 541), vec2(5.8, 8.6), 0.46, 0.53, 0.055);
    ctTempleGarden(layer, p, vec2(1047, 359), vec2(1086, 374), 9.0, 0.052);
    ctTempleGarden(layer, p, vec2(1093, 376), vec2(1118, 392), 7.6, 0.055);
    ctArcadeLantern(layer, p, vec2(1087, 509));
}

void ctArcades(inout vec4 layer, vec2 p) {
    ctArcadeBridge(layer, p);
    ctArcadeEastBack(layer, p);
    ctArcadeEastFront(layer, p);
    ctArcadeBrokenFront(layer, p);

    ctTemplePier(layer, p, vec2(669, 187), vec2(673, 296), 8.1, 0.63, 0.33, 24.0);
    ctTemplePier(layer, p, vec2(770, 215), vec2(771, 303), 6.2, 0.61, 0.30, 36.0);
    ctArcadeFoot(layer, p, vec2(1269, 393), 27.0, 0.65);
    ctArcadeCrackedPier(layer, p, vec2(1300, 193), vec2(1268, 393), 19.0, 0.88, 0.064, 0.54);
    ctTempleCornice(layer, p, vec2(1272, 186), vec2(1328, 189), 8.0, 0.95, 0.06, 0.48);
    ctTempleCornice(layer, p, vec2(1278, 194), vec2(1321, 197), 7.0, 0.77, 0.061, 0.45);
    ctTempleCornice(layer, p, vec2(1284, 205), vec2(1315, 208), 5.0, 0.66, 0.06, 0.52);
    ctCoralCoil(layer, p, vec2(1300, 194), vec2(1266, 391), 10.9);
    ctLamp(layer, p, vec2(934, 371), 6.4);
    ctLamp(layer, p, vec2(1230, 349), 6.1);
}

void ctFlankGallery(inout vec4 layer, vec2 p, vec2 a, vec2 b, vec2 d, vec2 c,
                    int bays, float scale, float exposure) {
    if (!ctBounds(p, min(min(a, b), min(c, d)) - vec2(21.0), max(max(a, b), max(c, d)) + vec2(22.0))) return;
    vec2 inset = vec2(9.0, -3.0) * scale;
    ctPanel(layer, p, a + inset, b + inset, c + inset, d + inset, vec2(float(bays) * 2.4, 7), 0.20 * exposure, 0.075);
    for (int i = 0; i < 10; ++i) {
        if (i >= bays) break;
        float u = float(i) / float(bays - 1);
        float bayU=u+sin(float(i)*6.17+a.y)*.017*sin(u*3.14159);
        vec2 top = mix(a, b, bayU);
        vec2 foot = mix(d, c, bayU);
        float seed = ctHash(vec2(i, a.x));
        float width = scale * (11.7 + seed * 2.3);
        if (i < bays - 1) {
            vec2 nextTop = mix(a, b, u + 1.0 / float(bays - 1));
            vec2 nextFoot = mix(d, c, u + 1.0 / float(bays - 1));
            vec2 windowTop = mix(top, nextTop, 0.51) + inset*.42;
            vec2 windowFoot = mix(foot, nextFoot, 0.51) + inset*.42;
            vec2 sill = mix(windowTop, windowFoot, 0.96);
            vec2 lintel = mix(windowTop, windowFoot, 0.11);
            if (ctBounds(p, min(lintel, sill) - 2.*width, max(lintel, sill) + 2.*width)) {
                vec2 axis = sill - lintel;
                float y = dot(p - lintel, axis) / dot(axis, axis);
                float x = abs(ctCross(normalize(axis), p - lintel));
                float radius=length(nextTop-top)*.306;
                float below=y*length(axis),arched=length(vec2(x,min(0.,below-radius)));
                float cut=min(radius-arched,(1.-y)*length(axis));
                vec3 jamb=ctMasonry(p,vec2(atan(x,max(.1,radius-below))*6.,below/8.),.51*exposure,.09);
                ctPut(layer,jamb*(.76+.31*exp(-abs(cut+2.)*.61)),
                      ctRamp(cut+3.6*scale,.65)*ctRamp((1.-y)*length(axis),.8));
                float inner=dot(p-lintel,normalize(vec2(axis.y,-axis.x)));
                float reveal=exp(-abs(cut-2.9)*.38)*smoothstep(0.,7.,inner);
                vec3 dark=vec3(.023,.054,.064)+vec3(.17,.17,.14)*reveal+
                          vec3(.024,.053,.061)*ctNoise(p*.10)*smoothstep(.15,.95,y);
                ctPut(layer,dark,ctRamp(cut,.68));
                if (seed > 0.68) ctLamp(layer, p, mix(lintel, sill, 0.63), 5.6 * scale);
            }
        }
        ctColumn(layer, p, top + vec2(5, 1) * scale, foot + vec2(6, 4) * scale,
                 width, 0.28 * exposure, 0.07, 120.0 + float(i));
        ctColumn(layer, p, top, foot, width * (0.81+.11*seed), exposure * (0.78 + seed * 0.21), 0.065, 20.0 + float(i));
    }
    ctBand(layer, p, d + vec2(-4, -3), c + vec2(5, -3), 8.0 * scale, exposure * 0.63, 0.085);
    ctBand(layer, p, a + vec2(-5, -8), b + vec2(5, -8), 10.0 * scale, exposure * 0.79, 0.075);
    // Salt, small attached shells and hanging growth follow damaged joints.
    vec2 edge=b-a;
    float along=dot(p-a,edge)/dot(edge,edge);
    float depth=ctCross(normalize(edge),p-a)+7.4;
    if(along>=0.&&along<=1.&&depth>-5.&&depth<25.){
        float rough=ctNoise(p*.46);
        float patchDensity=ctNoise(vec2(along*33.,a.x))*.57+ctNoise(vec2(along*88.,19.))*.43;
        float taper=3.+19.*smoothstep(.51,.79,patchDensity);
        float growth=(1.-smoothstep(taper-3.,taper+1.,depth))*smoothstep(-4.,.3,depth)
                    *smoothstep(.49,.70,patchDensity+.16*rough-depth*.007);
        vec3 turf=mix(vec3(.119,.15,.11),vec3(.34,.31,.185),rough);
        ctPut(layer,turf*(.65+.52*exp(-abs(depth)*.23)),growth*.86);
    }
}

void ctFlankCopper(inout vec4 layer, vec2 p) {
    vec2 center = vec2(1636, 433);
    vec2 radius = vec2(132, 52);
    vec2 q = (p - center) / radius;
    q.y -= q.x * 0.34 + .46*pow(clamp((p.x-1520.)/220.,0.,1.),2.4);
    if (abs(q.x) > 1.025 || q.y < -1.045 || q.y > 0.36) return;
    float merid = sqrt(max(0.0, 1.0 - q.x * q.x));
    float dome = max(length(vec2(q.x, min(q.y, 0.0))) - 1.0, q.y - merid * 0.30);
    float mask = 1.0 - smoothstep(-0.018, 0.018, dome);
    float z = sqrt(max(0.001, 1.0 - dot(vec2(q.x, min(q.y, 0.0)), vec2(q.x, min(q.y, 0.0)))));
    float theta = atan(q.x, max(0.06, z));
    vec3 normal = normalize(vec3(q.x, -q.y, z));
    float lighting = 0.31 + 0.73 * max(0.0, dot(normal, normalize(vec3(-0.49, 0.68, 0.54))));
    float shine = pow(max(0.0, dot(normal, normalize(vec3(-0.58, 0.60, 0.71)))), 13.0);
    vec2 tile = vec2(theta * 3.05, (q.y - z * 0.29) * 2.7);
    float seam = min(abs(fract(tile.x + 0.5) - 0.5), abs(fract(tile.y + 0.5) - 0.5));
    float weather = ctStoneNoise(p * 1.2);
    float corrosion = smoothstep(0.35, 0.73, 0.75 * ctNoise(p * 0.039) + 0.25 * weather);
    vec3 copper = mix(vec3(0.41, 0.27, 0.15), vec3(0.085, 0.14, 0.123), corrosion);
    float patina = 0.61 + 0.59 * weather + 0.14 * ctHash(floor(tile));
    vec3 color = copper * lighting * patina + vec3(0.81, 0.46, 0.20) * shine * patina;
    color *= 0.73 + 0.27 * smoothstep(0.012, 0.095, seam);
    color += exp(-ctSquare((q.y - merid * 0.30 + 0.043) * 33.0)) * vec3(0.29, 0.18, 0.098);
    float pits=ctNoise(p*.51)+.25*ctNoise(p*1.61);
    float verdigris=smoothstep(.57,.77,.47*ctNoise(p*.066)+.33*ctNoise(p*.185)+.20*pits);
    color=mix(color,vec3(.11,.24,.235)*(.49+.74*weather),verdigris*.74);
    float hammered=ctNoise(p*.78)+.31*ctNoise(p*1.45);
    color+=vec3(.59,.51,.36)*shine*smoothstep(.49,.81,hammered);
    color+=vec3(.23,.16,.085)*exp(-abs(seam-.021)*69.)*(.47+.53*lighting);
    float band=q.y-merid*.30;
    if(band>-.158&&band<-.024){
        vec2 key=fract(vec2(theta*23.,(band+.158)/.134));
        float fret=min(abs(key.y-.15),max(abs(key.x-.47)-.26,abs(key.y-.52)-.22));
        color=mix(vec3(.049,.131,.15),vec3(.245,.40,.38),exp(-abs(fret)*15.))*(.59+.66*weather);
    }
    ctPut(layer, color, mask);
}

// The turtle's dark shell crosses the pavilion skyline. The rear fin sits
// behind the carapace and the near fin crosses its lower rim.
void ctPavilionTurtle(inout vec4 layer,vec2 p,float t){
    vec2 q=p-vec2(1658.,382.)-vec2(-.67*t,.31*sin(t*.86));
    if(abs(q.x)>47.||abs(q.y)>26.)return;
    float axis=q.y-.55*q.x;
    float shell=length(vec2(q.x/22.8,axis/8.5));
    float grain=ctNoise(p*.73);
    vec2 fin=q-vec2(-4.4,7.);
    float wing=length(vec2((fin.x+.73*fin.y)/3.3,fin.y/7.6));
    vec2 neck=q-vec2(-20.,-12.);
    float head=length(vec2(neck.x/6.1,(neck.y-.47*neck.x)/4.3));
    vec2 rear=q-vec2(17.,12.);
    float leg=length(vec2(rear.x/7.5,(rear.y-.8*rear.x)/2.0));
    vec3 hide=mix(vec3(.18,.18,.16),vec3(.53,.48,.38),grain);
    ctPut(layer,hide,1.-smoothstep(.85,1.12,min(head,min(leg,wing))));
    vec3 shellTone=mix(vec3(.10,.12,.115),vec3(.40,.36,.28),
        clamp(.35-.037*axis+.3*(grain-.5),0.,1.));
    shellTone+=exp(-abs(shell-.88)*16.)*vec3(.17,.16,.12);
    ctPut(layer,shellTone,1.-smoothstep(.94,1.06,shell));
}

void ctFlanks(inout vec4 layer, vec2 p) {
    if (p.x < 650.0 && p.y > 240.0) {
        ctColonnade(layer, p, vec2(-30, 325), vec2(106, 312), 49.0, 51.0, 8, 8.0, 0.64, 0.37);
        ctPanel(layer, p, vec2(139, 360), vec2(239, 342), vec2(299, 326), vec2(199, 328), vec2(8, 6), 0.73, 0.29);
        ctColonnade(layer, p, vec2(237, 354), vec2(303, 334), 72.0, 59.0, 4, 8.1, 0.52, 0.34);
        ctColonnade(layer, p, vec2(139, 367), vec2(239, 348), 72.0, 67.0, 4, 10.1, 0.58, 0.27);
        ctBand(layer, p, vec2(137, 351), vec2(241, 333), 13.0, 0.73, 0.29);
        ctBand(layer, p, vec2(240, 335), vec2(300, 323), 11.0, 0.61, 0.32);
        ctObelisk(layer, p, vec2(105, 389), vec2(117, 446), 9.0, 0.61, 0.27);
        ctLamp(layer, p, vec2(287, 380), 5.2);

        ctColonnade(layer, p, vec2(553, 277), vec2(637, 274), 35.0, 35.0, 7, 5.0, 0.70, 0.25);
        ctRoof(layer, p, vec2(545, 273), vec2(643, 269), vec2(644, 264), vec2(560, 260), 12.0, 0.81, 0.22);

        vec2 leftEave=vec2(16,486),rightEave=vec2(175,447);
        vec2 sideEave=vec2(216,453);
        vec2 baseLeft=ctFlankFoot(leftEave,117.),baseRight=ctFlankFoot(rightEave,92.);
        vec2 apron=vec2(10.,6.);
        ctPanel(layer,p,baseLeft,baseRight,baseRight+apron,baseLeft+apron,vec2(15,2),.62,.14);
        ctBand(layer,p,baseLeft+apron,baseRight+apron,10.,.53,.10);
        ctStairs(layer,p,baseLeft+apron,baseRight+apron,baseRight+vec2(24.,25.),
                 baseLeft+vec2(23.,28.),.55,.14);
        vec2 quayA=vec2(202,518),quayB=vec2(278,541);
        ctPanel(layer,p,quayA,quayB,quayB+vec2(22,10),quayA+vec2(22,10),
                vec2(15,2),.55,.14);
        ctBand(layer,p,quayA+vec2(22,10),quayB+vec2(22,10),9.,.46,.14);
        ctColumn(layer,p,vec2(271,508),vec2(278,543),6.1,.48,.15,30.);
        ctColumn(layer,p,vec2(229,509),vec2(236,536),5.9,.50,.15,32.);
        if(p.x>231.&&p.x<272.){
            float u=(p.x-231.)/41.;
            float sag=515.+5.8*4.*u*(1.-u);
            float links=length(vec2((fract(u*10.)-.5)*1.6,(p.y-sag)*1.1));
            ctPut(layer,vec3(.12,.143,.147),1.-smoothstep(.22,.55,abs(links-.7)));
        }
        ctColonnade(layer,p,rightEave,sideEave,92.,
                    85.,3,9.3,.38,.17);
        ctColonnade(layer,p,leftEave,rightEave,117.,
                    92.,5,11.7,.52,.12);
        ctPanel(layer,p,vec2(-38,464),vec2(16,486),vec2(84,435),
                vec2(34,426),vec2(7,6),.47,.15);
        ctPanel(layer,p,vec2(34,426),vec2(84,435),vec2(175,447),
                vec2(128,433),vec2(6,6),.48,.14);
        ctPanel(layer,p,vec2(16,484),vec2(84,435),vec2(175,447),
                vec2(98,466),vec2(12,4),.42,.13);
        ctBand(layer,p,vec2(16,481),vec2(84,433),3.8,.79,.14);
        ctBand(layer,p,vec2(84,433),vec2(177,446),4.3,.67,.14);
        ctBand(layer,p,vec2(14,481),vec2(177,442),14.0,.72,.13);
        vec2 fasciaA=vec2(21,484),fasciaB=vec2(171,448);
        float fasU=ctQuadUV(p,fasciaA,fasciaB,fasciaA+vec2(0,8)).x;
        float fasV=p.y-mix(fasciaA.y,fasciaB.y,fasU);
        if(fasU>=0.&&fasU<1.&&fasV>0.&&fasV<6.){
            vec2 key=vec2(fract(fasU*23.),fasV/6.);
            float relief=abs(max(abs(key.x-.45)-.27,abs(key.y-.51)-.27));
            ctPut(layer,mix(vec3(.21,.19,.15),vec3(.49,.39,.24),exp(-relief*12.)),
                  .77);
        }
        ctBand(layer,p,vec2(14,489),vec2(177,450),4.2,.49,.12);

        ctRotunda(layer, p, vec2(466, 402), vec2(53, 33), 47.0, -4.0, 0.84, 0.14);
        ctStairs(layer, p, vec2(468, 445), vec2(502, 434), vec2(533, 452), vec2(495, 465), 0.70, 0.13);
        ctLamp(layer, p, vec2(485, 425), 6.1);
        ctLamp(layer, p, vec2(510, 417), 5.0);
        ctLamp(layer, p, vec2(347, 418), 5.6);
        ctLamp(layer, p, vec2(323, 419), 4.0);
    }
    if (p.x > 1308.0 && p.y > 183.0) {
        ctColonnade(layer, p, vec2(1483, 285), vec2(1572, 299), 70.0, 64.0, 6, 7.0, 0.61, 0.38);
        ctColonnade(layer, p, vec2(1520, 249), vec2(1598, 258), 40.0, 40.0, 6, 4.7, 0.63, 0.44);
        ctBand(layer, p, vec2(1510, 241), vec2(1599, 252), 10.0, 0.74, 0.42);
        ctColonnade(layer, p, vec2(1637, 204), vec2(1734, 215), 51.0, 57.0, 7, 6.1, 0.61, 0.42);
        ctRoof(layer, p, vec2(1629, 200), vec2(1740, 215), vec2(1747, 208), vec2(1637, 186), 8.0, 0.74, 0.42);
        ctObelisk(layer, p, vec2(1686, 227), vec2(1649, 346), 14.0, 0.79, 0.23);
        ctColonnade(layer, p, vec2(1516, 330), vec2(1709, 372), 53.0, 58.0, 11, 7.5, 0.62, 0.29);

        // The podium steps forward of the drum. Each face has one
        // pair of bearing lines shared by its posts, openings and coping.
        vec2 loA=vec2(1391,530),loB=vec2(1653,614),loC=vec2(1788,646);
        vec2 ftA=ctFlankFoot(loA,87.),ftB=ctFlankFoot(loB,105.),ftC=ctFlankFoot(loC,106.);
        ctFlankGallery(layer,p,loB,loC,ftB,ftC,3,1.27,.52);
        ctFlankGallery(layer,p,loA,loB,ftA,ftB,5,1.21,.66);
        vec2 deckA=loA-vec2(3.,14.),deckB=loB-vec2(0.,13.),deckC=loC-vec2(0.,13.);
        vec2 retreat=vec2(62.,-25.);
        ctPanel(layer,p,deckA,deckB,deckB+retreat,deckA+retreat,
                vec2(16,4),.64,.07);
        ctPanel(layer,p,deckB,deckC,deckC+retreat,deckB+retreat,
                vec2(8,4),.56,.08);
        ctBand(layer,p,deckA,deckB,12.,.73,.06);
        ctBand(layer,p,deckB,deckC,12.,.62,.07);
        vec2 upA=vec2(1493,450),upB=vec2(1607,483),upC=vec2(1775,513);
        vec2 baseA=ctFlankFoot(upA,59.),baseB=ctFlankFoot(upB,67.),baseC=ctFlankFoot(upC,69.);
        ctFlankGallery(layer,p,upB,upC,baseB,baseC,4,1.13,.68);
        ctFlankGallery(layer,p,upA,upB,baseA,baseB,3,1.04,.80);
        ctBand(layer,p,upA-vec2(6,14),upB-vec2(0,14),12.,.85,.065);
        ctBand(layer,p,upB-vec2(0,14),upC-vec2(-4,14),12.,.71,.07);
        // The circular roof bears on a continuous drum inside the polygonal
        // loggia. Its near edge and the roof share the same ellipse.
        float ringX=clamp((p.x-1636.)/132.,-1.,1.);
        float ringY=433.+17.68*ringX+15.6*sqrt(max(0.,1.-ringX*ringX))
                    +23.92*pow(clamp((p.x-1520.)/220.,0.,1.),2.4);
        float deckY=p.x<upB.x?mix(upA.y,upB.y,clamp((p.x-upA.x)/(upB.x-upA.x),0.,1.)):
                                 mix(upB.y,upC.y,clamp((p.x-upB.x)/(upC.x-upB.x),0.,1.));
        if(p.x>=1504.&&p.x<=1768.&&p.y>=ringY-.7&&p.y<deckY-10.){
            float h=p.y-ringY;
            float grain=ctStoneNoise(p);
            float mold=exp(-ctSquare((h-1.1)*.78))+exp(-ctSquare((h-4.8)*.88));
            float seams=abs(fract(atan(ringX,max(.01,sqrt(max(0.,1.-ringX*ringX))))*12.)-.5);
            vec3 drum=mix(vec3(.11,.16,.16),vec3(.39,.37,.30),grain)
                     *(.81+.19*smoothstep(.025,.11,seams));
            ctPut(layer,drum+vec3(.17,.141,.095)*mold,1.);
        }
        ctFlankCopper(layer, p);
        ctLamp(layer, p, vec2(1650, 540), 10.7);
        ctLamp(layer, p, vec2(1541, 628), 12.1);
        ctLamp(layer, p, vec2(1428, 584), 8.4);
        ctPut(layer, vec3(0.88, 0.43, 0.14), 0.81 * exp(-ctSquare((p.x - 1604.0) * 0.16) - ctSquare((p.y - 527.0) * 0.10)));
    }
}

vec4 cityFar(vec2 p, float t) {
    p = p * vec2(1760, 754) + vec2(0.36 * sin(t * 0.73), -0.25 * sin(t * 0.39));
    vec4 layer = vec4(0);
    ctFarDistrict(layer, p);
    return vec4(layer.rgb / max(layer.a, 0.0001), layer.a);
}

// The western ring is a retaining walk. The broken east end sits on the vent face.
void ctWestWalk(inout vec4 layer, vec2 p) {
    if (!ctBounds(p, vec2(334, 308), vec2(479, 554))) return;
    const vec2 outer[10] = vec2[10](vec2(435, 334), vec2(405, 344), vec2(381, 357), vec2(360, 374),
                                    vec2(347, 396), vec2(345, 416), vec2(360, 441), vec2(389, 465),
                                    vec2(430, 481), vec2(469, 489));
    const vec2 inner[10] = vec2[10](vec2(438, 325), vec2(415, 336), vec2(397, 348), vec2(382, 368),
                                    vec2(372, 388), vec2(375, 420), vec2(389, 437), vec2(422, 458),
                                    vec2(453, 469), vec2(481, 479));
    for (int i = 0; i < 9; ++i) {
        vec2 a = outer[i];
        vec2 b = outer[i + 1];
        vec2 d = a + vec2(-2.0 + 0.43 * float(i), 56.0 + 2.1 * float(i));
        vec2 c = b + vec2(-1.5 + 0.44 * float(i), 59.0 + 1.65 * float(i));
        float light = i > 5 ? 0.37 : 0.27;
        float haze = 0.08 + float(9 - i) * 0.009;
        if (i == 2 || i == 4 || i == 7 || i == 8) {
            ctArcadeBay(layer, p, a, b, c, d, vec2(8.0, -5.0), 0.24, 0.38, light, haze, false);
        } else {
            ctTempleSlab(layer, p, a, b, c, d, vec2(2, 5), light, haze);
        }
        ctArcadeCoping(layer, p, a, b, inner[i], inner[i + 1], 6.0 + 0.18 * float(i), 0.63 + 0.017 * float(i), haze,
                      0.78 - 0.026 * float(i));
    }
    ctTempleSlab(layer, p, outer[9], inner[9], vec2(477, 530), vec2(463, 542),
                 vec2(2, 5), 0.27, 0.081);
    ctTempleSlab(layer, p, vec2(435, 491), vec2(466, 500), vec2(463, 522), vec2(432, 513),
                 vec2(2, 2), 0.28, 0.096);
    ctTempleCornice(layer, p, vec2(435, 490), vec2(467, 498), 4.5, 0.54, 0.085, 0.85);
    ctTempleChip(layer, p, vec2(470, 484), vec2(7.4, 3.1), -0.38, 0.60, 0.086);
    ctTempleChip(layer, p, vec2(457, 486), vec2(5.3, 2.2), 0.44, 0.64, 0.088);
    ctTempleChip(layer, p, vec2(386, 464), vec2(5.9, 2.7), 0.55, 0.61, 0.101);
    ctTempleGarden(layer, p, vec2(367, 423), vec2(395, 441), 5.1, 0.094);
    ctTempleGarden(layer, p, vec2(415, 463), vec2(448, 470), 6.0, 0.088);
    ctLamp(layer, p, vec2(354, 417), 4.4);
}
vec4 cityNear(vec2 p, float t) {
    p = p * vec2(1760, 754) + vec2(0.36 * sin(t * 0.73), -0.25 * sin(t * 0.39));
    vec4 layer = vec4(0);
    ctMainTemple(layer, p);
    ctInnerTerrace(layer, p);
    ctArcades(layer, p);
    ctFlanks(layer, p);
    ctWestWalk(layer, p);
    return vec4(layer.rgb / max(layer.a, 0.0001), layer.a);
}

vec4 city(vec2 p, float t) {
    vec4 farLayer = cityFar(p, t);
    vec4 nearLayer = cityNear(p, t);
    float opacity = mix(farLayer.a, 1.0, nearLayer.a);
    vec3 premultiplied = mix(farLayer.rgb * farLayer.a, nearLayer.rgb, nearLayer.a);
    return vec4(premultiplied / max(opacity, 0.0001), opacity);
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

float rfRelief(vec2 p) {
    vec2 q = vec2(.82*p.x + .57*p.y, -.57*p.x + .82*p.y);
    return .53*rfNoise(p) + .27*rfNoise(2.17*q) +
           .13*rfNoise(4.63*q + 8.0) + .07*rfNoise(10.4*p - 7.0);
}

float rfRidge(vec2 p) {
    return 1.0 - abs(2.0*rfNoise(p) - 1.0);
}

vec2 rfRotate(vec2 p, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c*p.x - s*p.y, s*p.x + c*p.y);
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

vec2 rfMeasure(vec2 d) {
    return vec2(d.x*2.33546, d.y);
}

float rfCaustic(vec2 p, float t) {
    vec2 q = vec2(9.0*p.x, 24.0*p.y);
#if defined(DETAIL_LOOP_FRAMES)
    float phase = detailPhase(t);
    q += .24*vec2(sin(q.y*.77 - phase), cos(q.x*.8 + phase));
    float s = sin(q.x*1.74 + sin(q.y*1.6 + 2.0*phase)) +
              cos(q.y*1.86 - q.x*.39 + phase);
#else
    q += .24*vec2(sin(q.y*.77 - .72*t), cos(q.x*.8 + .73*t));
    float s = sin(q.x*1.74 + sin(q.y*1.6 + .72*t)) +
              cos(q.y*1.86 - q.x*.39 + .56*t);
#endif
    return pow(max(1.0 - abs(s), 0.0), 4.0) * (.4 + .6*rfNoise(1.2*q));
}

float rfCliffTop(float x) {
    float left = .076 + .31*x + .024*smoothstep(.29,.36,x);
    float east = .137 - .049*smoothstep(.892,.911,x);
    east += .152*(1.0-smoothstep(.864,.900,x));
    float distant = .267 + .024*cos((x-.39)*13.0);
    float wornEdge = .019*(rfRelief(vec2(x*53.0,13.0))-.5);
    wornEdge += .023*(rfNoise(vec2(x*17.0,20.0))-.5);
    return min(min(left,east),distant) + wornEdge;
}

float rfCliffRelief(vec2 q) {
    float bed = rfRelief(q);
    float erosion = rfRidge(q*vec2(2.75,.77) + vec2(9.7,2.6));
    return .74*bed + .26*erosion;
}

vec3 rfCliffTone(vec2 p, float edge) {
    float east = smoothstep(.72,.90,p.x);
    float cliffDepth = max(p.y-edge,0.0);
    float warp = rfRelief(p*vec2(25.0,14.0));
    float tilt = mix(-.72,1.3,east);
    vec2 gully = vec2(p.x*53.0 + p.y*tilt*11.0, p.y*8.4);
    gully += vec2(.94*(warp-.5),.63*rfNoise(gully*.5));
    float relief = rfCliffRelief(gully);
    float slope = relief-rfCliffRelief(gully-vec2(.19,.16));
    float flakes = rfRelief(p*vec2(201.0,137.0));
    float ledges = rfNoise(vec2(gully.x*.38,gully.y*4.9 + 1.38*relief));
    float light = clamp(.29 + .48*relief + 1.61*slope + .13*flakes,0.0,1.0);
    light *= mix(.67,1.0,smoothstep(.22,.51,relief));
    vec3 col = mix(vec3(.032,.090,.132),vec3(.114,.213,.257),light);
    float chips = smoothstep(.59,.83,ledges)*smoothstep(.36,.73,flakes);
    col += vec3(.060,.091,.115)*chips;
    float rim = exp(-cliffDepth*35.0);
    col += vec3(.085,.117,.132)*rim*smoothstep(.33,.81,light)*(.39+.61*east);
    float haze = exp(-sceneSquare((p.x-.52)*3.6));
    float shoulder=exp(-sceneSquare((p.x-.23)/.18)-sceneSquare((p.y-.196)/.115));
    col+=vec3(.006,.135,.202)*shoulder;
    float farShelf=exp(-sceneSquare((p.x-.36)/.16)-sceneSquare((p.y-.30)/.11));
    col+=vec3(.055,.111,.141)*farShelf;
    return mix(col,vec3(.076,.264,.353),haze*.63);
}

float rfBedHeight(vec2 p) {
    return rfRelief(p) + .21*rfRidge(1.63*p + vec2(2.4, 0.0));
}

vec3 rfStone(vec2 p, float t, float exposure) {
    vec2 q = rfRotate(rfMeasure(p), .17)*vec2(36.0, 65.0);
    vec2 warp = vec2(rfNoise(.48*q), rfNoise(.57*q + 17.0));
    q += 1.58*warp;
    float base = rfBedHeight(q);
    float rise = base - rfBedHeight(q - vec2(.20, .34));
    float detail = rfRelief(q*5.9);
    float darker = rfNoise(q*.33 + 20.0);
    float sharp = rfRidge(q*vec2(2.3, 4.5));
    float facet = smoothstep(-.13, .12, -rise+.02);
    float faceted = clamp(.40*base + .30*facet + .33*detail, 0.0, 1.0);
    vec3 shadow = mix(vec3(.014,.039,.059), vec3(.037,.048,.054), darker);
    vec3 cool = mix(vec3(.089,.157,.192), vec3(.177,.239,.248), warp.x);
    vec3 warm = mix(vec3(.137,.149,.132), vec3(.228,.232,.183), warp.x);
    vec3 surface = mix(cool, warm, smoothstep(.50,.75,darker));
    vec3 rgb = mix(shadow, surface, pow(faceted, 1.85)*1.2);
    rgb += vec3(.19,.29,.31)*pow(max(-rise+.035, 0.0), .91)*(.5 + exposure);
    rgb += vec3(.031,.063,.067)*pow(sharp, 12.0)*(.3 + .7*facet);
    rgb += vec3(.023,.061,.075)*rfCaustic(p, t)*exposure;
    return rgb;
}

vec4 reefBackdrop(vec2 p, float t) {
    float edge = rfCliffTop(p.x);
    float distant = exp(-sceneSquare((p.x-.53)*4.2));
    float crag = rfMask(edge-p.y,mix(.0016,.009,distant));
    vec3 col = rfCliffTone(p, edge);
    float bench = .283 + .18*distant + .056*rfRelief(p*vec2(11.0,3.0));
    float bed = smoothstep(bench,bench+.21,p.y);
    vec3 rubble = rfStone(p*vec2(.69,.89), t, .88);
    rubble = mix(rubble,vec3(.074,.242,.310),.34+.34*distant);
    col = mix(col, rubble, bed);
    float ravineX = .177 + .026*sin(8.4*p.y);
    float bank = .018 + .037*smoothstep(.39,.87,p.y);
    float ravine = exp(-sceneSquare((p.x-ravineX)/bank))*smoothstep(.42,.66,p.y);
    float canyonX = .5 - .044*smoothstep(.59,1.0,p.y);
    float canyon = exp(-sceneSquare((p.x-canyonX)/(.044+.026*p.y)))*
                   smoothstep(.63,.89,p.y);
    float channel = max(ravine,canyon);
    float current = rfRelief(vec2(p.x*89.0 + 8.0*p.y,p.y*12.0));
    vec3 ditch = mix(vec3(.015,.073,.106),vec3(.038,.191,.232),current);
    col = mix(col,ditch,.88*channel);
    float suspended = distant*exp(-sceneSquare((p.y-.39)*5.1));
    col = mix(col,vec3(.078,.272,.349),.32*suspended);
    return vec4(col,crag*mix(.97,.54,distant));
}

float rfForegroundEdge(float x) {
    float left = .770 + .463*x + .107*smoothstep(.235,.57,x);
    left += .027*sin(x*28.0) - .031*exp(-sceneSquare((x-.087)*19.0));
    float right = 1.032 - .37*(x-.66) - .10*smoothstep(.859,1.017,x);
    right += .027*sin(29.0*x + .4);
    return min(left, right) + .019*(rfRelief(vec2(x*63.,11.0))-.5) +
           .009*(rfNoise(vec2(x*151.,5.0))-.5);
}

void rfBoulder(inout vec4 col, vec2 p, vec2 center, vec2 scale,
               float tilt, float seed, float t, float light) {
    vec2 q = rfRotate(rfMeasure(p-center), tilt)/scale;
    if (max(abs(q.x),abs(q.y)) > 1.22) return;
    float warp = rfRelief(q*5.0 + seed);
    float r = length(q - vec2(.10,.05)*sin(q*3.0 + seed));
    float ds = r - 1.0 + .43*(warp-.50);
    float a = rfMask(ds, .095);
    vec3 stone = rfStone(p + seed, t, light);
    float rockZ = sqrt(max(.004,1.0-r*r));
    vec3 normal = normalize(vec3(q,rockZ));
    float facet = floor((atan(q.y,q.x)+3.14159)*1.11 + .28*warp)/7.0;
    float shade = clamp(dot(normal, vec3(-.39,-.65,.63)) + .22*(facet-.5),0.0,1.0);
    float chip = rfRidge(q*vec2(8.1,11.8) + seed*9.0);
    float seam = pow(chip,17.0)*smoothstep(.22,.65,shade);
    stone *= .34 + .94*shade;
    stone += vec3(.073,.091,.086)*pow(shade,2.2) + vec3(.037,.045,.041)*seam;
    rfOver(col, stone, a);
}

void rfRubble(inout vec4 col, vec2 p, float t) {
    float edge = rfForegroundEdge(p.x);
    if (p.y < edge-.055) return;
    vec3 stone = rfStone(p, t, 1.03);
    float shadow = rfRelief(vec2(p.x*82.0,p.y*78.0));
    float crest = exp(-max(p.y-edge,0.0)*44.0);
    stone += vec3(.105,.165,.178)*crest*(.26+.74*sceneSquare(shadow));
    float rich = smoothstep(.48,.75,rfRelief(p*vec2(22.0,40.0)));
    stone = mix(stone, stone*vec3(1.03,.89,.65), .68*rich);
    rfOver(col, stone, rfMask(edge-p.y, .002));
    vec2 grid = floor(p*vec2(55.0,21.0));
    for (int j=-1; j<=1; ++j) {
        for (int i=-1; i<=1; ++i) {
            vec2 cell = grid + vec2(float(i),float(j));
            float seed = rfHash(cell + 2.8);
            vec2 fp = (cell + vec2(seed,rfHash(cell + 29.1)))/vec2(55.0,21.0);
            float bottom = rfForegroundEdge(fp.x);
            if (fp.y > bottom-.006) {
                vec2 size = vec2(.026,.016)*(.38 + 1.23*rfHash(cell - 11.0));
                rfBoulder(col,p,fp,size,3.0*seed,seed,t,1.15);
            }
        }
    }
}

float rfSegment(vec2 p, vec2 a, vec2 b, out float u) {
    vec2 d = b-a;
    u = clamp(dot(p-a,d)/max(dot(d,d), .00001),0.0,1.0);
    return length(p-a-d*u);
}

void rfTube(inout vec4 col, vec2 p, vec2 a, vec2 b, float wa, float wb,
            vec3 tone, float seed) {
    float u;
    float d = rfSegment(p,a,b,u);
    float width = mix(wa,wb,u);
    float mask = rfMask(d-width, .03);
    if (mask <= 0.0) return;
    vec2 tangent = normalize(b-a);
    vec2 across = vec2(tangent.y,-tangent.x);
    float v = dot(p-a, across)/width;
    float lit = .51 + .35*sqrt(max(0.0,1.0-v*v)) + .17*v;
    float fleck = rfRelief(vec2(u*22.0 + seed, v*7.1));
    vec3 rgb = tone*(lit*.68 + fleck*.45);
    rgb += vec3(.09,.112,.113)*pow(max(lit-.56,0.0),.8);
    rfOver(col, rgb, mask);
}

void rfCoral(inout vec4 col, vec2 p, vec2 root, vec2 size, vec3 tone,
             float seed, float branched) {
    vec2 q = rfMeasure(p-root)/size;
    if (q.y > .27 || q.y < -1.32 || abs(q.x) > 1.30) return;
    for (int i=0; i<11; ++i) {
        float f = float(i);
        float rv = rfHash(vec2(f,seed));
        float branch = rfHash(vec2(f,seed+17.1));
        float hx = mix(-1.0,1.0,(f+.9*(branch-.5))/10.0);
        vec2 a = vec2(hx*(.13 + .19*rv), .12*rv);
        vec2 b = vec2(hx*(.63+.32*rv), -(.25+.46*rv+.40*(1.0-abs(hx))));
        vec2 ar = mix(a,b,.48) + vec2(.12*sin(f*7.9+seed),.17*rv);
        vec2 elbow = mix(ar,b,.55) + vec2(.04*sin(f*1.2+seed),-.042*branch);
        float width = mix(.059,.12,branch);
        vec3 c = tone*(.48+.74*branch);
        rfTube(col,q,a,ar,width,width*.82,c*.72,f+seed);
        rfTube(col,q,ar,elbow,width*.81,width*.64,c*.92,f+seed);
        rfTube(col,q,elbow,b,width*.63,width*.33,c,f+seed);
        if (branched > .5 || (i % 3) == 0) {
            float side = sign(branch-.42);
            vec2 forkRoot = mix(ar,b,.26);
            vec2 knuckle = mix(ar,b,.64) + vec2(side*.10,-.042);
            vec2 fork = mix(ar,b,.82) + vec2(side*(.12+.15*rv),-.10-.14*branch);
            rfTube(col,q,forkRoot,knuckle,width*.64,width*.48,c*.84,f+seed+30.);
            rfTube(col,q,knuckle,fork,width*.48,width*.25,c,f+seed+31.);
        }
    }
}

void rfCup(inout vec4 col, vec2 p, vec2 center, vec2 size,
           float a, float seed, vec3 inner, vec3 rim) {
    vec2 q = rfRotate(rfMeasure(p-center), a)/size;
    if (abs(q.x) > 1.37 || abs(q.y) > 2.15) return;
    float theta = atan(q.y,q.x);
    float lift = .056*cos(3.0*theta+seed) + .038*sin(5.0*theta+seed*.81);
    float fluting = lift + .040*cos(7.0*theta+seed) + .028*cos(11.0*theta+1.7*seed) +
                           .019*cos(17.0*theta+seed) + .010*cos(31.0*theta);
    float r = length(q);
    float grain = rfRelief(q*vec2(26.0,31.0) + seed);
    float stains = rfNoise(q*4.2+seed)+.29*rfNoise(q*12.3-seed);
    float ribPhase = 14.5*theta + 1.18*sin(4.0*theta+seed) + .87*r + 2.5*grain;
    float rib = .5+.5*cos(ribPhase);
    float lip = r-1.0-fluting;
    float basin = smoothstep(.15,.99,length(q-vec2(.04,.31)));
    float light = clamp(.62-.22*q.y-.28*q.x-.07*cos(theta*2.),.17,1.0);
    float wash = .72+.26*smoothstep(.17,.80,stains);
    float occlusion=exp(-dot(q-vec2(.01,.30),q-vec2(.01,.30))*5.6);
    float shallow=smoothstep(.14,.83,r)*(.74+.26*basin);
    vec3 wet = inner*(.26+basin*(.27+.28*light)+.11*grain+.17*rib*shallow-.15*occlusion)*wash;
    float reflected = exp(-abs(lip+.09)*12.)*pow(rib,1.5);
    wet += vec3(.052,.104,.148)*reflected*(.46+.54*basin);
    float roll=.64+.36*smoothstep(-.31,.58,q.y+.15*sin(theta*5.+seed));
    wet += rim*exp(-abs(lip+.020)*20.)*(.38+.55*light+.28*grain)*roll;
    wet += rim*.41*exp(-abs(lip+.078)*13.)*smoothstep(.38,.80,rib);

    // The far edge is thin. The outer wall thickens below the rolled near lip.
    vec2 underside=vec2(q.x/(1.02-.32*max(q.y-.62,0.0)),(q.y-.55)*.90);
    float skirt = rfMask(length(underside)-.99-.56*fluting,.032)*smoothstep(.17,.69,q.y);
    float flare = 1.-smoothstep(.61,1.7,q.y);
    float edgeShade = rfRelief(vec2(q.x*15.,q.y*8.)+seed*1.7);
    vec3 shell = inner*vec3(.47,.42,.38)*(.47+.44*rib+.31*edgeShade)*(.56+.32*flare);
    shell += rim*.17*pow(rib,2.3)*flare;
    rfOver(col,shell,skirt);
    rfOver(col,wet,rfMask(lip,.019));
}

void rfValve(inout vec4 col, vec2 p, vec2 hinge, vec2 size, float tilt, float seed,
             vec3 mineral, vec3 pearl) {
    vec2 q = rfRotate(rfMeasure(p-hinge),tilt)/size;
    if (abs(q.x)>1.15 || q.y>.08 || q.y< -1.17) return;
    float theta = atan(q.x,-q.y);
    float r = length(q);
    float envelope = pow(max(0.0,cos(theta*.97)),.50);
    float folds = 12.1*theta + .85*sin(4.1*theta+seed) + .21*sin(8.5*r);
    float profile=1.+.022*cos(folds)+.029*cos(4.4*theta+seed)+.015*cos(folds*1.79+seed);
    float rimDist = r-envelope*profile;
    float a = rfMask(rimDist,.017)*rfMask(q.y,.023);
    if (a <= .0) return;
    float ridge = .5+.5*cos(folds-.35);
    float reflected = smoothstep(.38,.93,r);
    float grain = rfRelief(q*vec2(39.0,31.0)+seed);
    float tint = rfNoise(q*vec2(6.0,12.0)-seed);
    float bands = .5+.5*cos(54.0*r+1.12*cos(folds)+.5*sin(q.x*23.0));
    float sidelight = smoothstep(.05,.81,q.x+.34*r);
    float light = clamp(.51+.19*ridge-.22*q.y+.20*sidelight,.22,1.0);
    float nacre = (.45+.52*smoothstep(.14,.76,r))*light*(.80+.20*grain+.066*bands);
    vec3 rgb = mix(mineral,pearl,.32+.32*reflected+.20*ridge)*nacre;
    rgb += vec3(.16,.101,.055)*smoothstep(.48,.79,tint)*(.19+.40*reflected)*light;
    rgb += vec3(.20,.23,.22)*exp(-abs(rimDist+.052)*19.)*sidelight*(.5+.5*ridge);
    rgb += vec3(.095,.11,.108)*smoothstep(.27,.88,reflected)*pow(ridge,1.8)*sidelight;
    rgb += vec3(.45,.39,.30)*exp(-abs(rimDist)*49.0)*(.56+.41*light);
    rfOver(col,rgb,a);
}

void rfHinge(inout vec4 col, vec2 p, vec2 center, vec2 size, float tilt) {
    vec2 q = rfRotate(rfMeasure(p-center),tilt)/size;
    if (any(greaterThan(abs(q),vec2(1.32,1.25))))return;
    float azimuth=atan(q.x,-q.y+.65);
    float edge=length(vec2(q.x+.18*q.y,q.y))-(1.+.054*sin(azimuth*9.)+.043*q.y);
    float growth=length(q-vec2(.0,.92));
    float ridges=.5+.5*cos(35.*growth+.46*sin(q.x*5.0)+.23*cos(azimuth*8.));
    float rays=.5+.5*sin(11.*azimuth+1.12*growth);
    float light=clamp(.56-.40*q.y-.22*q.x-.16*growth,.12,1.0);
    float grain=rfRelief(q*vec2(22.,31.));
    vec3 shell=mix(vec3(.057,.076,.092),vec3(.31,.282,.226),light*(.50+.50*ridges));
    shell += vec3(.095,.11,.12)*(grain*.31+rays*.17)*(1.-smoothstep(.20,.89,q.y));
    shell += vec3(.31,.28,.197)*exp(-abs(edge+.03)*24.)*light;
    rfOver(col,shell,rfMask(edge,.038));
}

void rfClam(inout vec4 col, vec2 p) {
    vec2 q=rfMeasure(p-vec2(.101,.900));
    if (abs(q.x)>.167||abs(q.y)>.141)return;
    vec2 seat=(q-vec2(.010,.024))/vec2(.132,.042);
    float occlusion=exp(-2.1*dot(seat,seat));
    rfOver(col,vec3(.015,.034,.044),occlusion*.86);
    rfValve(col,p,vec2(.104,.891),vec2(.111,.105),-.32,2.1,
            vec3(.164,.226,.274),vec3(.37,.463,.501));
    rfCup(col,p,vec2(.126,.909),vec2(.055,.025),.54,2.5,
          vec3(.229,.285,.31),vec3(.55,.471,.352));
    rfCup(col,p,vec2(.084,.881),vec2(.074,.030),-.10,1.4,
          vec3(.234,.339,.428),vec3(.48,.519,.494));
    rfHinge(col,p,vec2(.095,.879),vec2(.013,.016),-.36);
    rfHinge(col,p,vec2(.081,.880),vec2(.025,.022),.17);
}

void rfUrchin(inout vec4 col, vec2 p, vec2 base, float radius,
              float turn, vec3 tone) {
    vec2 q = rfMeasure(p-base)/vec2(radius,radius*.87);
    if (dot(q,q)>1.73)return;
    float mass=rfMask(length(q*vec2(1.,1.14))-.22,.10);
    float dark=rfRelief(q*35.+turn);
    rfOver(col,vec3(.014,.023,.041)+tone*(.08+.13*dark),mass);
    // The low, far set of spines gives way to shorter spines on the lit dome.
    for (int ring=0; ring<4; ++ring) {
        float layer=float(ring);
        vec2 key=q+vec2(.042*sin(layer*2.+turn),-.050*layer);
        float r=length(key);
        float angle=atan(key.y,key.x)+turn;
        float count=6.52+layer*1.29;
        float warp=angle+.016*sin(6.0*angle+layer)+.029*sin(3.8*r+layer+angle*5.);
        float k=(warp+.089*layer)*count;
        float s=floor(k+.5);
        float variance=rfHash(vec2(s,turn+layer));
        float low=.11+layer*.057;
        float high=(1.10-.12*layer)*(.67+.40*variance)+.037*sin(s*9.4+layer);
        float u=clamp((r-low)/(high-low),0.,1.);
        float crossSpine=k-s-.31*(variance-.50)*sin(3.14159*u);
        float thick=mix(.25,.029,pow(u,.74))*(.66+.46*variance);
        float mask=rfMask(abs(crossSpine)-thick,.066)*smoothstep(low,low+.18,r)*rfMask(r-high,.046);
        float ridge=rfMask(abs(crossSpine+thick*.40)-thick*.26,.069);
        float light=clamp(.60-.27*key.y-.17*key.x,.31,1.14);
        float taper=smoothstep(.18,.81,u);
        float bands=.77+.23*cos(9.8*u+5.2*variance+layer);
        vec3 c=tone*(.26+.37*variance+.51*taper)*light;
        c+=vec3(.39,.35,.39)*ridge*light*(.22+.67*taper)*(.51+.49*variance)*bands;
        rfOver(col,c,mask*.94);
    }
}

void rfFoliose(inout vec4 col,vec2 p){
    vec2 screen=p*vec2(880.,376.);
    vec2 seat=screen-vec2(228.5,342.3);
    if(abs(seat.x)>30.||abs(seat.y)>31.)return;
    rfOver(col,vec3(.024,.055,.062),.69*exp(-dot(seat/vec2(21.,7.),seat/vec2(21.,7.))));
    const vec4 blades[9]=vec4[9](vec4(224,341,209,318),vec4(226,338,218,315),
        vec4(229,337,228,315),vec4(233,335,237,315),vec4(236,337,246,318),
        vec4(239,339,256,321),vec4(222,341,213,323),vec4(226,343,221,324),
        vec4(236,342,252,323));
    for(int i=0;i<9;i++){
        vec4 blade=blades[i];
        vec2 axis=blade.zw-blade.xy;
        float h=length(axis);
        vec2 tangent=axis/h,across=vec2(-tangent.y,tangent.x);
        vec2 off=screen-blade.xy;
        float u=dot(off,tangent)/h;
        if(u<-.04||u>1.05)continue;
        float k=float(i);
        float side=dot(off,across)-sin(u*3.14159)*2.9*sin(k*1.7)-u*u*sin(k*4.0);
        float lobed=sqrt(max(0.,1.-pow(abs((u-.57)/.48),2.4)));
        float ruffle=.83+.29*rfNoise(vec2(u*20.9+k,side*.59))+.21*u;
        float rim=abs(side)-(2.45+1.3*rfHash(vec2(k,3.1)))*lobed*ruffle;
        float tip=max(-u,u-1.)*h+(rfNoise(screen*.91+k)-.45)*.64;
        float edge=max(rim,tip);
        if(edge>.5)continue;
        float skin=rfRelief(screen*1.27+k);
        float fold=dot(off,across)*.83+.42*sin(18.*u+k);
        float cosine=clamp(.73-.12*side+.17*u+.11*sin(fold),.38,1.22);
        vec3 sea=mix(vec3(.048,.102,.122),vec3(.275,.353,.358),cosine*(.28+.64*u));
        sea*=.72+.46*skin;
        sea+=vec3(.30,.35,.321)*exp(-abs(edge+.30)*1.62)*smoothstep(.18,.99,u)*(.39+.61*skin);
        rfOver(col,sea,rfMask(edge,.38));
    }
    rfCup(col,p,vec2(.259,.901),vec2(.043,.011),-.13,11.1,vec3(.116,.171,.185),vec3(.31,.36,.332));
}

void rfFingers(inout vec4 col, vec2 p, vec2 root, vec2 size, float seed, vec3 tone) {
    vec2 q = rfMeasure(p-root)/size;
    if (abs(q.x)>1.27 || q.y> .28 || q.y< -1.25) return;
    for (int i=0; i<9; ++i) {
        float index = float(i);
        float h = rfHash(vec2(index,seed));
        float s = (index-4.0)*.24;
        float layer = rfHash(vec2(index,seed+15.0));
        vec2 a = vec2(.28*s,.13*layer);
        vec2 b = vec2(s*(.66+.33*h),-(.29+.51*h+.25*(1.0-abs(s))));
        float bend = .27*(layer-.5)*sin(3.14159*clamp(q.y/b.y,0.0,1.0));
        vec2 bent = q-vec2(bend,0);
        float along;
        float d = rfSegment(bent,a,b,along);
        float width = mix(.128,.083,along)*(.64+.55*layer);
        if (d>width+.054) continue;
        float nodules = rfRelief(vec2(along*12.0,d*40.0)+index+seed);
        float ds = d-width*(.77+.43*nodules+.105*cos(along*31.0+h*36.0));
        float across = dot(bent-mix(a,b,along),normalize(vec2(b.y-a.y,a.x-b.x)))/width;
        float relief = sqrt(max(0.0,1.0-d*d/(width*width)));
        float growth = rfRelief(vec2(along*27.0,across*4.1)+index+seed);
        float pores = rfNoise(q*vec2(108.0,83.0)+index);
        float light = clamp(.30+.38*relief+.20*across+.19*along+.33*(growth-.5),.12,1.0);
        vec3 rgb = tone*light*(.64+.35*layer+.19*nodules);
        rgb += vec3(.174,.195,.213)*pow(light,2.0)*(.25+.75*nodules);
        rgb *= .79+.25*smoothstep(.17,.56,pores);
        rfOver(col,rgb,rfMask(ds,.019));
    }
}

void rfStar(inout vec4 col, vec2 p) {
    vec2 q = rfRotate(rfMeasure(p-vec2(.835,.952)),.17)/vec2(.101,.062);
    if (length(q)>1.3) return;
    float dist = length(q)-.182;
    float swell = clamp(1.0-length(q)*4.0,0.0,1.0);
    for (int i=0; i<5; ++i) {
        float az = 1.256637*float(i)-1.48;
        vec2 dir = vec2(cos(az),sin(az));
        float vr = .90 + .15*sin(float(i)*2.3 + .2);
        float u;
        float range = rfSegment(q,vec2(0),dir*vr,u);
        float thick = mix(.17,.018,pow(u,.59));
        float d = range-thick;
        if (d < dist) {
            dist = d;
            swell = 1.0-clamp(range/thick,0.0,1.0);
        }
    }
    float pore = rfRelief(q*57.0);
    float blotch = rfNoise(q*11.0);
    vec3 skin = mix(vec3(.205,.093,.089),vec3(.48,.267,.231),swell*.54+.39*pore);
    skin += vec3(.086,.076,.061)*smoothstep(.67,.77,pore)-.10*blotch;
    rfOver(col,skin,rfMask(dist,.020));
}

void rfCrab(inout vec4 col, vec2 p) {
    vec2 q = rfRotate(rfMeasure(p-vec2(.315,.959)),.056)/vec2(.064,.040);
    if (abs(q.x)>1.46 || abs(q.y)>1.45) return;
    rfOver(col,vec3(.028,.044,.046),.69*exp(-dot(q-vec2(.04,.20),q-vec2(.04,.20))*2.32));
    vec3 claw = vec3(.36,.19,.132);
    for (int i=0; i<4; ++i) {
        float arm = float(i);
        for (int j=0; j<2; ++j) {
            float s = float(j)*2.0-1.0;
            vec2 a = vec2(s*.31,.14);
            vec2 b = vec2(s*(.62+.068*arm),-.42+.24*arm+.051*s);
            vec2 c = vec2(s*(.80+.12*arm),-.36+.26*arm+.033*s);
            vec2 d = c+vec2(s*.12,.09+.08*arm);
            rfTube(col,q,a,b,.061,.048,claw*.72,arm);
            rfTube(col,q,b,c,.052,.035,claw,arm);
            rfTube(col,q,c,d,.038,.016,claw*.86,arm);
        }
    }
    vec2 body = (q+vec2(0,.15))/vec2(.62,.37);
    body.x+=body.y*.09;
    float r = length(body);
    float n = rfRelief(q*vec2(39.0,51.0));
    float az=atan(body.y,body.x);
    float shape=r-1.0+.13*(n-.50)+.065*cos(az*3.)+.042*cos(az*7.);
    float light=clamp(.56-.35*body.y+.45*n-.48*r,0.,1.);
    vec3 shell=mix(vec3(.118,.072,.050),vec3(.51,.287,.202),light);
    float flecks=smoothstep(.54,.80,rfNoise(q*24.3))*smoothstep(.40,.71,n);
    shell+=vec3(.365,.31,.25)*flecks*(.41+.59*light);
    shell+=vec3(.29,.21,.13)*exp(-abs(shape+.028)*28.)*(.31+.69*n)*light;
    rfOver(col,shell,rfMask(shape,.035));
    for (int i=0; i<2; ++i) {
        float s = float(i)*2.0-1.0;
        vec2 a = vec2(s*.39,.12);
        vec2 b = vec2(s*(.69+.046*s),.42+.052*s);
        vec2 c = vec2(s*(.57+.068*s),1.07-.071*s);
        vec2 d = vec2(s*(.41+.055*s),.87-.10*s);
        rfTube(col,q,a,b,.098,.135,claw*.87,float(i));
        rfTube(col,q,b,mix(b,c,.58),.155,.119,claw*1.1,float(i));
        rfTube(col,q,mix(b,c,.55),c,.10,.026,claw*.99,float(i));
        rfTube(col,q,mix(b,c,.33),d,.078,.018,claw*.83,float(i));
    }
}

void rfEncrusting(inout vec4 col, vec2 p, vec2 base, vec2 size, float seed, vec3 tone) {
    vec2 q = rfMeasure(p-base)/size;
    if (abs(q.x) > 1.38 || abs(q.y) > 1.24) return;
    float relief = rfRelief(q*7.1 + seed);
    float outline = length(q) - .95 + .39*(relief-.5);
    float lobes = rfNoise(q*6.1 - vec2(seed,3.9));
    float follicles = rfRelief(q*24.0 + seed);
    float ridges = smoothstep(.58,.77,lobes) * smoothstep(.39,.67,follicles);
    float crevices = .37 + .48*smoothstep(.26,.60,relief);
    float light = clamp(.59-.31*q.y-.16*q.x,.23,.95);
    float edge = smoothstep(-.24,-.035,outline);
    vec3 rgb = tone*crevices*(.24+.73*light)*(1.0-.33*edge);
    rgb += vec3(.135,.165,.147)*ridges*light;
    rfOver(col,rgb,rfMask(outline,.052));
}

float rfStalkX(float u, float phase, float sway) {
#if defined(DETAIL_LOOP_FRAMES)
    return sway*(.68*sin(phase-2.9*u)*u + .35*sin(7.4*u+2.0*phase)*u*u);
#else
    return sway*(.68*sin(phase-2.9*u)*u + .35*sin(7.4*u+phase*.63)*u*u);
#endif
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

void rfSeaweed(inout vec4 col, vec2 p, vec2 base, float h, float size,
               float seed, float warm, float t) {
    vec2 bounds = vec2(.037*size+.015,h*1.17);
    if (abs(p.x-base.x)>bounds.x || p.y>base.y+.005 || p.y<base.y-bounds.y) return;
#if defined(DETAIL_LOOP_FRAMES)
    float phase = seed + detailPhase(t);
#else
    float phase = seed + t*.64;
#endif
    if (base.y > .70) {
        for (int i=0; i<7; ++i) {
            float j = float(i);
            float fan = (j-3.0)/3.0;
            float variation = rfHash(vec2(j,seed));
            vec2 root = base+vec2(fan*.0038,0.0);
            vec2 tip = root+vec2(size*(fan*.025+.011*sin(phase+fan)),
                                 -h*(.42+.51*variation-.10*abs(fan)));
            rfKelpBlade(col,p,root,tip,size*(.0015+.0013*variation),
                        -fan*.007,seed+j,phase+fan,warm);
        }
        return;
    }
    float u = clamp((base.y-p.y)/h,0.0,1.08);
    float sway = size*.012;
    float cx = base.x + rfStalkX(u,phase,sway);
    float stemWidth = .00105*size*(1.0-.68*u);
    float stem = rfMask(abs(p.x-cx)-stemWidth, .00048)*rfMask(u-1.03,.021);
    rfOver(col,mix(vec3(.087,.134,.063),vec3(.32,.25,.068),warm),.90*stem);
    float nearest = floor(u*15.0);
    for (int i=-4; i<=1; ++i) {
        float j = nearest + float(i);
        if (j < 0.0 || j > 14.0) continue;
        float lengthVariation = rfHash(vec2(j,seed));
        float widthVariation = rfHash(vec2(seed-.91,j+2.7));
        float jn = (j+.62*widthVariation)/15.0;
        float side = (2.0*mod(j,2.0)-1.0)*mix(1.0,-1.0,step(.87,widthVariation));
        vec2 root = base+vec2(rfStalkX(jn,phase,sway),-jn*h);
        float span = size*(.007+.011*lengthVariation)*(1.0-.62*jn);
        float rise = (.065+.132*widthVariation)*(1.0-.46*jn);
        float flutter = sin(phase-5.5*jn+lengthVariation*1.2);
        vec2 tip = root+vec2(side*span*(.88+.27*flutter)+
                             rfStalkX(jn+rise,phase,sway)-rfStalkX(jn,phase,sway),
                             -h*rise);
        float width = size*(.0026+.0034*widthVariation)*(1.0-.62*jn);
        float curve = side*span*(.52-.32*widthVariation);
        rfKelpBlade(col,p,root,tip,width,curve,seed+lengthVariation*6.3,
                    phase-5.5*jn,mix(warm*.82,warm,lengthVariation));
    }
}

void rfCoralBed(inout vec4 col, vec2 p, float t) {
    vec3 steel = vec3(.25,.34,.37);
    vec3 mauve = vec3(.36,.235,.266);
    vec3 sand = vec3(.35,.306,.239);
    vec3 lilac = vec3(.262,.261,.372);
    rfEncrusting(col,p,vec2(.014,.765),vec2(.027,.010),9.15,sand*.80);
    rfEncrusting(col,p,vec2(.112,.788),vec2(.027,.012),4.81,lilac*.91);
    rfEncrusting(col,p,vec2(.149,.830),vec2(.042,.017),7.31,steel*.82);
    rfEncrusting(col,p,vec2(.159,.890),vec2(.055,.024),3.14,mauve*1.24);
    rfEncrusting(col,p,vec2(.033,.942),vec2(.047,.026),9.10,lilac*.92);
    rfEncrusting(col,p,vec2(.234,.919),vec2(.058,.021),12.3,sand*.87);
    rfEncrusting(col,p,vec2(.356,.978),vec2(.071,.022),1.71,steel*.89);
    rfEncrusting(col,p,vec2(.433,.998),vec2(.056,.027),6.72,sand*1.01);
    rfEncrusting(col,p,vec2(.810,.987),vec2(.048,.019),4.23,lilac*1.22);
    rfEncrusting(col,p,vec2(.904,.963),vec2(.056,.018),8.22,steel*.95);
    rfEncrusting(col,p,vec2(.978,.886),vec2(.070,.018),8.26,sand*.83);
    rfFingers(col,p,vec2(.023,.819),vec2(.075,.092),5.3,sand*.83);
    rfCup(col,p,vec2(.044,.791),vec2(.083,.029),.21,3.1,
        vec3(.279,.227,.175),vec3(.51,.442,.359));
    rfCoral(col,p,vec2(.105,.821),vec2(.054,.060),lilac*.58,13.9,1.);
    rfUrchin(col,p,vec2(.102,.813),.041,1.3,lilac*.61);
    rfFingers(col,p,vec2(.160,.867),vec2(.053,.078),4.3,mauve*.95);
    rfFingers(col,p,vec2(.209,.861),vec2(.052,.072),7.3,sand*.60);
    rfUrchin(col,p,vec2(.182,.861),.026,1.83,mauve*.82);
    rfBoulder(col,p,vec2(.263,.927),vec2(.063,.020),.20,9.6,t,.84);
    rfBoulder(col,p,vec2(.290,.940),vec2(.072,.021),-.27,15.1,t,.91);
    rfBoulder(col,p,vec2(.309,.956),vec2(.057,.022),.17,6.6,t,.74);
    rfFoliose(col,p);
    rfUrchin(col,p,vec2(.171,.927),.0525,2.3,mauve*.96);
    rfUrchin(col,p,vec2(.205,.933),.045,.14,mix(lilac,mauve,.42)*.94);
    rfUrchin(col,p,vec2(.058,.978),.064,.77,lilac*.60);
    rfEncrusting(col,p,vec2(.065,.941),vec2(.036,.026),2.31,steel*.86);
    rfEncrusting(col,p,vec2(.112,.966),vec2(.053,.022),13.31,sand*.95);
    rfClam(col,p);
    rfFingers(col,p,vec2(.133,1.008),vec2(.062,.069),2.7,sand*.65);
    rfFingers(col,p,vec2(.252,1.002),vec2(.065,.062),13.7,steel*1.10);
    rfFingers(col,p,vec2(.244,1.015),vec2(.058,.077),3.2,steel*.93);
    rfCoral(col,p,vec2(.374,.934),vec2(.047,.064),vec3(.49,.277,.147),7.7,1.);
    rfFingers(col,p,vec2(.476,1.022),vec2(.063,.067),9.7,steel*.86);
    rfEncrusting(col,p,vec2(.354,.939),vec2(.028,.016),6.23,sand*.81);
    rfCrab(col,p);
    rfUrchin(col,p,vec2(.703,1.018),.059,.44,steel*.70);
    rfCoral(col,p,vec2(.745,.996),vec2(.069,.089),mauve*.84,12.3,1.);
    rfFingers(col,p,vec2(.775,.934),vec2(.074,.076),7.12,sand*.96);
    rfFingers(col,p,vec2(.785,1.009),vec2(.065,.076),10.3,steel);
    rfEncrusting(col,p,vec2(.808,.945),vec2(.047,.019),7.3,mauve*.86);
    rfCoral(col,p,vec2(.956,.958),vec2(.062,.087),mauve*.78,9.75,0.);
    rfCup(col,p,vec2(.955,.916),vec2(.057,.026),-.18,4.3,
        vec3(.29,.236,.188),vec3(.29,.235,.16));
    rfUrchin(col,p,vec2(.973,1.003),.063,2.0,mauve*.64);
    rfFingers(col,p,vec2(.979,.889),vec2(.071,.059),12.3,steel*.69);
    rfFingers(col,p,vec2(.931,1.027),vec2(.082,.098),18.9,lilac*.91);
    rfStar(col,p);
}

void rfChain(inout vec4 col, vec2 p, vec2 center, float slope, float span) {
    vec2 q = rfMeasure(p-center);
    if (abs(q.x)>span || abs(q.y)>span) return;
    float nearest = floor(q.x/.021);
    for (int i=-1; i<=1; ++i) {
        float j = nearest + float(i);
        float x = j*.021;
        if (abs(x)>span-.013) continue;
        float y = x*slope + .044*cos(x*24.0) - .043;
        float a = slope - .7*sin(x*24.0);
        vec2 dj = rfRotate(q-vec2(x,y),-a);
        float r = length(dj/vec2(.013, mix(.0065,.0037,mod(j,2.0))));
        float d = abs(r-.85)-.24;
        float lit = smoothstep(.12,.89,.5-dj.y*89.0);
        vec3 c = mix(vec3(.027,.031,.033),vec3(.19,.168,.133),lit*.83);
        rfOver(col,c,rfMask(d,.13));
    }
}

vec4 reef(vec2 p, float t) {
    vec4 col = vec4(0.0);
    rfSeaweed(col,p,vec2(.063,.530),.207,.71,.55,.68,t);
    rfSeaweed(col,p,vec2(.107,.510),.228,.85,7.2,.85,t);
    rfSeaweed(col,p,vec2(.105,.671),.210,.88,2.54,.76,t);
    rfSeaweed(col,p,vec2(.243,.560),.274,.85,4.2,.84,t);
    rfSeaweed(col,p,vec2(.182,.454),.13,.54,.87,.32,t);
    rfSeaweed(col,p,vec2(.874,.535),.212,.72,2.1,.77,t);
    rfSeaweed(col,p,vec2(.836,.437),.148,.62,2.9,.63,t);
    rfSeaweed(col,p,vec2(.909,.420),.133,.52,1.6,.41,t);
    rfSeaweed(col,p,vec2(.974,.472),.144,.67,7.53,.78,t);
    rfSeaweed(col,p,vec2(.510,.771),.124,.71,8.2,.41,t);
    rfSeaweed(col,p,vec2(.757,.837),.113,.68,7.43,.29,t);
    rfRubble(col,p,t);
    rfCoralBed(col,p,t);
    rfChain(col,p,vec2(.213,1.020),-.45,.136);
    // The near chain rises from a broken block, crests above the urchin,
    // then disappears into the foreground reef.
    vec2 chainPx=p*vec2(880.,376.);
    if(chainPx.x>566.&&chainPx.x<679.&&chainPx.y>341.&&chainPx.y<374.){
        float cell=floor((chainPx.x-570.)/5.7);
        for(int i=-1;i<=1;i++){
            float j=cell+float(i),x=570.+5.7*j;
            float a=(x-633.)*.034;
            float y=356.-8.8*cos(a)-.026*(x-633.);
            vec2 q=rfRotate(chainPx-vec2(x,y),-atan(.299*sin(a)-.026));
            float tilt=mod(j,2.);
            vec2 axis=vec2(4.25,mix(2.19,1.09,tilt));
            float r=length(q/axis);
            float metal=1.-smoothstep(.19,.44,abs(r-.77));
            vec3 tone=mix(vec3(.053,.064,.064),vec3(.43,.32,.22),
                (.65+.35*rfNoise(chainPx*1.69))*(1.-smoothstep(-1.85,.36,q.y)));
            rfOver(col,tone,metal);
        }
    }
    return rfFinish(col);
}

// Track the two close stalks in 880-by-376 reference pixels.  The leaf
// endpoints flex against the motion of their roots as the stalks enter.
float rfNearTravel(float t, vec4 early, vec4 late) {
    float at = clamp((t-1.5)*2.0,0.0,7.0);
    int i = int(at);
    float samples[8] = float[8](early.x,early.y,early.z,early.w,
                                late.x,late.y,late.z,late.w);
    float a = samples[max(i-1,0)], b = samples[i];
    float c = samples[min(i+1,7)], d = samples[min(i+2,7)];
    float u = fract(at);
    return mix(b,c,u) + .5*u*(1.0-u)*
           mix(c-a-2.0*(c-b),2.0*(c-b)-(d-b),u);
}

vec2 rfNearStalk(vec2 root, vec2 travel, float side, float t) {
    float h = 1.0-clamp(root.y/376.0,0.0,1.0);
    vec2 shift = travel*mix(vec2(side < 0.0 ? .58 : 1.30,.18),vec2(1.03,1.0),h);
    float sway = sin(2.1*t+root.y*.011+side)*sin(2.0*(5.0-t));
    return root + shift + vec2(2.5*h*sway,1.1*h*sway);
}

void rfNearRod(inout vec4 col, vec2 p, vec2 base, vec2 crown,
               vec2 bend, float radius) {
    float u = (p.y-base.y)/(crown.y-base.y);
    if (u < 0.0 || u > 1.0) return;
    float x = mix(base.x,crown.x,u) + 3.0*u*(1.0-u)*mix(bend.x,bend.y,u);
    float width = mix(radius,.33*radius,u);
    float face = 1.0-clamp(abs(p.x-x)/width,0.0,1.0);
    vec3 bark = mix(vec3(.022,.012,.005),vec3(.092,.060,.015),u*u);
    rfOver(col,bark*(.82+.23*face),rfMask(abs(p.x-x)-width,.72));
}

void rfNearShoot(inout vec4 col, vec2 p, vec2 base, vec2 tip, vec2 bow,
                 float width, float shape, float seed, float exposure) {
    vec2 axis = tip-base;
    float len = length(axis);
    vec2 along = axis/len;
    vec2 normal = vec2(-along.y,along.x);
    vec2 q = p-base;
    float u = dot(q,along)/len;
    if (u < -.004 || u > 1.004) return;
    u = clamp(u,0.0,1.0);

    float taper = 3.55*pow(u,.88)*pow(1.0-u,shape);
    float center = 3.0*u*(1.0-u)*mix(bow.x,bow.y,u);
    float twist = sin(3.7*u+seed);
    float flank = dot(q,normal)-center;
    float face = flank/max(width*taper,.6);
    float asymmetry = 1.0 + .15*twist*sign(face);
    float ruffle = 1.0 + .034*sin(u*29.0+seed) +
                  .132*(rfNoise(vec2(u*17.0,seed+step(0.0,face)))-.5);
    float d = max(abs(flank)-width*taper*asymmetry*ruffle,
                  max(-dot(q,along),dot(q,along)-len));
    float a = rfMask(d,.72);
    if (a < .001) return;

    float crease = face + .31*sin(4.8*u+seed*.47);
    float fold = smoothstep(-.59,.42,crease*mix(-1.0,1.0,smoothstep(-.38,.38,twist)));
    float rib = exp(-abs(crease)*9.0);
    float thinRim = smoothstep(.66,1.09,abs(face))*smoothstep(.35,.96,u);
    float skin = rfRelief(vec2(u*19.0 + .45*face,face*3.1 + seed));
    float grain = rfNoise(vec2(u*112.0+seed,face*12.0));
    float light = (.60+.34*fold+.10*rib+.25*thinRim)*(.85+.19*skin+.12*grain);
    float upperWater = pow(1.0-clamp(p.y/376.0,0.0,1.0),2.1);
    float tipLight = mix(.48,1.0,smoothstep(.09,.94,u));
    float value = (.14+.41*upperWater)*tipLight*light*exposure;
    vec3 amber = vec3(1.0,.73,.033) * value;
    amber += vec3(.013,.010,.006)*(.42 + .58*skin);
    rfOver(col,amber,a);
}

void rfNearLeaf(inout vec4 col, vec2 p, float t, float side, vec2 travel,
                vec2 base, vec2 tip, vec2 compliance, vec2 bow,
                float width, float shape, float seed, float exposure) {
    float wave = sin(2.7*t+seed)*sin(1.6*(5.0-t));
    vec2 root = rfNearStalk(base,travel,side,t);
    vec2 end = tip + travel*compliance + vec2(3.4,2.1)*wave;
    float roll=.84+.13*cos(seed*.93+t*.75);
    float projectedWidth=width*roll*mix(.89,.82,smoothstep(3.5,5.,t));
    rfNearShoot(col,p,root,end,bow+vec2(1.8,-3.1)*wave,projectedWidth,shape,seed,exposure);
}

vec4 reefKelp(vec2 p, float t) {
    if (p.x > .181 && p.x < .786) return vec4(0.0);
    vec4 col = vec4(0.0);
    vec2 q = p*vec2(880.0,376.0);
    if (p.x >= .786 && t > 1.40) {
        vec2 travel = vec2(rfNearTravel(t,vec4(143,106,88,57),vec4(30,16,7,0)),
                           rfNearTravel(t,vec4(92,77,61,47),vec4(34,22,10,0)));
        rfNearLeaf(col,q,t,1.0,travel,vec2(885,120),vec2(848,-30),vec2(2.3,.68),vec2(3,13),10.,.80,.7,.76);
        rfNearLeaf(col,q,t,1.0,travel,vec2(875,162),vec2(809,-43),vec2(1.95,.76),vec2(-12,3),21.,.78,3.6,.65);
        rfNearLeaf(col,q,t,1.0,travel,vec2(853,273),vec2(896,158),vec2(1.19,.54),vec2(15,4),17.,.65,6.2,.66);
        rfNearLeaf(col,q,t,1.0,travel,vec2(839,315),vec2(892,197),vec2(1.12,.51),vec2(12,3),20.,.71,5.9,.90);
        rfNearLeaf(col,q,t,1.0,travel,vec2(820,382),vec2(908,271),vec2(1.21,.95),vec2(-10,10),25.,.67,6.8,.85);
        rfNearLeaf(col,q,t,1.0,travel,vec2(804,388),vec2(697,312),vec2(1.24,1.10),vec2(12,5),17.,.77,4.1,.69);
        rfNearLeaf(col,q,t,1.0,travel,vec2(797,361),vec2(711,277),vec2(1.16,1.00),vec2(8,5),11.,.85,4.5,.72);
        rfNearLeaf(col,q,t,1.0,travel,vec2(815,379),vec2(740,220),vec2(.66,1.44),vec2(-14,-11),23.,.88,3.2,.95);
        rfNearLeaf(col,q,t,1.0,travel,vec2(833,326),vec2(734,153),vec2(1.04,.53),vec2(16,11),28.,.99,4.4,.90);
        rfNearLeaf(col,q,t,1.0,travel,vec2(858,216),vec2(818,95),vec2(1.99,1.05),vec2(6,-7),20.,.51,4.8,.84);
        rfNearLeaf(col,q,t,1.0,travel,vec2(858,212),vec2(708,76),vec2(1.0,1.0),vec2(3,79),17.,1.36,3.6,1.09);
        float canopyShift = rfNearTravel(t,vec4(320,254,185,155),vec4(108,68,34,0));
        rfNearLeaf(col,q,t,1.0,travel,vec2(881,146),vec2(756.0+canopyShift,-2),
                   vec2(0.,.13),vec2(30,34),27.,.78,4.3,.78);
        vec2 base = rfNearStalk(vec2(816,385),travel,1.,t);
        vec2 crown = rfNearStalk(vec2(900,-27),travel,1.,t);
        rfNearRod(col,q,base,crown,vec2(14,20),6.1);
    }
    if (p.x <= .181 && t > 2.45) {
        vec2 travel = vec2(rfNearTravel(t,vec4(-192,-157,-137,-125),vec4(-101,-69,-34,0)),
                           rfNearTravel(t,vec4(15,12,2,-15),vec4(-20,-24,-16,0)));
        rfNearLeaf(col,q,t,-1.0,travel,vec2(64,370),vec2(-32,334),vec2(.60,.98),vec2(-8,-12),10.,.93,14.1,.66);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(55,338),vec2(-43,246),vec2(.65,.86),vec2(-12,-11),20.,.77,7.8,.78);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(41,285),vec2(-35,169),vec2(.70,.80),vec2(-8,-10),21.,.68,1.3,.87);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(29,236),vec2(-53,161),vec2(.81,.88),vec2(-6,-11),19.,.98,1.8,1.02);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(13,148),vec2(-31,57),vec2(.92,.39),vec2(-5,1),21.,.75,4.7,1.10);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(11,123),vec2(57,32),vec2(.94,.29),vec2(-18,-4),7.,.95,3.9,1.08);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(6,126),vec2(45,-13),vec2(.97,.13),vec2(-16,-10),22.,.73,4.6,1.30);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(14,150),vec2(89,-1),vec2(1.0,.12),vec2(26,23),17.,.78,3.2,1.66);
        rfNearLeaf(col,q,t,-1.0,travel,vec2(28,222),vec2(62,128),vec2(1.13,1.18),vec2(0,7),24.,.58,3.4,1.16);
        vec2 base = rfNearStalk(vec2(68,390),travel,-1.,t);
        vec2 crown = rfNearStalk(vec2(12,-22),travel,-1.,t);
        rfNearRod(col,q,base,crown,vec2(-9,-35),5.5);

        vec2 lower = travel*vec2(.86,.65);
        rfNearLeaf(col,q,t,-1.0,lower,vec2(71,391),vec2(132,306),vec2(1.37,1.12),vec2(9,5),13.,.91,1.9,.77);
        rfNearLeaf(col,q,t,-1.0,lower,vec2(69,394),vec2(96,218),vec2(1.07,.87),vec2(9,4),14.,.74,1.6,.96);
        rfNearLeaf(col,q,t,-1.0,lower,vec2(75,358),vec2(144,219),vec2(1.23,.93),vec2(-7,-13),9.,.86,4.2,1.30);
        float flexible = mix(.96,.55,smoothstep(3.05,3.63,t));
        float faceWidth = mix(7.0,20.0,smoothstep(3.44,4.25,t));
        rfNearLeaf(col,q,t,-1.0,lower,vec2(73,389),vec2(73,201),
                   vec2(flexible,.60),vec2(-14,-12),faceWidth,.60,3.8,.94);
        rfNearLeaf(col,q,t,-1.0,lower,vec2(59,394),vec2(112,324),
                   vec2(.59,.65),vec2(-7,-4),7.,.74,1.2,.74);
        rfNearLeaf(col,q,t,-1.0,lower,vec2(72,395),vec2(50,314),vec2(.80,.92),vec2(-6,4),11.,.72,9.4,.77);
    }
    return rfFinish(col);
}

// Projected shelves of limestone, rubble, and deep blue channels. These
// connect the plinths that sit at different distances along the canyon.
float shelfRock(vec2 p){
    return .48*valueNoise(p)+.27*valueNoise(2.17*p+8.)+.16*valueNoise(4.44*p)+.09*valueNoise(9.22*p-3.);
}
vec4 foundationLedge(vec2 s,vec2 center,vec2 span,float turn,float altitude,float seed){
    vec2 delta=s-center;
    vec2 q=vec2(delta.x,delta.y-turn*delta.x);
    vec2 across=q/span; 
    if(abs(across.x)>1.13||across.y< -1.32||q.y>altitude+span.y*1.3)return vec4(0.);
    float rough=shelfRock(s*.13+seed);
    float perimeter=sqrt(max(0.,1.-across.x*across.x));
    float chisel=(rough-.5)*min(12.,.56*span.y);
    float edge=span.y*perimeter+chisel;
    float top=edge-q.y;
    float alpha=smoothstep(-.65,.65,min((1.-abs(across.x))*span.x+chisel,min(q.y+edge,top+altitude)));
    if(alpha<.001)return vec4(0.);
    vec2 strata=vec2(q.x/(6.+3.*rough)+(.18*rough),q.y/(4.+rough)+1.4*rough);
    float fissure=abs(fract(strata.x+.5*mod(floor(strata.y),2.))-.5);
    float fracture=smoothstep(.008,.073,min(fissure,abs(fract(strata.y)-.5)));
    float facet=shelfRock(s*vec2(.27,.097)+seed);
    vec3 side=mix(vec3(.034,.095,.129),vec3(.18,.245,.247),rough*facet*1.5)*(.79+.21*fracture);
    float ledge=exp(-abs(top+2.)*.29);
    side+=ledge*vec3(.13,.14,.12)*rough;
    vec3 horizontal=mix(vec3(.11,.17,.17),vec3(.50,.49,.42),pow(rough,1.32))*(.7+.29*fracture+.15*facet);
    horizontal+=smoothstep(.55,.72,facet)*vec3(.12,.11,.08);
    return vec4(mix(side,horizontal,smoothstep(-1.,1.,top)),alpha);
}
vec3 footings(vec2 p,vec3 rgb,float t){
    vec2 s=p*vec2(880.,376.);
    const vec4 bases[9]=vec4[9](vec4(229,224,47,12),vec4(341,208,73,10),vec4(306,157,55,7),
        vec4(98,215,68,12),vec4(45,277,92,16),vec4(638,213,67,11),
        vec4(775,181,65,11),vec4(771,275,85,17),vec4(820,322,106,18));
    const float lean[9]=float[9](-.16,-.13,-.06,-.23,-.21,.04,.17,.24,.23);
    for(int i=0;i<9;i++){
        vec4 b=bases[i];
        vec4 rock=foundationLedge(s,b.xy,b.zw,lean[i],b.w*2.+11.,float(i)*17.);
        rgb=mix(rgb,rock.rgb,rock.a);
    }
    return rgb;
}
// Blue light returning through the narrow water-filled fissures softens the
// silhouettes of the vertical rock faces without brightening the plaza.
vec3 channelLight(vec2 p,float t,vec3 under){
    float depth=clamp((p.y-.44)*2.8,0.,1.);
    float west=.184+.041*sin(p.y*5.4-3.7);
    float center=.547-.018*sin(p.y*8.);
    float valley=exp(-abs(p.x-west)*68.)*smoothstep(.38,.67,p.y)
              +exp(-abs(p.x-center)*77.)*smoothstep(.77,.94,p.y);
    float stria=valueNoise(vec2(p.x*215.+sin(p.y*19.+t*.23)*.46,p.y*4.+t*.11));
    float shine=(.32+.68*stria)*valley;
    return under+vec3(.047,.215,.303)*shine*(.46+.54*depth);
}
// Individual cap stones sit above visible vertical courses. Coordinates are
// in delivery pixels so joints and chipping hold their size at native scale.
vec4 railCourse(vec2 s,vec2 a,vec2 b,float halfWidth,float rise,float ornate){
    vec2 axis=b-a;
    float len=length(axis);
    vec2 u=axis/len,v=vec2(-u.y,u.x);
    float noise=valueNoise(s*1.35)*.47+valueNoise(s*.36)*.53;
    float chip=smoothstep(.60,.84,noise)*1.32;
    vec4 outc=vec4(0.);
    for(int face=0;face<2;face++){
        vec2 local=s-a-vec2(0.,face==0?rise:0.);
        float x=dot(local,u),y=dot(local,v);
        float courses=max(1.,floor(len/8.));
        float j=fract(x/len*courses);
        float joint=min(j,1.-j)*len/courses;
        float d=min(min(x,len-x),halfWidth-abs(y))-chip;
        if(d<-.5)continue;
        float id=floor(x/len*courses);
        float grain=valueNoise(vec2(x*.32,y*1.4)+id);
        vec3 base=mix(vec3(.37,.354,.30),vec3(.74,.72,.63),.48*noise+.32*grain+.2*valueNoise(vec2(id,13.)));
        float border=min(joint,halfWidth-abs(y));
        base*=.60+.40*smoothstep(.01,.53,border-chip*.7);
        base+=vec3(.12,.11,.083)*exp(-abs(border-chip-.61)*3.);
        if(face==0)base*=vec3(.44,.49,.53);
        else if(ornate>.5){
            vec2 tile=vec2(fract(x/6.)*6.,y+halfWidth);
            float line=min(abs(abs(y)-halfWidth+.57),max(abs(tile.x-2.9)-1.8,abs(tile.y-2.8)-1.35));
            float fret=min(abs(line),max(abs(tile.y-2.6),abs(tile.x-3.4)-1.05));
            base=mix(base*vec3(.91,.81,.65),vec3(.19,.19,.16),.72*(1.-smoothstep(.11,.49,fret)));
        }
        float alpha=smoothstep(-.45,.45,d);
        outc=vec4(mix(outc.rgb,base,alpha/max(.001,alpha+outc.a*(1.-alpha))),alpha+outc.a*(1.-alpha));
    }
    return outc;
}
vec4 railOver(vec4 a,vec4 b){
    float alpha=b.a+a.a*(1.-b.a);
    return vec4(mix(a.rgb,b.rgb,b.a/max(alpha,.0001)),alpha);
}
vec4 brokenCauseway(vec2 p,float t){
    vec2 s=p*vec2(880.,376.);
    if(s.x<464.||s.x>604.||s.y<295.)return vec4(0.);
    vec4 c=vec4(0.);
    if(s.x<559.){
        // The turning bay has a skewed arch. Its narrow west jamb
        // descends into the open channel behind the broken near parapet.
        vec2 arch=s-vec2(529.4,314.4);
        if(arch.x>=-2.3&&arch.x<=22.4&&arch.y>=-1.&&arch.y<35.){
            float u=clamp(arch.x/21.6,0.,1.);
            float crown=20.7*u+1.5;
            float bottom=crown+4.1+7.6*pow(1.-u,6.);
            float strut=2.1-.034*arch.y;
            float vertical=min(strut-abs(arch.x+.076*arch.y),35.-arch.y);
            float shape=max(vertical,min(arch.y-crown,bottom-arch.y));
            float n=stoneNoise(s*1.7);
            float joint=abs(fract(arch.y*.23+.10*arch.x)-.5);
            vec3 cutStone=mix(vec3(.166,.205,.20),vec3(.44,.43,.35),n)
                         *(.73+.27*smoothstep(.014,.105,joint));
            float innerRim=exp(-abs(bottom-arch.y-.73)*2.8)*smoothstep(.06,.30,u);
            c=vec4(cutStone+innerRim*vec3(.12,.11,.09),smoothstep(-.32,.32,shape+(n-.5)*.8));
        }
        c=railOver(c,railCourse(s,vec2(473,308),vec2(496,307),2.8,4.3,0.));
        c=railOver(c,railCourse(s,vec2(497,307),vec2(530,313),2.8,4.3,0.));
        c=railOver(c,railCourse(s,vec2(531,313),vec2(550,338),3.2,4.7,0.));
        c=railOver(c,railCourse(s,vec2(550,338),vec2(516,382),3.6,4.3,1.));
        c=railOver(c,railCourse(s,vec2(528,309),vec2(534,310),2.,5.,0.));
        c=railOver(c,railCourse(s,vec2(545,334),vec2(551,336),2.2,4.,0.));
    }
    vec2 q=s-vec2(580.8,317.);
    q.y+=q.x*.08;
    float h=6.1+.060*q.x;
    float axial=q.x+1.5*sqrt(max(0.,1.-q.y*q.y/(h*h)));
    float edge=min(14.4-abs(axial),h-abs(q.y));
    if(edge>-.45){
        float ny=clamp(q.y/h,-1.,1.);
        float phase=asin(ny)*8.;
        float wear=valueNoise(s*1.65);
        float light=.48+.48*sqrt(max(0.,1.-ny*ny))-.29*ny;
        float flutes=.82+.18*smoothstep(-.68,.2,cos(phase+.13*wear));
        float fissure=abs(q.x+4.5+.27*q.y+1.1*valueNoise(s*.77));
        float tooling=abs(max(abs(q.x-2.)-3.6,abs(q.y+1.1)-1.5));
        vec3 stone=vec3(.67,.63,.54)*light*flutes*(.84+.22*wear);
        stone*=1.-.32*exp(-fissure*3.4)-.19*exp(-tooling*3.8);
        float band=min(abs(abs(axial-1.)-9.2),abs(abs(axial-1.)-10.9));
        stone=mix(stone,vec3(.56,.38,.19)*light*(.85+.36*cos(band*3.4)),1.-smoothstep(.34,.89,band));
        stone=mix(stone,vec3(.22,.27,.25)*(.7+.41*wear),smoothstep(12.4,14.,axial));
        c=railOver(c,vec4(stone,smoothstep(-.45,.45,edge-(wear-.5)*.62)));
    }
    return c;
}

void domeContact(inout vec4 col,vec2 s,vec2 root,vec2 scale,float depth){
    vec2 q=(s-root)/scale;
    float shadow=exp(-2.35*dot(q,q));
    if(shadow>.01)rfOver(col,vec3(.029,.062,.066),shadow*depth);
}

// Uneven branches have pale tips and keep widening where they meet the substrate.
void domeFingers(inout vec4 col,vec2 s,vec2 root,vec2 size,vec3 tone,float seed){
    vec2 q=(s-root)/size.y;
    float spread=size.x/size.y;
    if(abs(q.x)>spread+.16||q.y< -1.17||q.y>.20)return;
    domeContact(col,s,root+vec2(.2,.7),size*vec2(.76,.25),.68);
    for(int i=0;i<11;i++){
        float k=float(i);
        float u=hash12(vec2(k,seed));
        float v=hash12(vec2(k,seed+17.));
        float fan=k*.2-1.+.17*(u-.5);
        vec2 base=vec2(spread*fan*(.16+.18*v),.087*v-.038);
        vec2 tip=vec2(spread*(fan*(.56+.39*u)+.16*(v-.5)),
                      -(.29+.47*u+.28*(1.-abs(fan))+.08*sin(seed+3.9*k)));
        vec2 bend=mix(base,tip,.49)-vec2(spread*(fan*.09+.10*(v-.5)),.047*v);
        float width=mix(.031,.086,v);
        vec3 branch=tone*(.48+.51*v);
        rfTube(col,q,base,bend,width*1.35,width,branch*.78,k+seed);
        if(i%3!=1){
            vec2 elbow=mix(bend,tip,.50)+vec2(spread*(v-.45)*.24,-.023);
            vec2 fork=mix(bend,tip,.79)+vec2(spread*(v-.44)*.61,-.13*u);
            rfTube(col,q,bend,elbow,width*.65,width*.56,branch*.81,k+seed+30.);
            rfTube(col,q,elbow,fork,width*.58,width*.38,branch*(1.07+.22*v),k+seed+31.);
        }
        vec2 collar=mix(bend,tip,.70);
        rfTube(col,q,bend,collar,width,width*.73,branch*1.04,k+seed);
        rfTube(col,q,collar,tip,width*.73,width*.49,branch*1.14+vec3(.145,.110,.084)*v,k+seed);
    }
}

// Lobed, knobby patches follow an oblique surface and overlap at their bases.
void domeCrust(inout vec4 col,vec2 s,vec2 center,vec2 scale,float lean,vec3 base,float seed){
    vec2 q=rfRotate(s-center,lean)/scale;
    if(any(greaterThan(abs(q),vec2(1.47,1.66))))return;
    domeContact(col,s,center+vec2(.35,.87),scale*vec2(.93,.66),.68);
    for(int i=0;i<13;i++){
        float k=float(i);
        float a=k*2.39996+seed;
        float jitter=hash12(vec2(seed,k));
        float r=sqrt(k/13.)*(.70+.24*jitter);
        vec2 origin=r*vec2(cos(a),.83*sin(a));
        vec2 local=q-origin;
        float w=.17+.21*jitter;
        float h=w*(.63+.42*hash12(vec2(k,seed+11.)));
        vec2 d=local/vec2(w,h);
        float block=length(d);
        if(block>1.19)continue;
        float theta=atan(d.y,d.x+1.e-6);
        float grain=rfRelief(s*1.8+seed+k);
        float pores=rfNoise(s*3.9+seed+k);
        float lobes=1.+.078*cos(theta*(4.+floor(jitter*3.))+a)+.087*cos(theta*3.+k)+.20*(pores-.51);
        float mask=1.-smoothstep(lobes-.14,lobes+.10,block);
        float tilt=clamp(.74-.30*d.y-.20*d.x,0.,1.05);
        float highlight=exp(-dot(d+vec2(.27,.40),d+vec2(.27,.40))*2.);
        float polyp=pow(.5+.5*cos(theta*7.+a+.31*grain),4.);
        float crown=exp(-abs(block-.59)*7.)*polyp;
        float throat=exp(-block*block*13.);
        vec3 lit=base*(.39+.55*tilt+.29*grain)*(.68+.29*jitter);
        lit+=vec3(.175,.199,.195)*highlight*.54;
        lit+=vec3(.19,.224,.203)*crown*(.28+.39*jitter)*tilt;
        lit*=1.-.38*smoothstep(.62,.88,pores)-throat*.21;
        rfOver(col,lit,mask);
    }
}

// Layered foliose plates expose a round catchlight around the near lip.
void domePlate(inout vec4 col,vec2 s,vec2 c,vec2 scale,float angle,vec3 clay,vec3 lip,float seed){
    vec2 q=rfRotate(s-c,angle)/scale;
    if(any(greaterThan(abs(q),vec2(1.32,1.72))))return;
    domeContact(col,s,c+vec2(.60,2.4),scale*vec2(1.,.77),.84);
    float theta=atan(q.y,q.x+.00001);
    float r=length(q);
    float waves=.073*cos(theta*5.+seed)+.044*cos(theta*9.-seed)+.019*sin(theta*16.+seed);
    float rim=1.+waves+.06*sin(theta+seed);
    float grain=rfRelief(s*vec2(1.3,2.5)+seed);
    float fan=.5+.5*cos(18.*theta+1.22*sin(3.*theta+seed)+2.9*r+grain);
    float stripe=.5+.5*cos(37.*r+1.2*fan+2.1*grain);
    float underside=length(vec2(q.x*1.07,(q.y-.38)*1.04));
    float skirt=rfMask(underside-1.-waves*.60,.067)*smoothstep(.12,.55,q.y);
    vec3 skin=clay*(.21+.23*fan+.20*grain)+lip*.12*exp(-abs(underside-1.)*12.);
    rfOver(col,skin,skirt);
    float side=clamp(.69+.23*q.y-.17*q.x,.38,1.12);
    float slope=smoothstep(.30,rim,length(q-vec2(.04,.21)));
    float seat=exp(-dot(q-vec2(.05,.16),q-vec2(.05,.16))*6.1);
    vec3 bowl=clay*(.28+.46*slope+.19*grain+.11*fan*slope+.07*stripe-.090*seat);
    float polish=.55+.45*smoothstep(.18,.75,grain-.08*q.x);
    bowl+=lip*side*exp(-abs(r-rim+.06)*19.)*polish*(.57+.46*grain);
    bowl+=lip*.41*side*exp(-abs(r-rim+.16)*12.)*smoothstep(.38,.88,fan);
    rfOver(col,bowl,rfMask(r-rim,.051));
}

void domeGlow(inout vec4 col,vec2 s,vec2 c,float radius,float intensity,float time){
    vec2 q=(s-c)/radius;
    q.x+=q.y*.16;
    float d=dot(q,q);
    if(d>17.)return;
    float shine=intensity*(.91+.09*sin(time*1.8+c.x));
    rfOver(col,vec3(.071,.37,.47),exp(-d*.23)*shine*.46);
    rfOver(col,vec3(.16,.79,.88),exp(-d*1.45)*shine*.79);
    rfOver(col,vec3(.53,.96,.96),exp(-d*3.9)*shine*.68);
}

struct DomeCrustPatch {
    vec4 bounds;
    vec4 tint;
    float angle;
};

// Sessile colonies attach to the front ledge, fracture edges and the surviving shell.
vec4 domeColonies(vec2 p,float time){
    vec4 cl=vec4(0.);
    const vec2 screen=vec2(880.,376.);
    vec2 s=p*screen;
    if(s.x<224.||s.x>459.||s.y<195.||s.y>320.)return cl;
    const vec3 olive=vec3(.245,.305,.18),blue=vec3(.225,.363,.448);
    const vec3 slate=vec3(.144,.244,.285),pink=vec3(.445,.253,.296);
    const vec3 ochre=vec3(.509,.382,.251),violet=vec3(.296,.310,.414);
    // Rim debris, turf and incrustations hug the stone instead of tracing an even ring.
    const DomeCrustPatch patches[45]=DomeCrustPatch[45](
        DomeCrustPatch(vec4(249.3,246.2,7.2,4.9),vec4(blue*.79,8.),-.18),
        DomeCrustPatch(vec4(255.7,243.4,6.0,3.1),vec4(slate*1.2,9.),-.34),
        DomeCrustPatch(vec4(264,238.8,7.1,2.9),vec4(olive*.83,11.),-.47),
        DomeCrustPatch(vec4(269.6,233.3,7.2,3.5),vec4(slate*.94,14.),-.54),
        DomeCrustPatch(vec4(279,229.5,6.3,2.7),vec4(olive*.83,17.),-.57),
        DomeCrustPatch(vec4(318.3,220.4,6.3,2.9),vec4(violet*1.24,18.),-.06),
        DomeCrustPatch(vec4(355.6,214.5,5.6,1.9),vec4(olive*1.20,21.),.34),
        DomeCrustPatch(vec4(361.8,220.2,6.8,2.8),vec4(olive,22.),.54),
        DomeCrustPatch(vec4(368.5,223.5,4.6,1.6),vec4(olive*1.1,23.),.54),
        DomeCrustPatch(vec4(363.4,215.4,4.5,1.3),vec4(pink*.80,24.),.43),
        DomeCrustPatch(vec4(344.1,255.5,3.1,1.4),vec4(slate*1.35,25.),.15),
        DomeCrustPatch(vec4(355.8,257.9,4.3,2.1),vec4(pink,27.),-.18),
        DomeCrustPatch(vec4(361.4,256.7,3.0,1.5),vec4(slate*1.43,28.),-.10),
        DomeCrustPatch(vec4(364.2,263.1,4.4,2.5),vec4(blue*.93,29.),-.14),
        DomeCrustPatch(vec4(265.5,273.5,9.1,6.0),vec4(slate*1.1,32.),-.13),
        DomeCrustPatch(vec4(269.9,266.8,6.8,3.4),vec4(slate,34.),-.61),
        DomeCrustPatch(vec4(284.2,284.,9.7,6.2),vec4(blue,37.),-.12),
        DomeCrustPatch(vec4(296.3,289.8,5.1,3.7),vec4(ochre*.87,40.),.19),
        DomeCrustPatch(vec4(331,282.4,8.5,6.3),vec4(violet*1.12,41.),-.17),
        DomeCrustPatch(vec4(334,273.5,4.7,4.2),vec4(olive*1.19,42.),.34),
        DomeCrustPatch(vec4(341,282.3,4.1,2.6),vec4(pink*1.15,43.),.14),
        DomeCrustPatch(vec4(351.7,282.9,6.8,4.8),vec4(ochre*1.11,44.),-.23),
        DomeCrustPatch(vec4(357.1,288.6,6.6,4.3),vec4(blue*1.09,45.),-.18),
        DomeCrustPatch(vec4(368,284.3,5.4,2.2),vec4(olive,47.),-.21),
        DomeCrustPatch(vec4(375.4,284.5,3.3,1.7),vec4(pink*.92,48.),.09),
        DomeCrustPatch(vec4(385.1,278.3,6.2,2.6),vec4(olive*.87,49.),-.22),
        DomeCrustPatch(vec4(406.9,269.5,4.1,2.8),vec4(ochre*1.21,51.),-.18),
        DomeCrustPatch(vec4(410.9,262.1,5.6,3.9),vec4(pink*1.04,53.),.17),
        DomeCrustPatch(vec4(401.2,258.8,5.7,3.2),vec4(ochre,55.),-.34),
        DomeCrustPatch(vec4(416.2,258.3,7.3,4.7),vec4(blue*1.15,56.),-.26),
        DomeCrustPatch(vec4(245.2,280.7,5.1,2.5),vec4(slate,57.),-.08),
        DomeCrustPatch(vec4(253.6,279.1,4.7,1.9),vec4(olive,59.),.10),
        DomeCrustPatch(vec4(316.3,295.4,9.9,1.8),vec4(olive*.86,60.),.01),
        DomeCrustPatch(vec4(346.2,292.7,6.9,1.5),vec4(olive*.90,61.),-.18),
        DomeCrustPatch(vec4(368.2,289.8,7.1,1.8),vec4(olive,62.),.05),
        DomeCrustPatch(vec4(387,282.8,7.3,1.9),vec4(olive*.92,63.),-.17),
        DomeCrustPatch(vec4(303.8,265.4,3.9,2.2),vec4(ochre*1.21,64.),-.45),
        DomeCrustPatch(vec4(308.8,262.4,3.2,1.5),vec4(olive*1.30,65.),.23),
        DomeCrustPatch(vec4(275.4,275.1,5.6,3.7),vec4(blue*.89,66.),-.1),
        DomeCrustPatch(vec4(291.2,286.1,3.9,2.9),vec4(slate*1.14,69.),.12),
        DomeCrustPatch(vec4(327,288.9,4.6,2.8),vec4(blue*1.06,70.),-.28),
        DomeCrustPatch(vec4(334.1,287.3,4.1,2.7),vec4(blue*1.01,71.),-.21),
        DomeCrustPatch(vec4(362.5,286.4,3.0,2.2),vec4(pink*.71,72.),.31),
        DomeCrustPatch(vec4(394.3,273.3,4.1,2.8),vec4(olive*1.17,73.),-.12),
        DomeCrustPatch(vec4(405.4,264.8,3.8,2.1),vec4(pink,74.),-.1));
    for(int i=0;i<45;i++){
        DomeCrustPatch growth=patches[i];
        domeCrust(cl,s,growth.bounds.xy,growth.bounds.zw,growth.angle,growth.tint.rgb,growth.tint.a);
    }

    const vec4 fingersBounds[13]=vec4[13](
        vec4(274.,231.3,7.1,17.3),
        vec4(269.1,238.6,5.4,9.2),
        vec4(251.5,275.4,10.2,16.5),
        vec4(258.2,273.7,4.4,8.6),
        vec4(386.8,265.8,9.0,17.5),
        vec4(361.,253.,5.5,10.5),
        vec4(404.7,249.,5.8,11.4),
        vec4(364.6,267.1,4.5,6.1),
        vec4(282.5,286.6,8.6,7.9),
        vec4(329.3,287.5,9.7,8.7),
        vec4(355.,286.4,6.7,6.5),
        vec4(415.1,258.9,7.3,7.1),vec4(318.3,220.9,3.9,3.4));
    const vec4 fingersTone[13]=vec4[13](
        vec4(vec3(.64,.42,.29),3.),
        vec4(pink*.72,22.),
        vec4(ochre*1.21,6.),
        vec4(ochre,32.),
        vec4(pink*1.39,7.),
        vec4(ochre*1.33,10.),
        vec4(ochre*.87,14.),
        vec4(blue*1.08,19.),
        vec4(blue*1.21,24.),
        vec4(violet*1.36,13.),
        vec4(ochre*1.29,25.),
        vec4(blue*1.07,16.),vec4(violet*1.23,17.));
    for(int i=0;i<13;i++){
        vec4 bounds=fingersBounds[i];
        vec4 shade=fingersTone[i];
        domeFingers(cl,s,bounds.xy,bounds.zw,shade.rgb,shade.a);
    }

    vec3 clay=vec3(.375,.293,.240),lip=vec3(.76,.693,.551);
    const vec4 platesBounds[8]=vec4[8](
        vec4(317.5,269.2,8.2,4.4),
        vec4(316.3,265.7,8.0,4.4),
        vec4(303.4,275.1,7.7,3.6),
        vec4(306.4,273.1,10.2,4.4),
        vec4(295.3,281.8,6.5,3.1),
        vec4(309.4,285.7,7.6,3.5),
        vec4(399.2,265.8,6.1,3.0),
        vec4(426.4,276.9,5.8,2.6));
    const vec4 platesStyle[8]=vec4[8](
        vec4(-.21,.88,.87,5.),
        vec4(.18,1.01,.97,8.),
        vec4(-.10,.77,.77,2.),
        vec4(.05,1.,1.23,4.),
        vec4(-.29,.83,.73,3.),
        vec4(.18,.79,.76,6.),
        vec4(-.15,1.,.88,9.),
        vec4(.12,.92,.82,13.));
    for(int i=0;i<8;i++){
        vec4 bounds=platesBounds[i];
        vec4 style=platesStyle[i];
        domePlate(cl,s,bounds.xy,bounds.zw,style.x,clay*style.y,lip*style.z,style.w);
    }

    rfCoral(cl,p,vec2(.51,.758),vec2(.018,.047),vec3(.31,.32,.13),8.,0.);
    // The draped tentacles emerge from the overturned vessel on the edge.
    vec2 q=s-vec2(415.,295.);
    if(length(q)<35.){
        for(int i=0;i<8;i++){
            float k=float(i),theta=-.18+k*.35;
            vec2 dir=vec2(cos(theta),sin(theta));float len=18.+8.*sin(k*1.62);
            float u=clamp(dot(q,dir)/len,0.,1.);
            vec2 bend=vec2(-dir.y,dir.x)*(2.4*sin(u*6.+k+.2*time)*u);
            float d=length(q-dir*len*u-bend);
            float w=2.2*pow(1.001-u,.66);
            rfOver(cl,mix(vec3(.22,.095,.08),vec3(.6,.34,.29),exp(-abs(d-.7)*.9)),1.-smoothstep(w-.3,w+.5,d));
        }
        vec2 jar=(s-vec2(411.,289.))*mat2(.84,.54,-.54,.84);
        float j=length(jar/vec2(8.,5.));
        float grooves=exp(-abs(abs(jar.x)-5.5)*1.4)+.69*exp(-abs(abs(jar.x)-4.0)*2.4);
        vec3 clayBody=mix(vec3(.143,.108,.081),vec3(.61,.451,.256),exp(-abs(jar.y+2.3)*.57));
        clayBody+=vec3(.231,.153,.086)*grooves*(.53+.47*valueNoise(s*1.9));
        rfOver(cl,clayBody,1.-smoothstep(.90,1.04,j));
    }
    // Separate small polyps anchor the cyan clusters at the foot of the copper.
    domeGlow(cl,s,vec2(264.5,263.4),1.15,.83,time);
    domeGlow(cl,s,vec2(264.0,262.1),.72,.48,time);
    domeGlow(cl,s,vec2(381.7,273.3),1.42,1.,time);
    domeGlow(cl,s,vec2(383.0,273.8),.84,.87,time);
    domeGlow(cl,s,vec2(380.9,271.9),.69,.70,time);
    domeGlow(cl,s,vec2(390.7,272.0),.76,.68,time);
    return rfFinish(cl);
}
// Patch reefs at the broken ends of the arcades and the margin of the plaza.
// Use a colony-scale envelope and uneven, independently shaded lobes.
vec3 reefGardens(vec2 p,vec3 rgb,float t){
    vec2 s=p*vec2(880.,376.);
    const vec4 roots[13]=vec4[13](vec4(257,223,15,5),vec4(385,202,9,8),vec4(502,235,16,6),vec4(524,235,10,9),
        vec4(543,256,16,9),vec4(562,288,11,9),vec4(592,271,17,5),vec4(631,259,19,5),
        vec4(645,200,19,6),vec4(705,249,17,9),vec4(742,261,20,8),vec4(681,298,20,11),
        vec4(434,283,16,10));
    for(int i=0;i<13;i++){
        vec4 cluster=roots[i];vec2 local=(s-cluster.xy)/cluster.zw;
        if(abs(local.x)>1.15||abs(local.y)>.99)continue;
        float k=float(i);
        for(int j=0;j<10;j++){
            float index=float(j);
            vec2 rnd=vec2(hash12(vec2(k,index)),hash12(vec2(index,k+13.)));
            vec2 center=vec2((rnd.x-.5)*1.64,(rnd.y-.5)*.75);
            vec2 d=local-center;
            float width=.085+.17*rnd.y;
            float h=width*(.8+1.1*hash12(vec2(k+73.,index)));
            vec2 scaled=d/vec2(width,h);
            float r=length(scaled);
            if(r>1.2)continue;
            float a=atan(scaled.y,scaled.x+.0001);
            float lobed=1.+.11*sin(a*(5.+floor(rnd.y*5.))+index);
            float opacity=(1.-smoothstep(lobed-.18,lobed+.10,r))*(.77+.20*rnd.x);
            float grain=valueNoise(s*.85+k);
            float spec=sceneSquare(max(0.,1.-length(scaled-vec2(-.3,-.5))*.98));
            vec3 coral=mix(vec3(.12,.16,.18),vec3(.35,.19,.21),rnd.y);
            if((i%4)==0)coral=mix(coral,vec3(.14,.28,.32),.63);
            vec3 light=coral*(.62+.44*grain)+(.18*max(0.,-scaled.y)+.10*spec)*vec3(1.,.91,.79);
            float holes=smoothstep(.5,.82,valueNoise(s*1.74+index));
            rgb=mix(rgb,light*(1.-.31*holes),opacity);
        }
    }
    return rgb;
}

// Animated pelagic school and free-swimming animals. Coordinates are screen UV (y down).
const float FISH_ASPECT = 4400.0 / 1884.0;

float fishHash(float n) {
    return hash12(vec2(floor(n*103.0), 173.0));
}

vec4 fishOver(vec4 background, vec4 foreground) {
    float a = foreground.a + background.a * (1.0 - foreground.a);
    vec3 c = foreground.rgb * foreground.a + background.rgb * background.a * (1.0 - foreground.a);
    return vec4(c / max(a, .00001), a);
}

float fishCross(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

float fishSegment(vec2 p, vec2 a, vec2 b) {
    vec2 edge = b - a;
    return length(p - a - edge * clamp(dot(p - a, edge) / max(dot(edge, edge), 1e-7), 0.0, 1.0));
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

// Each fish starts behind the retaining gallery, rounds its west end,
// crosses the front steps, then returns behind the east colonnade.
vec4 templeSchool(vec2 p, float t, float cameraTime) {
    vec4 school = vec4(0.);
    if (p.x < .31 || p.x > .86 || p.y < .43 || p.y > .75) return school;
    vec2 cityOffset = vec2(.36 * sin(.73 * cameraTime), -.25 * sin(.39 * cameraTime));
    float templeAlpha = -1.;
    for (int i = 0; i < 24; ++i) {
        float k = float(i);
        float seed = fishHash(k + 72.);
        float row = float(i % 4) - 1.5;
        float delay = .115 * float(i / 4) + .045 * seed;
        float swimTime = max(t - delay, 0.);
        // Integrate a smooth acceleration out of shelter.
        float angle = 1.38 * (swimTime - .23 * (1. - exp(-swimTime / .23)));
        vec2 orbit = vec2(-sin(angle), -cos(angle));
        vec2 radius = vec2(.215 + .008 * row + .009 * seed, .083 + .005 * row);
        vec2 center = vec2(.59, .575) + radius * orbit;
        center.x += .009 * row + .009 * (seed - .5);
        center.y += .008 * row + .005 * sin(2. * angle + k);
        vec2 tangent = radius * vec2(-cos(angle), sin(angle));
        tangent.y += .010 * cos(2. * angle + k);
        float nearSide = .5 + .5 * orbit.y;
        float size = mix(.010, .025, nearSide) * (.83 + .33 * seed);
        vec4 fish = fishIndividual(p, center, atan(tangent.y / FISH_ASPECT, tangent.x),
                                   size, mix(.19, .79, nearSide), seed, t);
        if (fish.a <= 0.) continue;
        // Both depth crossings happen in open water outside the temple bounds.
        if (orbit.y < 0.) {
            if (templeAlpha < 0.) {
                vec4 temple = vec4(0.);
                ctMainTemple(temple, p * vec2(1760., 754.) + cityOffset);
                templeAlpha = temple.a;
            }
            fish.a *= 1. - templeAlpha;
        }
        school = fishOver(school, fish);
    }
    return school;
}

vec4 fishPatrol(vec2 p, vec2 at, float size, float facing, float pitch, float t, float phase, float opacity) {
    vec2 d = (p - at) * vec2(facing, 1.0 / FISH_ASPECT);
    if (max(abs(d.x), abs(d.y)) > size * 1.17) return vec4(0.0);
    vec2 q = vec2(d.x, d.y - d.x * pitch) / size;
    float x = clamp((q.x + .78) / 1.70, 0.0, 1.0);
    float center = -.022 * smoothstep(.2, 1.0, x);
    float halfBody = .128 * pow(max(4.0 * x * (1.0 - x), 0.0), .7) * smoothstep(.0, .43, x);
    float body = max(abs(q.y - center) - halfBody, max(-q.x - .78, q.x - .92));
    float wag = .055 * sin(8.9 * t + phase);
    float topFin = fishTriangle(q, vec2(-.18, -.075), vec2(-.35, -.292), vec2(.063, -.108));
    float flipper = fishTriangle(q, vec2(-.01, .064), vec2(-.38, .214), vec2(.34, .05));
    float tail = fishTriangle(q, vec2(-.69, .0), vec2(-1.10, -.235 + wag), vec2(-.94, .035 + wag));
    tail = min(tail, fishTriangle(q, vec2(-.68, .0), vec2(-.94, .035 + wag), vec2(-1.06, .16 + wag)));
    float edge = max(.030, .00059 / size);
    float a = 1.0 - smoothstep(-edge * .35, edge, min(min(body, flipper), min(topFin, tail)));
    vec3 color = mix(vec3(.050, .194, .249), vec3(.068, .246, .303), smoothstep(-.12, .15, q.y));
    color += .025 * exp(-9.0 * abs(q.y + halfBody + .012)) * smoothstep(.15, .58, x);
    return vec4(color, a * opacity);
}

vec2 fishBezier(vec2 a, vec2 b, vec2 c, float u) {
    return mix(mix(a, b, u), mix(b, c, u), u);
}

bool fishEdgeCrossing(vec2 q, vec2 a, vec2 b) {
    return ((a.y > q.y) != (b.y > q.y))
        && ((fishCross(b - a, q - a) > 0.0) == (b.y > a.y));
}

float fishRayWing(vec2 q, vec2 rootUpper, vec2 rootLower, vec2 tip, vec2 upperControl, vec2 lowerControl) {
    float distanceToWing = fishSegment(q, rootUpper, rootLower);
    bool inside = fishEdgeCrossing(q, rootUpper, rootLower);
    vec2 upper = rootUpper;
    vec2 lower = rootLower;
    for (int i = 1; i <= 6; i++) {
        float u = float(i) / 6.0;
        vec2 nextUpper = fishBezier(rootUpper, upperControl, tip, u);
        vec2 nextLower = fishBezier(rootLower, lowerControl, tip, u);
        distanceToWing = min(distanceToWing, fishSegment(q, upper, nextUpper));
        distanceToWing = min(distanceToWing, fishSegment(q, lower, nextLower));
        inside = inside != fishEdgeCrossing(q, upper, nextUpper);
        inside = inside != fishEdgeCrossing(q, lower, nextLower);
        upper = nextUpper;
        lower = nextLower;
    }
    return inside ? -distanceToWing : distanceToWing;
}

// Main animal banks from a bright frontal pose into a dark, close side pass.
vec3 fishRayTrack(float t) {
    const vec3 positions[19] = vec3[19](
        vec3(.198,.285,.010), vec3(.191,.287,.011), vec3(.188,.294,.014),
        vec3(.188,.302,.018), vec3(.194,.311,.022), vec3(.201,.324,.027),
        vec3(.220,.338,.030), vec3(.248,.350,.034), vec3(.284,.364,.038),
        vec3(.339,.377,.054), vec3(.397,.389,.058), vec3(.478,.394,.067),
        vec3(.568,.392,.080), vec3(.648,.387,.079), vec3(.729,.374,.082),
        vec3(.809,.378,.081), vec3(.893,.389,.073), vec3(1.012,.402,.070),
        vec3(1.119,.414,.066)
    );
    float sampleTime = clamp(t * 4.0, 0.0, 18.0);
    int index = min(int(floor(sampleTime)), 17);
    vec3 a = positions[index];
    vec3 b = positions[index + 1];
    vec3 startTangent = .5 * (b - positions[max(index - 1, 0)]);
    vec3 endTangent = .5 * (positions[min(index + 2, 18)] - a);
    float u = sampleTime - float(index);
    return mix(a, b, u * u * (3.0 - 2.0 * u))
         + u * (1.0 - u) * (startTangent * (1.0 - u) - endTangent * u);
}

vec4 fishRayWingTips(float t) {
    const vec4 poses[10] = vec4[10](
        vec4(-.77,-.11, 1.04,-.48), vec4(-.54,-.36, .63,-.45),
        vec4(-.31,-.49, .60,-.55), vec4(-.11,-.45, .40,-.50),
        vec4( .25,-.33, .12, .32), vec4( .75,-.32, .09, .34),
        vec4( .96,-.31, .19, .38), vec4(1.00,-.27, .15, .35),
        vec4( .82,-.16, .16, .32), vec4( .78,-.24, .13, .24)
    );
    float sampleTime = clamp((t - 2.0) * 4.0, 0.0, 9.0);
    int index = min(int(floor(sampleTime)), 8);
    return mix(poses[index], poses[index + 1], smoothstep(0.0, 1.0, sampleTime - float(index)));
}

vec4 fishMainRay(vec2 p, float t) {
    if (t > 4.49) return vec4(0.0);
    vec3 track = fishRayTrack(t);
    float width = track.z;
    vec2 q = (p - track.xy) * vec2(1.0, 1.0 / FISH_ASPECT) / width;
    if (abs(q.x) > 1.84 || abs(q.y) > .87) return vec4(0.0);

    float bank = smoothstep(1.29, 2.21, t);
    float dark = smoothstep(1.73, 2.62, t);
    float upstroke = sin(5.8 * t - .75);
    vec4 tips = fishRayWingTips(t);
    vec2 nearTip = mix(vec2(-1.03, -.44 - .12 * upstroke), tips.xy, bank);
    vec2 farTip = mix(vec2(1.03, -.35 + .16 * upstroke), tips.zw, bank);

    vec2 head = q - vec2(.066, .022);
    head.y -= .098 * head.x * smoothstep(.98, 1.64, t);
    vec2 frontalRadii = vec2(mix(.355, .522, smoothstep(.94, 1.89, t)), .245);
    float frontBody = (length(head / frontalRadii) - 1.0) * frontalRadii.y;
    float along = clamp((q.x + .90) / 1.86, 0.0, 1.0);
    float spine = mix(-.142, .158, along) - .020 * sin(3.14159 * along);
    float profile = pow(max(sin(3.14159 * along), 0.0), .72);
    float snout = smoothstep(.47, .99, along);
    float backDepth = .111 * profile * (1.0 - .20 * snout);
    float bellyDepth = .144 * profile * (1.0 - .30 * snout);
    float offset = q.y - spine;
    float sideBody = max(max(-offset - backDepth, offset - bellyDepth), max(-q.x - .90, q.x - .96));
    float body = mix(frontBody, sideBody, bank);

    // The visible fin sweeps forward during the roll. Its outer edge curls up
    // while the farther fin passes behind the belly.
    float nearRootX = mix(nearTip.x - .48, .13, smoothstep(.26, .93, nearTip.x));
    vec2 nearBack = mix(vec2(-.24,-.010), vec2(nearRootX,-.073), bank);
    vec2 nearFront = mix(vec2(.09,.232), vec2(min(.88, nearTip.x + .45), .159), bank);
    vec2 nearBackCurve = mix(vec2(-.62,-.012), mix(nearBack, nearTip, .59) + vec2(-.068,.133), bank);
    vec2 nearFrontCurve = mix(vec2(-.37,.250), mix(nearFront, nearTip, .63) + vec2(.121,.023), bank);
    float nearWing = fishRayWing(q, nearBack, nearFront, nearTip, nearBackCurve, nearFrontCurve);

    float farUnderside = smoothstep(-.16, .24, farTip.y);
    vec2 farBack = mix(vec2(.17,-.045), vec2(farTip.x - .39, mix(-.083,.118,farUnderside)), bank);
    vec2 farFront = mix(vec2(.10,.234), vec2(farTip.x + .42, mix(.105,.157,farUnderside)), bank);
    vec2 farBackCurve = mix(vec2(.63,.111), mix(farBack, farTip, .58) + vec2(-.026,.10), bank);
    vec2 farFrontCurve = mix(vec2(.70,.185), mix(farFront, farTip, .63) + vec2(.072,.018), bank);
    float farWing = fishRayWing(q, farBack, farFront, farTip, farBackCurve, farFrontCurve);

    float dorsalX = mix(-.26,-.37,smoothstep(3.01,3.80,t));
    float dorsal = fishTriangle(q, vec2(dorsalX - .17,-.13), vec2(dorsalX - .04,-.257),
                                vec2(dorsalX + .14,-.10));
    dorsal += .29 * (1.0 - farUnderside * bank);

    vec2 tailRoot = mix(vec2(-.16,.13), vec2(-.49,-.081), bank);
    vec2 tailMiddle = mix(vec2(-.54,.181), vec2(-.94,-.149), bank);
    float reach = -1.54 + .45 * smoothstep(2.56, 3.0, t) - .14 * smoothstep(3.10, 3.54, t);
    vec2 tailTip = mix(vec2(-.94,.256), vec2(reach,-.19 + .055 * sin(5.1 * t)), bank);
    float tailTaper = .036 * (1.0 - smoothstep(.88, -reach, -q.x)) * bank;
    float tail = min(fishSegment(q, tailRoot, tailMiddle) - mix(.016,.031,bank),
                     fishSegment(q, tailMiddle, tailTip) - .008 - tailTaper);
    float broadBody = min(min(body, nearWing), min(farWing, dorsal));
    float edge = min(broadBody, tail);
    float blur = mix(.017, .038, dark) + .00027 / width;
    float alpha = 1.0 - smoothstep(-blur * .62, blur, edge);

    float lightFace = 1.0 - smoothstep(.005, .25, head.y);
    vec3 white = mix(vec3(.385,.448,.459), vec3(.934,.925,.865), lightFace);
    float paleStroke = smoothstep(.14, .85, t) * (1.0 - bank);
    float wingSurface = smoothstep(.42,.94,abs(q.x)) * paleStroke;
    white = mix(white, vec3(.937,.942,.899), wingSurface);
    white *= 1.0 - .54 * smoothstep(.146, .244, head.y);
    float earlyShadow = (1.0 - smoothstep(.28,.83,t)) * smoothstep(.36,.95,abs(q.x));
    white = mix(white, vec3(.107,.219,.277), earlyShadow * .88);

    float bodyHeight = offset / max(offset < 0.0 ? backDepth : bellyDepth,.037);
    float belly = smoothstep(.30,.91,bodyHeight);
    float backLight = exp(-pow((bodyHeight + .77) / .29, 2.0));
    backLight *= smoothstep(.012,.34,along) * (1.0 - smoothstep(.75,.99,along));
    vec3 back = mix(vec3(.019,.038,.054), vec3(.099,.253,.293), belly * .82);
    back += mix(vec3(.58,.49,.46), vec3(.207,.236,.252), dark) * backLight;

    float finColumn = q.x - nearTip.x;
    float foldY = mix(-.17, -.07, smoothstep(.25, .95, nearTip.x))
                + .49 * max(-finColumn, 0.0) + .50 * max(finColumn, 0.0);
    float visibleWing = 1.0 - smoothstep(.005,.057,nearWing);
    float underside = visibleWing * smoothstep(foldY - .041, foldY + .046, q.y);
    float finLight = exp(-pow((q.y - foldY - .11) / .225, 2.0));
    vec3 fin = mix(vec3(.014,.035,.052), vec3(.146,.335,.385), .91 * underside * finLight);
    float finCoverage = visibleWing * (1.0 - smoothstep(-.027,.022,nearWing - body));
    back = mix(back, fin, max(finCoverage, underside * .98));

    if (farUnderside > .05) {
        float underWing = (1.0 - smoothstep(-.024,.024,farWing - min(body, nearWing)))
                        * smoothstep(.12,.27,q.y);
        back = mix(back, vec3(.018,.057,.076), underWing * farUnderside);
    }
    if (tail < broadBody) {
        white *= .68;
        back *= .84;
    }
    return vec4(mix(white, back, dark), alpha * (1.0 - smoothstep(4.26, 4.49, t)));
}

vec4 fishSmallReef(vec2 p, float t) {
    if (p.y < .597) return vec4(0.0);
    const vec3 points[19] = vec3[19](
        vec3(.203,.785,.0069), vec3(.271,.817,.0038), vec3(.323,.826,.0040),
        vec3(.382,.861,.0057), vec3(.419,.865,.0042), vec3(.476,.909,.0067),
        vec3(.504,.882,.0041), vec3(.540,.923,.0054), vec3(.550,.913,.0063),
        vec3(.580,.968,.0068), vec3(.682,.867,.0071), vec3(.733,.713,.0063),
        vec3(.751,.695,.0047), vec3(.782,.644,.0058), vec3(.757,.823,.0049),
        vec3(.850,.773,.0045), vec3(.870,.786,.0053), vec3(.924,.809,.0047),
        vec3(.719,.705,.0044)
    );
    vec4 result = vec4(0.0);
    for (int i = 0; i < 19; i++) {
        float seed = fishHash(float(i) + 86.2);
        vec3 d = points[i];
        float side = (seed < .45) ? -1.0 : 1.0;
        vec2 center = d.xy + vec2(side * (.004 + .008 * seed) * t + .014 * sin(t * 1.48 + seed * 9.0),
                                  .017 * (sin(t * 1.91 + seed * 18.0) - sin(seed * 18.0)));
        if (abs(p.x - center.x) > d.z * 1.8 || abs(p.y - center.y) > .024) continue;
        vec2 q = (p - center) * vec2(side, 1.0 / FISH_ASPECT) / d.z;
        q.y += (.118 + .3 * sin(t * 1.65 + seed * 13.4)) * q.x;
        float h = (.36 + .16 * seed) * sqrt(max(0.0, 1.0 - q.x * q.x));
        float body = max(abs(q.y) - h, abs(q.x) - 1.0);
        float sway = .065 * sin(t * 23.0 + seed * 32.0);
        float tail = fishTriangle(q, vec2(-.72, .0), vec2(-1.36, -.28 + sway), vec2(-1.30, .28 + sway));
        float a = 1.0 - smoothstep(-.1, .25, min(body, tail));
        vec3 color = (seed < .59) ? vec3(.42,.313,.040) : ((seed < .84) ? vec3(.26,.087,.144) : vec3(.106,.208,.39));
        color *= mix(.61, 1.32, (1.0 - smoothstep(-.31, .24, q.y)));
        color += vec3(.24,.183,.065) * .51 * exp(-21.0 * abs(q.y + .29));
        result = fishOver(result, vec4(color, a * .84));
    }
    return result;
}

vec4 fishDistant(vec2 p, float t) {
    vec4 result = fishPatrol(p, vec2(.306 + .0105 * t, .137 + .0047 * t), .025, 1.0, .090, t, 1.2, .92);
    result = fishOver(result, fishPatrol(p, vec2(.827 - .0118 * t, .158 + .0048 * t), .026, -1.0, -.062, t, 4.2, .88));
    result = fishOver(result, fishPatrol(p, vec2(.376 + .016 * t, .195 + .007 * sin(t)), .012, 1.0, .25, t, 2.8, .69));
    result = fishOver(result, fishPatrol(p, vec2(.684 + .011 * t, .193 + .005 * sin(t)), .008, -1.0, .080, t, 3.0, .57));
    return result;
}

vec4 fishNear(vec2 p,float t){
    return fishOver(fishSmallReef(p, t), fishMainRay(p, t));
}

// Daylight warms exposed limestone. Recesses receive cooler diffuse light,
// with the distant city seen through a longer water path.
vec4 cityLight(vec4 object,vec2 p,float t,float farDepth){
    if(object.a<.0001)return object;
    vec3 c=object.rgb;
    float lightness=dot(c,vec3(.2126,.7152,.0722));
    float exposure=smoothstep(.13,.55,lightness);
    float cone=exp(-sceneSquare((p.x-.50)/.27));
    float sun=cone*(.28+1.18*exposure);
    vec3 ambient=mix(vec3(.78,.86,.93),vec3(1.044,1.000,.965),exposure);
    c=c*ambient*(1.+sun*vec3(.72,.59,.50))+sun*vec3(.035,.020,.014);

    float distant=clamp(.10+.64*(1.-smoothstep(.14,.78,p.y))+.31*farDepth,0.,1.);
    vec3 airlight=waterColumn(p,t)*mix(vec3(.70,.88,1.06),vec3(.84,1.045,1.18),farDepth);
    c=mix(c,airlight,distant*(.34+.21*farDepth));

    // Ripples travel with the incident light and break up on the lit faces.
    if(farDepth<.5){
        float rip=rfCaustic(p*2.4+vec2(.17,.31),t);
        c+=vec3(.050,.061,.065)*rip*exposure*(.26+.74*cone);
    }
    float westShade=1.-smoothstep(.075,.21,p.x);
    c*=1.-.24*westShade*smoothstep(.31,.61,p.y);
    float window=exp(-sceneSquare((p.x-.40)/.16)-sceneSquare((p.y-.40)/.25));
    c+=vec3(.116,.136,.147)*window*(.41+.59*exposure);
    float eastWindow=exp(-sceneSquare((p.x-.82)/.14)-sceneSquare((p.y-.44)/.16));
    c+=vec3(.071,.082,.089)*eastWindow*(.30+.70*exposure);
    return vec4(c,object.a);
}

vec3 midwaterScatter(vec3 color,vec2 p,float t){
    float band=exp(-sceneSquare((p.y-.35)/.23));
    float temple=exp(-pow(abs((p.x-.568)/.15),4.));
    float sun=exp(-sceneSquare((p.x-.46)/.42));
    float shaft=.90+.16*valueNoise(vec2((p.x-.46)/(1.+p.y*.8)*74.,p.y*2.+t*.13));
    float weight=(.17+.11*sun)*band*(1.-.78*temple)*shaft;
    vec3 scatter=mix(vec3(.127,.345,.483),vec3(.37,.60,.677),sun);
    color=mix(color,scatter,weight);
    float channelFill=exp(-sceneSquare((p.x-.181)/.063)-sceneSquare((p.y-.668)/.245));
    color+=vec3(.028,.071,.091)*channelFill*(1.-smoothstep(.26,.57,dot(color,vec3(.213,.715,.072))));

    // Light drops into the near canyon. Keep sunlit paving and warm
    // highlights readable while cooling the ambient faces.
    float canyon=smoothstep(.52,.87,p.y);
    float luma=dot(color,vec3(.2126,.7152,.0722));
    float diffuse=1.-smoothstep(.20,.67,luma);
    vec3 cooler=mix(vec3(luma),color,.82)*vec3(.62,.78,.89);
    color=mix(color,cooler,canyon*diffuse*.47);
    float litStone=smoothstep(.47,.79,luma)*smoothstep(-.13,.03,color.r-color.b);
    return color+vec3(.058,.065,.071)*litStone*canyon*(.20+.80*sun);
}

// A separate layer of tiny oblique swimmers hangs behind the temple.
// Each horizontal cell contributes one animal to a loose depth stratum.
vec3 upperSwimmers(vec3 rgb,vec2 p,float t){
    if(p.y<.083||p.y>.267)return rgb;
    vec2 s=p*vec2(880.,376.);
    for(int layer=0;layer<3;layer++){
        float k=float(layer);
        float drift=(k==1.?-1.:1.)*(4.+1.2*k)*t;
        float pitch=19.+k*6.;
        float cell=floor((s.x-drift)/pitch);
        float r=valueNoise(vec2(cell*4.7,k*73.8+4.));
        float cx=(cell+.24+.50*r)*pitch+drift;
        float cy=44.+k*12.+(r-.5)*18.+6.*sin(cell*.62+k+t*.24);
        vec2 q=s-vec2(cx,cy);
        if(abs(q.x)>5.||abs(q.y)>4.)continue;
        q.x*=k==1.?-1.:1.;
        q.y-=q.x*(.24-.55*r);
        float size=1.5+1.7*r;
        float d=length(q/vec2(size,.29+.38*r));
        float a=1.-smoothstep(.57,1.28,d);
        float tail=(1.-smoothstep(.35,.78,abs(q.y+.20*sin(t*6.+cell))))*
                   (1.-smoothstep(.25,1.,abs(q.x+size+.23)));
        vec3 fish=mix(vec3(.11,.31,.39),vec3(.55,.69,.69),(1.-smoothstep(-.53,.0,q.y)));
        rgb=mix(rgb,fish,max(a,tail*.57)*(.32+.37*r));
    }
    return rgb;
}
vec3 passingTurtle(vec3 rgb,vec2 p,float t){
    vec2 s=p*vec2(880.,376.);
    vec2 q=s-vec2(42.-18.7*t,171.5-.85*t+.55*sin(2.*t));
    if(abs(q.x)>18.||abs(q.y)>10.)return rgb;
    q.y-=q.x*.095;
    float stroke=sin(t*3.6+.75);
    float carapace=length((q-vec2(.5,-.6))/vec2(10.,3.0));
    float shell=1.-smoothstep(.91,1.07,carapace);
    float n=valueNoise(q*.95);
    vec3 c=mix(vec3(.18,.24,.24),vec3(.55,.57,.48),clamp(.53-.20*q.y+.2*(n-.5),0.,1.));
    vec2 fin=q-vec2(-4.3,1.0);
    fin.x+=fin.y*(.80+.36*stroke);
    float limb=1.-smoothstep(.82,1.16,length((fin-vec2(0.,2.4+stroke))/vec2(1.05,3.4+stroke)));
    vec2 head=q-vec2(-10.3,-.3);
    float neck=1.-smoothstep(.8,1.08,length(head/vec2(3.35,1.38)));
    rgb=mix(rgb,vec3(.36,.40,.36),max(limb,neck)*.88);
    return mix(rgb,c,shell*.94);
}

// This composition shares the rebuilt architecture but keeps it in view.
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

vec3 detailShot(vec2 p, float seconds) {
    float phase = detailPhase(seconds);
    // These existing materials take a bounded phase input for light only.
    float lightTime = 2.35 * sin(phase + p.x * 2.6) + .71 * cos(2.0 * phase - p.y * 2.8);
    vec3 rgb = waterColumn(p, seconds);
    rgb = detailOver(rgb, reefBackdrop(p, seconds));
    rgb = detailSwimmers(rgb, p, seconds, true);
    rgb = detailOver(rgb, cityLight(cityFar(p, 0.0), p, seconds, 1.0));
    rgb = channelLight(p, lightTime, footings(p, rgb, 0.0));
    rgb = detailOver(rgb, plaza(p, lightTime));
    rgb = detailOver(rgb, cityLight(cityNear(p, 0.0), p, seconds, 0.0));
    rgb = midwaterScatter(rgb, p, lightTime);
    rgb = detailOver(rgb, brokenRotunda(p, 0.0));
    rgb = detailOver(rgb, brokenCauseway(p, 0.0));
    rgb = detailOver(rgb, domeColonies(p, lightTime));
    rgb = reefGardens(p, rgb, 0.0);
    rgb = detailOver(rgb, reef(p, seconds));
    rgb = detailJellies(rgb, p, seconds);
    rgb = detailVents(rgb, p, seconds);
    rgb = detailSwimmers(rgb, p, seconds, false);
    rgb = detailMotes(rgb, p, seconds);
#if DEBUG_MODE == 1
    return waterColumn(p, seconds);
#elif DEBUG_MODE == 2
    return city(p, 0.0).rgb * city(p, 0.0).a;
#elif DEBUG_MODE == 4
    return vec3(reef(p, seconds).a, reefBackdrop(p, seconds).a, 0.0);
#endif
    return clamp(rgb, 0.0, 1.0);
}

// The main temple is centered at x=.59 in the city drawing.
#define WILDLIFE_LOOP_FRAMES 1440
const float WILDLIFE_LOOP_SECONDS = float(WILDLIFE_LOOP_FRAMES) / 24.0;

vec3 wildlifeSchool(vec3 rgb, vec2 p, float phase) {
    if (p.x < .30 || p.x > .88 || p.y < .18 || p.y > .54) return rgb;
    float templeAlpha = -1.0;
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
            if (templeAlpha < 0.) {
                vec4 temple = vec4(0.);
                ctMainTemple(temple, p * vec2(1760., 754.));
                templeAlpha = temple.a;
            }
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
    vec3 rgb = detailShot(p, waterTime);
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

vec3 shotFiltered(vec2 p, float seconds, vec2 pixelSize) {
    float t = mod(FREEZE_TIME >= 0.0 ? FREEZE_TIME : seconds + START_TIME, WILDLIFE_LOOP_SECONDS);
#if AA == 1
    return wildlifeShot(p, t);
#else
    vec3 sum = vec3(0.0);
    for (int y = 0; y < AA; ++y) {
        for (int x = 0; x < AA; ++x) {
            vec2 offset = (vec2(x,y) + .5) / float(AA) - .5;
            sum += pow(wildlifeShot(p + pixelSize * offset, t), vec3(2.2));
        }
    }
    return pow(sum / float(AA * AA), vec3(1.0 / 2.2));
#endif
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 p=fragCoord/iResolution.xy;
    fragColor=vec4(shotFiltered(vec2(p.x,1.0-p.y),iTime,1.0/iResolution.xy),1.0);
}
