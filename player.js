const stage = document.querySelector('main');
const canvas = document.querySelector('canvas');
const error = document.querySelector('[role=alert]');
function fullscreen() {
    if (document.fullscreenElement || document.webkitFullscreenElement) return;
    const request = stage.requestFullscreen || stage.webkitRequestFullscreen;
    // Embedded browsers can deny native fullscreen. The scene still fills the viewport.
    if (request) Promise.resolve(request.call(stage)).catch(() => {});
}
stage.addEventListener('click', fullscreen);
stage.addEventListener('keydown', event => {
    if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        fullscreen();
    }
});

async function load() {
    const mask = new Image();
    mask.src = 'temple-mask.png';
    const scenery = document.querySelector('img');
    const source = fetch('live.frag').then(response => {
        if (!response.ok) throw Error('Could not load the shader.');
        return response.text();
    });
    const gl = canvas.getContext('webgl2', {alpha:false, antialias:false, depth:false, stencil:false});
    if (!gl) throw Error('This scene needs WebGL 2.');
    const program = gl.createProgram();
    const shaders = [];
    function attach(type, code) {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, code);
        gl.compileShader(shader);
        gl.attachShader(program, shader);
        shaders.push(shader);
    }
    attach(gl.VERTEX_SHADER, `#version 300 es
out vec2 uv;
void main(){
    vec2 pos = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    uv = vec2(pos.x,1.-pos.y);
    gl_Position = vec4(2.*pos-1.,0.,1.);
}`);
    attach(gl.FRAGMENT_SHADER, await source);
    gl.linkProgram(program);
    await Promise.all([scenery.decode(), mask.decode()]);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
        throw Error(shaders.map(s => gl.getShaderInfoLog(s)).join(' ') + gl.getProgramInfoLog(program));
    gl.useProgram(program);
    for (const [unit, name, image] of [[0, 'scenery', scenery], [1, 'templeMask', mask]]) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, gl.createTexture());
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
        for (const axis of [gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T])
            gl.texParameteri(gl.TEXTURE_2D, axis, gl.CLAMP_TO_EDGE);
        for (const filter of [gl.TEXTURE_MIN_FILTER, gl.TEXTURE_MAG_FILTER])
            gl.texParameteri(gl.TEXTURE_2D, filter, gl.LINEAR);
        gl.uniform1i(gl.getUniformLocation(program, name), unit);
    }
    const time = gl.getUniformLocation(program,'seconds');
    const start = performance.now();
    let lastFrame = -1, animation;
    function animate(now) {
        const frame = Math.floor((now - start) * .024) % 1440;
        if (frame !== lastFrame) {
            gl.uniform1f(time, frame / 24);
            gl.drawArrays(gl.TRIANGLES, 0, 3);
            lastFrame = frame;
        }
        animation = requestAnimationFrame(animate);
    }
    canvas.addEventListener('webglcontextlost', event => {
        event.preventDefault();
        cancelAnimationFrame(animation);
        canvas.hidden = true;
    });
    canvas.addEventListener('webglcontextrestored', () => location.reload());
    animate(start);
    canvas.hidden = false;
}
load().catch(err => { canvas.hidden = true; error.textContent = err.message; });
