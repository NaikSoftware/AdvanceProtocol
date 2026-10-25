"""Mantaflow bake + Cycles render of one VFX preset into per-frame PNGs.

Run: blender -b --factory-startup -P bake_flipbook.py -- <preset> <out_dir> [--quick] [--nobake] [frame ...]
Frames land in <out_dir>/<preset>/f_NNN.png (16-bit RGBA). assemble.py turns them into an atlas.
Sizes are real metres (1 BU = 1 m); the camera is orthographic and looks along +Y.
"""
import sys, os, math, bpy

PRESETS = {
    # smoke_puff: a billowing plume segment; assemble.py makes it loop by cross-fading two cycles.
    "smoke_puff": dict(
        dom=(8, 8, 12), res=128, cam_c=(0, 0, 5.2), cam_w=12.0, cell=192, nscale=1.1,
        time_scale=0.3, fps=4, sim_start=1, sim_frames=64, render=(1, 64), kind="smoke",
        flow=dict(type="SMOKE", behavior="GEOMETRY", pos=(0, 0, 3.0), r=2.4, dens=1.6, temp=3.0, vcoord=(0, 0, 0.5), rag=0.5),
        d=dict(alpha=0.05, beta=0.7, vorticity=1.6, dissolve=True, dissolve_speed=110, noise=False, upres=2),
        mat=dict(smoke_col=(0.30, 0.30, 0.30), sigma=1.6, aniso=0.2, sun=1.2, ambient=0.5),
    ),
    # wreck_fire: low flames 1-2 m, black smoke at the tips.
    "wreck_fire": dict(
        dom=(6, 6, 6), res=130, cam_c=(0, 0, 2.4), cam_w=6.4, cell=192, nscale=2.8,
        fps=8, sim_start=1, sim_frames=150, render=(23, 150), kind="fire",
        flow=dict(type="BOTH", behavior="INFLOW", pos=(0, 0, 0.45), r=1.1, dens=0.6, temp=1.6, fuel=1.0),
        d=dict(alpha=1.0, beta=2.2, vorticity=1.6, dissolve=True, dissolve_speed=40,
               burn=0.55, flame_smoke=1.6, flame_vort=0.8, noise=False, upres=2),
        mat=dict(smoke_col=(0.06, 0.06, 0.06), sigma=5.0, aniso=0.1, sun=1.0, ambient=0.6, flame_gain=3.2, ramp_gain=0.5),
    ),
    # explosion: one-shot fireball + dark smoke, 15 m class.
    "explosion": dict(
        dom=(20, 20, 20), res=120, cam_c=(0, 0, 9.5), cam_w=20.0, cell=256, nscale=0.55,
        fps=48, sim_start=1, sim_frames=65, render=(2, 65), kind="fire", time_scale=1.6,
        flow=dict(type="BOTH", behavior="GEOMETRY", pos=(0, 0, 9.0), r=3.4, dens=2.5, temp=2.0, fuel=1.0, vnorm=10.0, rag=0.45),
        d=dict(alpha=0.5, beta=2.5, vorticity=1.2, dissolve=False, bottom=False,
               burn=0.3, flame_smoke=3.0, flame_vort=1.0, noise=False, upres=1),
        mat=dict(smoke_col=(0.38, 0.38, 0.38), sigma=3.0, aniso=0.2, sun=1.0, ambient=0.8, flame_gain=4.0, ramp_gain=0.5),
    ),
    # dirt_burst: brown earth and dust, no fire.
    "dirt_burst": dict(
        dom=(16, 16, 16), res=120, cam_c=(0, 0, 5.0), cam_w=16.0, cell=256, nscale=0.8,
        fps=40, sim_start=1, sim_frames=64, render=(1, 64), kind="smoke", time_scale=1.5,
        flow=dict(type="SMOKE", behavior="GEOMETRY", pos=(0, 0, 0.4), r=2.8, dens=2.0, temp=1.0, vnorm=12.0, rag=0.4),
        d=dict(alpha=1.5, beta=1.2, vorticity=0.8, dissolve=False, noise=False, upres=1, bottom=True),
        mat=dict(smoke_col=(0.38, 0.32, 0.26), sigma=2.2, aniso=0.0, sun=1.0, ambient=0.9),
    ),
    # flash: muzzle/impact flash, 16 frames, white-hot core.
    "flash": dict(
        dom=(8, 8, 8), res=128, cam_c=(0, 0, 4.0), cam_w=8.0, cell=256, nscale=1.4,
        fps=60, sim_start=1, sim_frames=17, render=(2, 17), kind="fire", time_scale=3.0,
        flow=dict(type="BOTH", behavior="GEOMETRY", pos=(0, 0, 4.0), r=1.1, dens=1.5, temp=2.0, fuel=1.0, vnorm=5.0, rag=0.45),
        d=dict(alpha=0.5, beta=2.5, vorticity=1.2, dissolve=False, bottom=False, burn=0.3, flame_smoke=3.0, flame_vort=1.0,
               noise=False, upres=1),
        mat=dict(smoke_col=(0.38, 0.38, 0.38), sigma=3.0, aniso=0.2, sun=1.0, ambient=0.8, flame_gain=4.0, ramp_gain=0.5),
    ),
}


