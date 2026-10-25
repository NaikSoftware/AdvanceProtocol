#!/bin/bash
# Renders every atlas source frame set from the free JangaFX VDB packs (CC0), then packs the atlases.
# usage: VDB=<dir holding the unpacked packs> WORK=<scratch dir, not /tmp> OUT=<atlas dir> render_all.sh
# fade= softens the sim volume towards its box (the sims end in a straight cut); bed= adds the glowing
# surface the wreck fire stands on.
set -e
H="$(cd "$(dirname "$0")" && pwd)"
B="${BLENDER:-blender}"
G="$VDB/ground/ground_explosion/ground_explosion_VDB"
F="$VDB/campfire/smallCampfire/smallCampfireVDB"
R() { "$B" -b --factory-startup -P "$H/vdb_flipbook.py" -- "$@"; }
R "$G" "$WORK" explosion rotx=90 height=24 kind=fire cell=192 samples=64 frames=6:132:2 pitch=45 ground=1 ramp=0.52 gain=4.5 fabs=10 dens=7 col=0.3,0.3,0.3 margin=0.06 fade=0.22
R "$G" "$WORK" smoke_puff rotx=90 height=24 kind=smoke cell=192 samples=64 frames=66:129:1 pitch=45 ground=1 dens=5 col=0.32,0.32,0.32 margin=0.06 fade=0.12
R "$G" "$WORK" dirt_burst rotx=90 height=14 kind=smoke cell=192 samples=64 frames=4:130:2 pitch=45 ground=1 dens=6 col=0.36,0.28,0.2 margin=0.06 fade=0.12
R "$G" "$WORK" flash rotx=90 height=8 kind=fire cell=192 samples=64 frames=4:34:2 pitch=45 ground=1 ramp=1.0 gain=9 fabs=10 dens=4 col=0.3,0.3,0.3 margin=0.12 fade=0.12
R "$F" "$WORK" wreck_fire rotx=90 height=1.7 vstretch=3.6 kind=fire cell=256 cellw=128 samples=48 frames=0:192:1.5 pitch=45 ground=1 athr=0.3 ramp=1.7 gain=8 fabs=40 dens=40 col=0.08,0.08,0.08 margin=0.6 fit=typ
python3 "$H/assemble.py" "$WORK" "$OUT" all
