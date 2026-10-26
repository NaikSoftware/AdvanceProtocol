#!/bin/bash
# Renders every atlas source frame set from the free JangaFX VDB packs (CC0), then packs the atlases.
# usage: VDB=<dir holding the unpacked packs> WORK=<scratch dir, not /tmp> OUT=<atlas dir> render_all.sh
# lift= raises the volume (m) over the first frames, so a ground burst rises; heat= makes the first frames the
# hottest; each blender run prints an ANCHOR line (blast point in the cell). fade= softens the sim volume towards its box (the sims end in a straight cut).
set -e -o pipefail
H="$(cd "$(dirname "$0")" && pwd)"
B="${BLENDER:-blender}"
G="$VDB/ground/ground_explosion/ground_explosion_VDB"
R() { "$B" -b --factory-startup --python-exit-code 1 -P "$H/vdb_flipbook.py" -- "$@"; }
R "$G" "$WORK" explosion rotx=90 height=24 kind=fire cell=256 samples=64 frames=16:142:2 pitch=45 ground=1 athr=0.25 ramp=0.52 gain=4.5 fabs=10 dens=7 col=0.3,0.3,0.3 margin=0.04 fade=0.0001 heat=1 tau=7 lift=12 l0=4 l1=44
R "$G" "$WORK" smoke_puff rotx=90 height=24 kind=smoke cell=192 samples=64 frames=66:129:1 pitch=45 ground=1 dens=5 col=0.32,0.32,0.32 margin=0.06 fade=0.12
R "$G" "$WORK" dirt_burst rotx=90 height=14 kind=smoke cell=256 samples=64 frames=20:146:2 pitch=45 ground=1 athr=0.25 dens=6 col=0.36,0.28,0.2 margin=0.04 fade=0.0001 lift=8 l0=4 l1=44
R "$G" "$WORK" flash rotx=90 height=8 kind=fire cell=192 samples=64 frames=12:42:2 pitch=45 ground=1 ramp=1.0 gain=9 fabs=10 dens=4 col=0.3,0.3,0.3 margin=0.3 fade=0.0001 heat=1 tau=4
python3 "$H/assemble.py" "$WORK" "$OUT" all