def lin(c):  # sRGB 0..1 -> linear
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def hexc(h):
    return lin(tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)))


RES = 0


def build(P, cache, quick):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.fps = P["fps"]
    sc.frame_start, sc.frame_end = P["sim_start"], P["sim_start"] + P["sim_frames"] - 1
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, P["dom"][2] / 2))
    dom = bpy.context.object
    dom.name = "Domain"
    dom.scale = P["dom"]
    m = dom.modifiers.new("Fluid", "FLUID")
    m.fluid_type = "DOMAIN"
    s = m.domain_settings
    s.domain_type = "GAS"
    s.resolution_max = RES or (48 if quick else P["res"])
    s.cache_directory = cache
    s.cache_type = "ALL"
    s.cache_frame_start, s.cache_frame_end = sc.frame_start, sc.frame_end
    s.use_adaptive_timesteps = True
    s.time_scale = P.get("time_scale", 1.0)
    D = P["d"]
    s.alpha, s.beta, s.vorticity = D["alpha"], D["beta"], D["vorticity"]
    s.use_dissolve_smoke = D["dissolve"]
    if D["dissolve"]:
        s.dissolve_speed = D["dissolve_speed"]
        s.use_dissolve_smoke_log = True
    if "burn" in D:
        s.burning_rate, s.flame_smoke, s.flame_vorticity = D["burn"], D["flame_smoke"], D["flame_vort"]
        s.flame_smoke_color = (0.0, 0.0, 0.0)
    s.use_noise = D["noise"] and not quick
    if s.use_noise:
        s.noise_scale = D["upres"]
    for side in ("front", "back", "left", "right", "top"):
        setattr(s, "use_collision_border_" + side, False)
    s.use_collision_border_bottom = D.get("bottom", True)
    F = P["flow"]
    bpy.ops.mesh.primitive_uv_sphere_add(radius=F["r"], location=F["pos"], segments=24, ring_count=16)
    em = bpy.context.object
    em.name = "Emitter"
    if F.get("rag"):  # a ragged seed, so the first frames are not a perfect disc
        bpy.ops.object.shade_smooth()
        sub = em.modifiers.new("Sub", "SUBSURF")
        sub.levels = 2
        tex = bpy.data.textures.new("rag", "CLOUDS")
        tex.noise_scale = F["r"] * 0.6
        tex.noise_depth = 3
        dm = em.modifiers.new("Disp", "DISPLACE")
        dm.texture, dm.strength, dm.mid_level = tex, F["r"] * F["rag"], 0.5
    fm = em.modifiers.new("Fluid", "FLUID")
    fm.fluid_type = "FLOW"
    f = fm.flow_settings
    f.flow_type = F["type"]
    f.flow_behavior = F["behavior"]
    f.flow_source = "MESH"
    f.surface_distance = 0.5
    f.volume_density = 1.0
    f.density = F["dens"]
    f.temperature = F["temp"]
    if F["type"] in ("FIRE", "BOTH"):
        f.fuel_amount = F["fuel"]
    if F.get("vcoord"):
        f.use_initial_velocity = True
        f.velocity_coord = F["vcoord"]
    if F.get("vnorm"):
        f.use_initial_velocity = True
        f.velocity_normal = F["vnorm"]
    em.hide_render = True
    # --- render setup
    M = P["mat"]
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16 if quick else 160
    sc.cycles.use_denoising = True
    sc.cycles.sample_clamp_indirect = 1.0  # volume fireflies
    sc.cycles.max_bounces = 6
    sc.cycles.volume_bounces = 2
    sc.cycles.volume_step_rate = 0.5
    try:
        pref = bpy.context.preferences.addons["cycles"].preferences
        pref.compute_device_type = "OPTIX"
        pref.get_devices()
        for d_ in pref.devices:
            d_.use = d_.type != "CPU"
        sc.cycles.device = "GPU"
    except Exception as e:
        print("GPU unavailable:", e)
    c = P["cell"] // (2 if quick else 1)
    sc.render.resolution_x = sc.render.resolution_y = c
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "16"
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = P["cam_w"]
    cam.location = (P["cam_c"][0], -30, P["cam_c"][2])
    cam.rotation_euler = (math.pi / 2, 0, 0)
    sc.camera = cam
    w = bpy.data.worlds.new("W")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.82, 0.86, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = M["ambient"]
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.data.energy = M["sun"] * 4.0
    sun.data.angle = math.radians(25)
    sun.rotation_euler = (math.radians(55), 0, math.radians(35))
    # --- volume material
    mat = bpy.data.materials.new("Vol")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dens = nt.nodes.new("ShaderNodeAttribute")
    dens.attribute_name = "density"
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (*lin(M["smoke_col"]), 1)
    pv.inputs["Anisotropy"].default_value = M["aniso"]
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = M["sigma"]
    thr = nt.nodes.new("ShaderNodeMath")
    thr.operation, thr.use_clamp = "SUBTRACT", True
    thr.inputs[1].default_value = 0.06
    nt.links.new(dens.outputs["Fac"], thr.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.noise_dimensions = "4D"
    nz.inputs["W"].default_value = P["seed"] if "seed" in P else 0.0
    nz.inputs["Scale"].default_value = P["nscale"]
    nz.inputs["Detail"].default_value = 7.0
    nz.inputs["Roughness"].default_value = 0.6
    nz.inputs["Distortion"].default_value = 0.5
    nm = nt.nodes.new("ShaderNodeMapRange")
    nm.inputs["From Min"].default_value, nm.inputs["From Max"].default_value = 0.40, 0.62
    nm.inputs["To Min"].default_value, nm.inputs["To Max"].default_value = P.get("nlo", 0.0), P.get("nhi", 1.7)
    nm.clamp = True
    mp = nt.nodes.new("ShaderNodeMapping")  # Object coords are in units of the (scaled) domain cube; make them metres
    mp.inputs["Scale"].default_value = P["dom"]
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], nz.inputs["Vector"])
    nt.links.new(nz.outputs["Fac"], nm.inputs["Value"])
    dn = nt.nodes.new("ShaderNodeMath")
    dn.operation = "MULTIPLY"
    nt.links.new(thr.outputs[0], dn.inputs[0])
    nt.links.new(nm.outputs["Result"], dn.inputs[1])
    nt.links.new(dn.outputs[0], mul.inputs[0])
    nt.links.new(mul.outputs[0], pv.inputs["Density"])
    last = pv.outputs[0]
    if P["kind"] == "fire":
        fl = nt.nodes.new("ShaderNodeAttribute")
        fl.attribute_name = "flame"
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        cr = ramp.color_ramp
        cr.elements[0].position, cr.elements[0].color = 0.0, (*hexc("#4A1204"), 1)
        e1 = cr.elements.new(0.35)
        e1.color = (*hexc("#E0702A"), 1)
        cr.elements[2].position, cr.elements[2].color = 1.0, (*hexc("#FFD9A0"), 1)
        rs = nt.nodes.new("ShaderNodeMath")
        rs.operation = "MULTIPLY"
        rs.inputs[1].default_value = P["mat"].get("ramp_gain", 0.4)
        fl2 = nt.nodes.new("ShaderNodeMath")  # flame x noise: cooler, redder patches inside the hot mass
        fl2.operation = "MULTIPLY"
        nt.links.new(fl.outputs["Fac"], fl2.inputs[0])
        nt.links.new(nm.outputs["Result"], fl2.inputs[1])
        nt.links.new(fl2.outputs[0], rs.inputs[0])
        nt.links.new(rs.outputs[0], ramp.inputs["Fac"])
        em_ = nt.nodes.new("ShaderNodeEmission")
        gm = nt.nodes.new("ShaderNodeMath")
        gm.operation = "MULTIPLY"
        gm.inputs[1].default_value = M["flame_gain"]
        fn_ = nt.nodes.new("ShaderNodeMath")
        fn_.operation = "MULTIPLY"
        nt.links.new(fl.outputs["Fac"], fn_.inputs[0])
        nt.links.new(nm.outputs["Result"], fn_.inputs[1])
        nt.links.new(fn_.outputs[0], gm.inputs[0])
        nt.links.new(ramp.outputs["Color"], em_.inputs["Color"])
        nt.links.new(gm.outputs[0], em_.inputs["Strength"])
        ab = nt.nodes.new("ShaderNodeVolumeAbsorption")
        am = nt.nodes.new("ShaderNodeMath")
        am.operation = "MULTIPLY"
        am.inputs[1].default_value = 6.0
        nt.links.new(fn_.outputs[0], am.inputs[0])
        nt.links.new(am.outputs[0], ab.inputs["Density"])
        ab.inputs["Color"].default_value = (1, 1, 1, 1)
        a1 = nt.nodes.new("ShaderNodeAddShader")
        a2 = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(pv.outputs[0], a1.inputs[0])
        nt.links.new(em_.outputs[0], a1.inputs[1])
        nt.links.new(a1.outputs[0], a2.inputs[0])
        nt.links.new(ab.outputs[0], a2.inputs[1])
        last = a2.outputs[0]
    nt.links.new(last, out.inputs["Volume"])
    dom.data.materials.append(mat)
    return dom


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name, outdir = argv[0], argv[1]
    global RES
    quick = "--quick" in argv
    RES = next((int(a[6:]) for a in argv if a.startswith("--res=")), 0)
    P = PRESETS[name]
    cache = os.path.join(outdir, name, "cache")
    os.makedirs(cache, exist_ok=True)
    dom = build(P, cache, quick)
    sc = bpy.context.scene
    bpy.context.view_layer.objects.active = dom
    for o in bpy.data.objects:
        o.select_set(o is dom)
    if "--nobake" not in argv:
        bpy.ops.fluid.bake_data()
        if dom.modifiers["Fluid"].domain_settings.use_noise:
            bpy.ops.fluid.bake_noise()
    r0, r1 = P["render"]
    only = [int(a) for a in argv if a.isdigit()]  # frame subset: tuning run, cache kept
    for fr in range(r0, r1 + 1):
        if only and fr not in only:
            continue
        sc.frame_set(fr)
        sc.render.filepath = os.path.join(outdir, name, "f_%03d.png" % fr)
        bpy.ops.render.render(write_still=True)
        print("rendered", fr)
    if "--keepcache" not in argv and not only:
        import shutil
        shutil.rmtree(cache, ignore_errors=True)


main()
