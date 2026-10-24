# Battlefield props — reference and brief

What the static 3D props on the board are, how big they are in metres and on screen, which can be
shipped from CC0 sources, and how the rest are built: **Blender** for precise or procedural geometry,
**Tripo** for organic or irregular shapes. Setting fixed by [art-direction](../art-direction.md):
the 2030s, contemporary Eastern-European countryside. **Nothing medieval or old-world.**
The season and sky are per map: River is late autumn, overcast and wet; Crossroads is late summer
under a strong sun; Ridge is a clear early autumn. Deciduous trees therefore come in three
seasonal variants (`_late`, `_summer`, `_early`); pine is shared. Sizes and colours below are
written for River's late autumn unless a line says otherwise. No stone-arch bridges, no slate-and-fieldstone cottages.

Contact sheet: `art-refs/props/props_sheet.jpg` (gitignored, local only). Ids below are the labels
on that sheet.

## Camera facts this brief is sized from

1 tile = 8 m. Ground resolution is 7 cm/px at the closest zoom and 22 cm/px at the farthest, at pitch 38–55°.

| real size | px at 7 cm/px | px at 22 cm/px | what it means for a prop |
| --- | --- | --- | --- |
| 1 m | 14 | 4.5 | |
| wire, 1–3 cm | 0.2–0.4 | < 0.15 | **never geometry**: a screen-space line or nothing |
| insulator, 0.15–0.25 m | 2–4 | 1 | a pale dot on the crossarm, nothing more |
| roof corrugation pitch, 5–15 cm | 1–2 | < 1 | invisible. Show only sheet edges (~1.1 m) and the ridge |
| satellite dish, 0.6–0.9 m | 9–13 | 3–4 | a bright disc at close zoom |
| window, 1.2 × 1.4 m | 17 × 20 | 5 × 6 | a dark rectangle with a white PVC frame |
| hay bale, Ø 1.2–1.5 m | 17–21 | 5–7 | silhouette, colour and a contact shadow |
| tank, 7.5 m | 107 | 34 | the "~100 px" legibility rule is for units at close zoom |
| house, 10 m | 143 | 45 | a roof shape plus one or two wall faces |
| pine, 18 m tall | ~180 (foreshortened) | ~60 | crown mass and, at the edge, a trunk |

- A 100 px prop is 7 m at close zoom and 22 m at far zoom. Small props are 5–20 px blobs at far zoom.
  Brief them for **silhouette, value and a baked contact shadow**, never for surface detail.
- At this pitch **roofs are 55–70 % of a building's visible pixels** (k_aerialpl1, k_wd7). Roof colour
  and shape carry the read. Two façades are seen, the backs rarely, the undersides never.
- Texture detail under ~0.3 m is wasted. Single-leaf atlases (ambientCG LeafSet/Foliage) are useless
  here because a leaf is under 1 px. Crown textures must depict **leaf masses 0.5–2 m across**.
- **Tripo does not honour metres.** Every prompt states the real size, but the bounding box is set
  afterwards in Blender or at export (the `3d-modelling` skill: 1 tile = 1.0 unit, ground at y = 0,
  front −Z). Never trust a generated model's scale.

## Shortlist

Reference-only unless marked **ship**. Commons file pages are linked; every image was looked at.

| id | source | licence | used for |
| --- | --- | --- | --- |
| **k_aerialpl1** ★ | [Kadłubiec drone 12](https://commons.wikimedia.org/wiki/File:2022-05_Kad%C5%82ubiec_(12)_Z_lotu_ptaka.jpg), Ralf Lotys | CC BY 4.0 | Village from ~40° pitch: roof shapes, outbuildings, rooftop PV, fences. Closest real match to the game camera |
| **k_wd7** ★ | [Moshchun NGU video, frame 5271](https://commons.wikimedia.org/wiki/File:Battle_of_Moshchun_(NGU_video,_2022-07-19,_frame_5271).jpg) | CC BY 4.0 | Village against a pine wood at ~45°: the two map characters side by side, with war damage among intact houses |
| **k_wd4 / k_wd5** | same video, frames [0840](https://commons.wikimedia.org/wiki/File:Battle_of_Moshchun_(NGU_video,_2022-07-19,_frame_0840).jpg) / [4946](https://commons.wikimedia.org/wiki/File:Battle_of_Moshchun_(NGU_video,_2022-07-19,_frame_4946).jpg) | CC BY 4.0 | Oblique view of damaged plots, roofless houses, gardens |
| **k_wd6** ★ | same video, [frame 5045](https://commons.wikimedia.org/wiki/File:Battle_of_Moshchun_(NGU_video,_2022-07-19,_frame_5045).jpg) | CC BY 4.0 | **Nadir view of shelled houses**, scaled by 0.6 m tyres: the model for every ruin |
| k_wd3 | same video, [frame 0819](https://commons.wikimedia.org/wiki/File:Battle_of_Moshchun_(NGU_video,_2022-07-19,_frame_0819).jpg) | CC BY 4.0 | Ground view: brick chimney stacks and wall stubs left standing |
| k_db11 | [Damaged building in Irpin 8](https://commons.wikimedia.org/wiki/File:A_damaged_building_in_Irpin_8.jpg), Rasal Hague | CC BY-SA 4.0 | Burnt single-storey brick house, roof sheets fallen inside |
| k_db14 | [Damaged building in Irpin p12](https://commons.wikimedia.org/wiki/File:A_damaged_building_in_Irpin_after_the_invasion_of_Russian_troops_p12.jpg), Kisnaak | CC BY-SA 4.0 | Roof blown open, insulation and rafters exposed, brick spill |
| house0 | [Spasov 3](https://commons.wikimedia.org/wiki/File:Spasov,_Rovno_oblast,_Ukraine_3.jpg), Liilia Moroz | CC BY-SA 4.0 | Brick-faced single-storey house, grey corrugated roof, decorative concrete fence |
| house3 | [Hubychi 06](https://commons.wikimedia.org/wiki/File:%D0%93%D1%83%D0%B1%D0%B8%D1%87%D1%96_%D0%A5%D0%90%D0%A2%D0%98_06_%D0%B4%D0%B5%D1%80%D0%B5%D0%B2%D1%8F%D0%BD%D0%B0_%D1%85%D0%B0%D1%82%D0%B0_%D1%96%D0%B7_%D1%82%D0%B0%D1%80%D1%96%D0%BB%D0%BA%D0%BE%D1%8E.jpg), Nickispeaki | CC BY-SA 4.0 | Hip-roofed house with satellite dish behind a corrugated-sheet fence |
| house5 | [Grabivka 01](https://commons.wikimedia.org/wiki/File:Grabivka,_Kulykivka_Raion_01_%D0%A5%D0%B0%D1%82%D0%B0_%D1%96%D0%B7_%D0%B7%D0%B0%D0%B1%D0%BE%D1%80%D0%BE%D0%BC.jpg), Nickispeaki | CC BY-SA 4.0 | Plastered house with a light-ochre corrugated roof and a painted profiled-sheet fence |
| k_pole8 | [Apartment in Mena](https://commons.wikimedia.org/wiki/File:Apartment_in_Mena,_Ukraine;_08.08.19.jpg), VKras | CC BY-SA 4.0 | Two-storey brick apartment block with a wooden pole on a concrete stub |
| hangar4 | [Staszów barn](https://commons.wikimedia.org/wiki/File:Stasz%C3%B3w_ul_Armii_Krajowej_stodo%C5%82a.jpg), A. Kwiecień | CC BY-SA 3.0 | Farm barn: grey boards over a stone-and-brick base, grey roof |
| k_bales7 | [Bukupe 2015 (02)](https://commons.wikimedia.org/wiki/File:Bukupe,_2015_(02).jpg), Draceane | CC BY-SA 4.0 | White silicate-brick shed with a dark roof; wrapped bale for scale |
| k_pylon4 / k_pylon6 ★ | [Electricity pylon File 001](https://commons.wikimedia.org/wiki/File:Electricity_pylon_File_001.jpg) / [008](https://commons.wikimedia.org/wiki/File:Electricity_pylon_File_008.jpg), Novoklimov | **CC0** | **Concrete** distribution pole with a steel crossarm and three pin insulators: the dominant rural pole |
| k_pylon9 | [Electricity pylon in Ukraine 03](https://commons.wikimedia.org/wiki/File:Electricity_pylon_in_Ukraine_03.jpg), Novoklimov | CC BY 4.0 | Steel lattice tower with two crossarms and suspension strings |
| k_pole3 / k_pole7 | [panoramio 49](https://commons.wikimedia.org/wiki/File:13.04.2015_-_panoramio_(49).jpg), edykbo / [panoramio 1](https://commons.wikimedia.org/wiki/File:23_%D0%BC%D0%B0%D1%8F_2010_-_panoramio_(1).jpg) | CC BY 3.0 | Village street: concrete poles, a pole-mounted transformer, grey roofs |
| k_pole6 | [panoramio 394](https://commons.wikimedia.org/wiki/File:2014_-_panoramio_(394).jpg) | CC BY 3.0 | Roadside fuel-station canopy at village scale (the brand colours are **not** to be copied) |
| k_po21 / k_po25 | [Paldiski 2023 3](https://commons.wikimedia.org/wiki/File:Paldiski_Nuclear_Submarine_Training_Center_2023_3.jpg), VargaA / [Lagodekhi barracks](https://commons.wikimedia.org/wiki/File:Wikiwyprawa_2015_dawne_koszary_w_lagodeki.jpg) | CC BY-SA 4.0 / 3.0 | Panelled concrete yard fence (PO-2 type) |
| k_wt0 / k_wt1 | [panoramio xxttxx](https://commons.wikimedia.org/wiki/File:-_panoramio_-_xxttxx.jpg) / [Pidvidnyi vodoprovid 11](https://commons.wikimedia.org/wiki/File:11_%D0%9F%D1%96%D0%B4%D0%B2%D1%96%D0%B4%D0%BD%D0%B8%D0%B9_%D0%B2%D0%BE%D0%B4%D0%BE%D0%BF%D1%80%D0%BE%D0%B2%D1%96%D0%B4_after_1.jpg) | CC BY 3.0 / CC BY-SA 4.0 | Brick tower; slim steel tank-on-pipe tower. Some towers in that category are painted in national colours: **do not copy** |
| silo2 | [Jabłowo silo](https://commons.wikimedia.org/wiki/File:Jab%C5%82owo,_silo.JPG) | CC BY 3.0 | Concrete silo battery beside a village road |
| k_bales3 / k_bales9 | [Belasiana](https://commons.wikimedia.org/wiki/File:Belasiana.jpg), Merc777 / [Chatham Hayfield](https://commons.wikimedia.org/wiki/File:Chatham_Hayfield_0_-_panoramio.jpg) | CC BY-SA 4.0 / 3.0 | Round hay bales: size, spacing, weathered colour |
| beam1 / beam4 | [Qew Brücke 46](https://commons.wikimedia.org/wiki/File:Qew_bruecke_nf_beton_kaputt_46_von_46.jpg), Achim Hering / [Wiesentbrücke Hollfeld](https://commons.wikimedia.org/wiki/File:Wiesentbruecke_in_Hollfeld_01.JPG) | CC BY 3.0 / PD | Flat concrete deck on piers; a small town beam bridge |
| **dbridge0 / dbridge1 / dbridge5** ★ | [Irpin R-30 bridge 1](https://commons.wikimedia.org/wiki/File:Destroyed_bridge_over_the_Irpin_River_on_the_R-30_highway_-_2022-04-04_-_photo1649078187.jpg) / [2](https://commons.wikimedia.org/wiki/File:Destroyed_bridge_over_the_Irpin_River_on_the_R-30_highway_-_2022-04-04_-_photo1649077871.jpg), Press Office of the President of Ukraine / [Narodychi](https://commons.wikimedia.org/wiki/File:Destroyed_Bridge_in_Narodychi.jpg) | CC BY 4.0 | **Destroyed beam bridge**: span dropped into the river from a pier, broken deck slabs, rebar, railings hanging |
| **bailey2** ★ / bailey0 / k_bailey10 | [Bailey Bridge La Reunion](https://commons.wikimedia.org/wiki/File:Bailey_Bridge_La_Reunion.jpg), MathiasEllpunkt / [Marcq](https://commons.wikimedia.org/wiki/File:Marcq_pont_bailey.jpg), Velvet / [Coppename](https://commons.wikimedia.org/wiki/File:Bailey-Coppename_River.jpg) | CC BY-SA 4.0 / CC BY-SA 4.0 / PD | Panel-truss bridge on concrete abutments; timber deck from above |
| k_bailey1 | [Truck broke the bridge](https://commons.wikimedia.org/wiki/File:A_truck_carrying_a_pile_of_rocks_broke_down_the_bridge_at_my_village.jpg), Caps Carter | CC BY-SA 4.0 | **Collapsed panel bridge**: one end dropped, trusses buckled |
| **pontoon1** ★ / k_pont5 | [Sasbach pontoon bridge](https://commons.wikimedia.org/wiki/File:Sasbach_am_Kaiserstuhl_military_pontoon_bridge_HBdia02256.jpg) / [Khorramshahr 080](https://commons.wikimedia.org/wiki/File:Liberation_of_Khorramshahr_(Operation_Beit_al-Moqaddas)_(080).jpg) | CC BY 4.0 / PD | Pontoon bridge seen from above, bays separated; ribbon deck with a truck for scale |
| k_forest8 / k_forest9 ★ | [Road crossing the taiga](https://commons.wikimedia.org/wiki/File:Aerial_view_of_a_road_crossing_the_ta%C3%AFga.jpg) / [Taiga](https://commons.wikimedia.org/wiki/File:Aerial_view_of_ta%C3%AFga.jpg), Gabriel Picard | CC BY-SA 4.0 | **Nadir conifer canopy with a road for scale**: crown size and count per tile |
| k_forest1 / k_forest5 | [West of Litovel 03](https://commons.wikimedia.org/wiki/File:Aerial_photograph_west_of_Litovel_03.jpg) / [Vrapač](https://commons.wikimedia.org/wiki/File:Aerial_view_of_Vrapa%C4%8D.jpg), Pan Domaci | **CC0** | Broadleaf forest edges seen from an oblique angle |
| **k_forest11** ★ | [Bakonybél, Kálvária](https://commons.wikimedia.org/wiki/File:Bakonyb%C3%A9l,_K%C3%A1lv%C3%A1ria_l%C3%A9gi_fot%C3%B3n.jpg), Civertan | CC BY-SA 4.0 | **Bare late-autumn broadleaf wood from above**: the ground shows through everywhere |
| k_forest15 | [Csatka-Szentkút 6](https://commons.wikimedia.org/wiki/File:Csatka-Szentk%C3%BAt_l%C3%A9gi_felv%C3%A9telen_6.jpg), Civertan | CC BY-SA 4.0 | Autumn mixed broadleaf at an oblique angle, edge trunks visible |
| birch3, pine5, oak4, oak3, boulder0; bare0 | geograph.org.uk via Commons: [birch3](https://commons.wikimedia.org/wiki/File:Silver_Birch_in_autumn_-_geograph.org.uk_-_6649632.jpg), [pine5](https://commons.wikimedia.org/wiki/File:Clump_of_Scots_pine_north_of_Starpole_Pond,_New_Forest_-_geograph.org.uk_-_142519.jpg), [oak4](https://commons.wikimedia.org/wiki/File:Solitary_Oak_tree_-_geograph.org.uk_-_3202874.jpg), [oak3](https://commons.wikimedia.org/wiki/File:Solitary_oak_tree_-_geograph.org.uk_-_5284667.jpg), [boulder0](https://commons.wikimedia.org/wiki/File:Glacial_erratic_boulders_-_geograph.org.uk_-_3618306.jpg); [bare0](https://commons.wikimedia.org/wiki/File:Poggersdorf_Linsenberg_Landschaft_mit_Birnb%C3%A4umen_11012019_5938.jpg), J. Jaritz. Others (pine2, bare5, birch2): `art-refs/props/c/<tag>/meta.tsv` | CC BY-SA 2.0; bare0 CC BY-SA 4.0 | Single-tree silhouettes, overcast colour, a field of glacial boulders |
| warno18 | WARNO, [Steam](https://store.steampowered.com/app/1611600) | © Eugen, reference only | Silo battery next to tanks: relative scale in a realistic RTS |
| warno24 | same | © reference only | Broadleaf canopy from an oblique RTS camera |
| mow3 | Men of War II, [Steam](https://store.steampowered.com/app/1128860) | © reference only | How a game ruin reads from above. Its WWII half-timbered houses are **off-setting**; use only the rubble spread |

**Rejected on sight:** Commons "ruin" and "panel building" searches (castles, English manors, churches);
urban high-rise war damage (k_db2–k_db10, ruin grid: wrong building type); the Bervytsia
frames (k_wd8–k_wd15: police tape, uniforms, identifiable wrecks); k_pont4 (an identifiable
amphibious bridging vehicle); k_forest10 (Shutterstock watermark); Poly Haven `island_tree_*` (a
Mediterranean olive form). Also every other WARNO, Broken Arrow and Men of War II store shot: cinematic
low shots, identifiable vehicles. **No photo was retrieved for a culvert, a farm trailer, corrugated
steel grain bins or an intact panel block.** The Commons API search returned nothing usable. These are
briefed from stated dimensions; at their on-screen size a photo would add little.

**The Moshchun, Irpin and Bervytsia frames show a real war and a real army** (NGU watermark,
flags). They inform damage morphology only. Nothing from them may appear in an asset: no flag, no
watermark, no recognisable building, no national colours.

### CC0 candidates checked (Poly Haven API; sizes from the API, in metres)

| asset | size | polys | verdict |
| --- | --- | --- | --- |
| [rock_moss_set_01](https://polyhaven.com/a/rock_moss_set_01) / [_02](https://polyhaven.com/a/rock_moss_set_02) | 8.0 × 6.9 × 1.8 / 8.3 × 3.4 × 1.4 set | 63k / 58k | **ship**: grey, mossy, angular glacial-erratic look (matches boulder0). Decimate each rock to 300–600 faces and bake the normals |
| [boulder_01](https://polyhaven.com/a/boulder_01) | 1.3 × 1.8 × 1.0 | 124k | **ship** after decimation. Warm brown: desaturate the albedo about 30 % |
| [namaqualand_boulder_04](https://polyhaven.com/a/namaqualand_boulder_04) | 2.5 × 2.5 × 1.9 | 111k | reference only: orange desert lichen, wrong region |
| [tree_stump_01](https://polyhaven.com/a/tree_stump_01), [dead_tree_trunk_02](https://polyhaven.com/a/dead_tree_trunk_02) | 1.4 × 1.6 × 0.6; 4.1 m log | 41k; 156k | **ship** as forest deadfall and clearing props after decimation |
| [pine_tree_01](https://polyhaven.com/a/pine_tree_01) | 3 trees, 17.6 m tall | **17.4 M** | Scots-pine form, right height. **Not shippable as a mesh**; its CC0 bark and needle-twig textures are the source for Blender cards |
| [fir_tree_01](https://polyhaven.com/a/fir_tree_01) | 19.3 m tall | 7.9 M | Same use: spruce or fir texture source for the conifer clumps |
| [modular_electricity_poles](https://polyhaven.com/a/modular_electricity_poles) | kit, 7.0 m poles | 201k | Wooden urban kit. Useful only for crossarm and insulator parts; the rural pole is **concrete** (k_pylon4) |
| Kenney, Quaternius | — | — | Stylised: never a reference |
| ambientCG materials | CorrugatedSteel005/007, RoofingTiles006/013A, Bricks105, Plaster001, Concrete034/046, Planks021, MetalPlates013, Bark012 | — | **ship** as tiling PBR for the Blender-built props. Darken and desaturate to the mood |

No realistic CC0 birch, oak, lime or shrub model exists on Poly Haven or ambientCG. Those come from
Tripo (single hero trees) or are built in Blender (clumps), as below.

---

## Per-prop sheets

Format: **size** (m → tiles) · **from above** · **materials and weathering** · **refs** · **route** ·
prompt or build spec. Common to every Tripo prompt (append it verbatim):

> `photorealistic PBR, real-world scale, physically based materials, overcast diffuse light, wet
> weathered surfaces, muted desaturated colours, no text, no logos, no flags, no insignia, isolated
> object on flat ground, no base plate, no stylisation, not cartoon, not toy, not low-poly art`

Tripo flags: `--model tripo-p1 -p face_limit=<budget>`, GLB output, no FBX conversion (per the
`asset-manager` skill). After generation: set the bounding box to the stated metres in Blender, put the pivot at the bottom centre with the front along −Z,
and check the preview from 45° above.

**ACCEPT IF** (every Tripo prop): bounding box within ±5 % of the stated metres after fitting; reads
as the named object in a 45°-above preview scaled to 100 px tall; no base plate or ground disc; face
count ≤ the stated budget; no text, number or emblem anywhere on the texture; mean albedo L* ≤ 60
except white plaster or bark.

### Houses (village side)

What the references agree on (k_aerialpl1, k_wd7, house0/3/5, k_pole3/7): **grey corrugated
asbestos-cement sheet (шифер) is the dominant roof**, then dark brown, graphite or dull red metal tile,
and occasionally an ochre or green painted corrugated roof. That grey dominates the colour read from above and already
sits in the mood's dark desaturated range. Walls are white or cream plaster, buff or red brick, or white
silicate brick. Windows are white PVC. Modern cues for the 2030s: rooftop PV panels (dark blue-black,
1.0 × 1.7 m modules in 2–4 rows), satellite dishes, profiled-sheet or decorative concrete fences, a
gas pipe along the façade. Plots are long, 15–25 m wide and 40–80 m deep: house at the street, sheds behind,
a vegetable garden at the back (k_wd4, k_wd7).

| id | type | footprint × height | tiles | from above |
| --- | --- | --- | --- | --- |
| H1 | one-storey plastered house, hipped grey шифер roof, veranda | 10 × 8 m, eaves 3.0 m, ridge 6.0 m, pitch 30° | 1.25 × 1.0 | Pale-grey hipped roof with one brick chimney; the cream façade shows on one side |
| H2 | one-storey brick-faced house, gable metal-tile roof (dark brown), enclosed porch | 11 × 9 m, eaves 3.2 m, ridge 7.0 m | 1.4 × 1.1 | Dark gable roof, light ridge line, satellite dish on the gable |
| H3 | two-storey 2010s–2030s cottage, plaster plus brick plinth, graphite metal tile, PV array on the south roof | 10 × 10 m, eaves 6.0 m, ridge 9.5 m | 1.25 × 1.25 | Large dark roof with a blue-black PV block 5 × 3.4 m; tallest roof in the hamlet |
| H4 | small wooden-clad house, green or ochre corrugated metal roof (house3, house5) | 9 × 6 m, ridge 5.5 m | 1.1 × 0.75 | Small coloured roof: the one accent of saturated colour, kept low-chroma |
| H5 | 2–3-storey brick or panel apartment block, flat bitumen roof, 2–3 stairwells (k_pole8) | 30 × 12 m, 7–10 m high | 3.75 × 1.5 | Flat dark roof with vent stacks and stair-head boxes; a long silhouette, a landmark |
| R1–R3 | ruins of H1, H2/H3 and H5 | footprint +3–5 m rubble apron | +0.5 tile | See Ruins |

**Route.** H1–H4 are **Tripo**: irregular, many small parts, and they read better generated than
built from boxes. 3000–5000 faces each, texture at most 1024 px. H5 is **Blender**: boxes with a
tiling façade texture, one baked atlas, about 1500 faces. Generate each house intact; ruins are
separate assets, not a damage shader.

Tripo prompt H1 (adapt the others from the table):
> `single-storey rural house in contemporary Eastern Europe, 10 m by 8 m footprint, 6 m to the
> ridge, cream lime-plaster walls with grey patches of damp, low hipped roof of grey corrugated
> fibre-cement sheets with moss streaks, one brick chimney, white PVC windows, small glazed
> veranda on the long side, concrete steps, gutter and downpipe, satellite dish on the wall,` +
> common suffix.

H3 adds: `two storeys, graphite metal-tile gable roof, rooftop solar panel array on one slope,
render over brick, brick plinth, clean modern lines`. **Must not:** shop signs, house numbers, flags, ornate Baroque or Tudor detail, slate, timber framing.
H1 also passes if the roof is ≥ 55 % of the top-down silhouette and is grey, not red.

### Ruins (shelled houses)

Measured from k_wd6 (nadir view; tyres Ø 0.6 m ≈ 10 px give about 6 cm/px):

- Walls stand to **0.5–2.5 m** over most of the footprint, 0.25–0.4 m thick. One or two fragments
  reach eave height, often a **brick chimney stack** (k_wd3). The roof is **gone or collapsed inside the footprint**.
- **Rubble apron 2–5 m** outside the walls: brick in buff, orange and white, plaster chunks, and
  **corrugated roof sheets (red, brown, grey) bent and scattered**. They are the brightest pieces, at
  0.9 × 2 m (13 × 28 px at close zoom).
- Burnt variant (k_db11): soot black above window heads, sheets sagging inside, door and window holes
  open and black.
- Partial hit (k_db14, k_wd5): roof torn open over a third of the length, rafters showing, the rest
  intact. This is the cheapest "damaged" state: an intact house with a hole.

Route: **Tripo** for the rubble mass and wall stubs, 3000–4000 faces; scattered roof sheets added in
**Blender** as ~10 thin bent quads (cheap, and the right size). Prompt:
> `ruin of a shelled single-storey brick house, 10 m by 8 m footprint, walls broken down to 0.5 to
> 2.5 m high, one brick chimney stack standing 5 m, roof completely collapsed into the interior,
> heaps of broken brick and plaster spilling 3 m beyond the walls, bent corrugated roof sheets
> scattered on the rubble, charred timber beams, soot-blackened window openings, wet dust,` + common
> suffix. **Must not:** medieval stone, arches, ivy-covered romance ruin, bodies, vehicles, flags.
Also passes if no wall stands higher than 3 m except the chimney, and rubble covers ≥ 1.3× the footprint area from above.

### Farm and industrial

| id | prop | size | tiles | route | notes |
| --- | --- | --- | --- | --- | --- |
| F1 | farm barn or shed, brick base plus vertical grey boards (hangar4), grey шифер roof | 15 × 7 m, ridge 6.5 m | 1.9 × 0.9 | Tripo, 2500 faces | prompt as H1 with `farm barn, rough sawn grey vertical boards over a rubble-stone and brick lower wall, wide double doors` |
| F2 | long livestock barn (from k_aerialpl1, k_wd4) | 60 × 12 m, ridge 6 m | 7.5 × 1.5 | Blender | Long grey roof with a row of roof vents; white silicate-brick walls; half the roof sheets missing in the damaged variant |
| F3 | steel portal-frame agricultural hangar | 36 × 18 m, eaves 6 m, ridge 9 m | 4.5 × 2.25 | Blender, ~800 faces | Light-grey or green trapezoidal cladding, two roller doors 5 × 5 m, darker roof panels showing seam lines every ~1 m |
| F4 | corrugated-steel grain bins, 3–4 in a row, plus an elevator leg | each Ø 7 m × 10 m plus 2 m cone; leg 20 m | 1 tile each, group 4 × 1.5 | Blender (lathe) | Galvanised grey with dull streaks; conical roof; a catwalk between the tops. Reads as a cluster of discs from above |
| F5 | concrete silo battery (silo2, warno18) | 6 cells Ø 6 m × 25 m | 4.5 × 1 | Blender | Tallest object on the map: use as a landmark on one side only |
| F6 | small fuel station (k_pole6) | canopy 15 × 9 m at 5 m, 2 pump islands, kiosk 8 × 5 × 3 m | 2 × 1.2 | Blender | Neutral grey canopy, **no brand colours, no price board text**; stained concrete apron |
| F7 | water tower, steel tank on a pipe (k_wt1) | tank Ø 3 m × 6 m on a Ø 1.4 m column; 18 m overall | 0.4 × 0.4 | Blender, 300 faces | Grey-white paint peeling to rust. **Not** blue and yellow (k_wt2/3) |
| F7b | water tower, brick (k_wt0) | Ø 5 m, 22 m | 0.6 | Blender | Red-brown brick, steel tank cap; a landmark |
| F8 | farm tipping trailer, two axles | body 6.0 × 2.4 × 1.0 m, overall 7.5 × 2.5 × 2.3 m | 0.9 × 0.3 | Blender | Faded blue-green or rust-red steel box on four tyres, drawbar; **no maker plate, no lettering**. Doubles as a wreck when tipped and burnt |
| F9 | concrete culvert under a road | Ø 1.0–1.5 m pipe, 10 m long, headwalls 3 × 1.5 m | 0.4 | Blender plus a ground decal | Only the headwalls and dark pipe mouths are seen; mostly a ditch decal |
| F10 | concrete jersey blocks, road blocks | 2.0 × 0.6 × 0.8 m | 0.25 | Blender, 50 faces | Grey with chipped edges; checkpoints and battle scars |

Prompt F1 is enough for Tripo; the rest are dimensioned primitives with ambientCG materials (shipped
CC0), one baked atlas per prop, no generator.

### Fences and walls

| prop | real dimensions | reads as | route |
| --- | --- | --- | --- |
| profiled-sheet fence (house3, house5): the most common modern rural fence | 1.8–2.0 m high, sheets 1.15 m wide on steel posts every 2.5 m | Solid coloured strip (grey, green, red-brown), 26 px tall at close zoom | Blender, one quad per 2.5 m plus a bevel |
| decorative concrete "euro" fence (house0, k_pole5) | sections 2.0 m, 1.5–2.0 m high, posts 0.15 m | Pale grey with a relief pattern; reads as a dotted wall | Blender, normal-mapped quads |
| industrial panel fence, PO-2 type (k_po21, k_po25) | panels about 4 m × 2.5 m on posts (measured against trees; **not confirmed against a datasheet**) | Long light-grey wall round yards, quarries and depots | Blender |
| wooden picket or plank fence | 1.2–1.5 m, boards 0.1 m | Under 1 px per board at far zoom: **alpha card**, not geometry | Blender card |
| low dry wall of fieldstone or broken concrete | 0.8–1.0 m high, 0.6 m thick | Grey line with a contact shadow | Tripo (irregular), 800 faces per 8 m segment. Prompt: `straight segment of low field wall, 8 m long, 0.9 m high, 0.6 m thick, stacked grey fieldstones and broken concrete chunks, moss in the joints, wet,` + common suffix |

All fences come in straight 8 m segments with a corner piece, snapped to plot lines, not to tiles. The rules grid is not drawn (§8).

### Hay bales

Round bales Ø 1.2–1.5 m, width 1.2 m (k_bales3/9). Wet late-autumn colour: grey-ochre to dark khaki,
never golden. Wrapped silage bales are white, pale green or black plastic (k_bales7), the one
glossy material in a field. Laid in loose rows 10–30 m apart, or stacked 2–3 high at the yard edge.
**Blender**: a 24-segment cylinder with a bevelled rim and a spiral normal map, about 120 faces. No generator.

### Power lines

| element | real numbers | on screen | route |
| --- | --- | --- | --- |
| concrete distribution pole, 10 kV (k_pylon4/6) | SV-95/105 type: 9.5–10.5 m long (SV-95 length 9.5 m from a manufacturer listing); about 2.5 m buried, so **7–8 m above ground** (burial depth typical, unverified); square section tapering 0.28 → 0.17 m; steel crossarm 1.8–2.0 m at the top with three pin insulators | Pole 100 px tall at close zoom, crossarm 26 px | Blender, ~150 faces |
| 0.4 kV street pole variant | same pole, 4 insulators on brackets or a black insulated bundle cable, wires 6–7 m above ground | — | Blender |
| wooden pole (k_pole8) | pine log Ø 0.25 m, 8–9 m, bolted to a 3 m concrete stub | — | Blender (Poly Haven modular_electricity_poles crossarm parts may be reused, CC0) |
| spans (typical engineering values, **unverified**) | 10 kV: **50–70 m = 6–9 tiles**; 0.4 kV: **30–40 m = 4–5 tiles**; sag 0.8–1.5 m; ground clearance ≥ 6 m | — | — |
| steel lattice tower, 110–330 kV (k_pylon9) | **25–40 m tall** (Wikipedia: transmission towers typically 15–55 m); two or three crossarms; insulator strings 2–3 m; lowest wire ≥ 7 m | 70–140 px at far zoom; the tallest prop | Blender (beams as thin boxes, ~1500 faces), or an alpha-card lattice at 2 cards per face |
| lattice spans (typical, **unverified**) | **250–400 m = 31–50 tiles**, longer than a map; sag 6–12 m | — | — |

- **Wires are never meshes.** They are under 0.5 px wide at every zoom. Draw them as screen-space lines of
  constant 1 px, dark grey at 60 % alpha, as catenaries between the attachment points, or leave them out.
  The sag and attachment heights above are real numbers. They place the line, and they do not change
  any mesh.
- A board holds **at most one lattice tower**. Its line runs off the board in both directions, through a
  cut 30–40 m wide in a forest (the cut itself is the readable feature from above). Distribution
  poles follow roads, set 6–9 tiles apart.
- Insulators are light-grey or green-glass dots, 2–4 px. A pole-mounted transformer (k_pole3) is an optional
  variant: a 1.5 m grey box at 4 m.

### Trees (single)

| species | height | crown | from above | late-autumn state (River) |
| --- | --- | --- | --- | --- |
| Scots pine (pine2, pine5, k_wd7) | 18–25 m (Wiedemann 1943 yield table: 18–25 m at 60–80 years) | Ø 4–7 m, flat-topped, in the top third | Dark green-grey flattened crown; the orange-brown upper trunk shows only at edges | Evergreen: the only full canopy in late autumn |
| Norway spruce / fir | 20–28 m | Ø 3–5 m, conical | Pointed star crowns, darkest green, k_forest9 | Evergreen |
| silver birch (birch2/3) | 15–22 m | Ø 4–7 m, narrow, drooping | Sparse yellow or bare crown; the **white trunk is the identifier**, readable from 45° | Few last yellow leaves, mostly bare twigs |
| oak / lime (oak4, oak3) | 18–25 m | Ø 10–16 m in the open | Broad dome, the biggest silhouette | Brown leaves holding on (oak) or bare (lime) |
| bare deciduous (oak3, bare0) | 10–20 m | Ø 8–12 m | A web of branches over a visible ground shadow | Fully bare |
| shrubs: hazel, willow, blackthorn | 2–5 m | Ø 2–5 m | Dark brown-grey mounds | Mostly bare, dense twigs |

Route: single hero trees (solitary oak, birch, roadside lime or pear) are **Tripo**, 1500–3000 faces,
then foliage converted to alpha-cut cards in Blender if Tripo merges the crown into a solid blob.
Prompt (oak):
> `solitary mature oak tree in a ploughed field in late autumn, 20 m tall, broad 14 m crown of
> thick twisting branches holding sparse brown withered leaves, deeply furrowed grey bark, trunk
> 1 m diameter,` + common suffix + `separate leaf clusters, see-through crown`. **Must not:** a
> lollipop sphere crown, uniform green, a fantasy twisted shape, a grass disc base. Also passes if the
> ground is visible through ≥ 40 % of the crown from above.

Birch: adapt the oak prompt to `silver birch, 18 m tall, narrow 5 m crown of drooping fine twigs, white
bark with black fissures and a dark rough base, a few last yellow leaves`.

Conifers are **Blender**: cards built from the Poly Haven pine and fir textures (CC0), 200–400 faces per tree.

---

## Forest — dense woods a tank can hide in

### What a real wood looks like at this camera (measured)

| wood type | refs | crowns per 8 × 8 m tile | canopy cover from above | crown base | what stands under it |
| --- | --- | --- | --- | --- | --- |
| pine plantation, 40–80 years | k_wd7, pine5 | **2–3** (crowns Ø 5–7 m) | 80–90 %; ground shows in gaps 1–3 m wide | 10–14 m: tall clean trunks in rows 2–3 m apart | Little: sparse sapling pines, bracken, needle litter, dead branches |
| spruce or young conifer | k_forest8, k_forest9 (road ≈ 6 m ≈ 70 px gives 8.6 cm/px; crowns 25–40 px = 2–3.5 m) | **6–9** | 90–95 % | 2–6 m: green to the ground | Almost nothing visible |
| mixed (pine, birch, oak) | k_wd7 edge, birch3, k_forest15 | 2–4 (Ø 4–10 m) | 70–85 % in late autumn: conifers stay, birch and oak thin out | 5–10 m | Hazel and young spruce 2–5 m, bracken, deadfall |
| broadleaf (oak, hornbeam, lime) | k_forest1/5 (summer), **k_forest11 (late autumn)** | 1–2 (Ø 8–14 m) | summer 90 %+; **late autumn 30–50 % (branches only)**: the ground and anything on it shows through | 4–8 m | Hornbeam and hazel understory 2–6 m, leaf litter, logs |

**The setting decides the hiding place.** In late autumn a broadleaf wood is a lattice of bare
branches (k_forest11): realistically it does **not** hide a tank from above. Only conifer stands
and dense young growth do. If woods must conceal, the concealing woods are **pine and spruce**, and
broadleaf woods read as see-through cover. That is true to the setting, and it doubles as information.

### What stays visible of a unit — open decision

Woods dense enough to hide a 7.5 m tank conflict with pillar 5 and §3.5: a unit on scouted ground must
be **identifiable at ~100 px** and inspectable. The numbers that frame the choice:

- Under 85 % pine canopy with the crown base at 10 m, a 2.5 m-tall hull at 45° pitch shows **10–20 %
  of its top area** in the gaps: two or three 1–2 m fragments, not a silhouette. A squad base (four
  figures on about 3 × 3 m) is effectively hidden.
- Options: **(a)** the clump on any tile holding a visible unit fades or dithers to about 30 % opacity
  within ~0.6 tile of the unit, so the wood stays dense everywhere else. **(b)** Units are drawn over
  the canopy with an outline or silhouette pass, which is cheap but looks "x-ray". **(c)** A crown-cut
  variant: the clump on an occupied tile swaps for a version with a 4–5 m gap over the tile centre.
  It is consistent with ruts and broken trees as battle scars, and a tank that drove in breaks trees anyway.
- (c) with (a) as the fallback keeps the wood dense without breaking legibility. Hidden *enemy* units are
  already hidden by the fog rules, not by trees.

### Edge treatment (k_forest1, k_forest5, k_wd7)

- A **shrub belt 3–6 m deep** (hazel, blackthorn, young birch, young pine 2–5 m tall) along every
  wood–field edge. It is denser than the interior and sits lower, so the edge steps up in 2–3 bands:
  shrubs 2–5 m, then young or edge trees 8–15 m, then the full canopy 18–25 m.
- Edge trees carry crowns lower and wider on the open side. Trunks are visible only in the first row.
- The edge line is irregular, with bays and spurs of 5–20 m, never along tile edges (§8).
- On the edge tile itself: deadfall logs 4–10 m (Poly Haven dead_tree_trunk_02, tree_stump_01, CC0),
  bracken patches (a ground texture, not geometry), and the odd boulder.

### Assets and budget

The arithmetic that rules out individual trees: a 24 × 16 board at 30 % wood is about 115 forest tiles. At
3 crowns per tile and 300–400 faces per tree that is 100–140k faces for trees alone. Over budget.

| asset | content | faces | instancing |
| --- | --- | --- | --- |
| **canopy-mass tile** (interior) ×3 variants per wood type | One lumpy hull 8 × 8 m (overhangs 1–2 m) with an alpha-cut crown-mass texture: 2–3 pine crowns, or 1–2 oak or bare crowns; no trunks (unseen) | **150–300** | MultiMeshInstance3D, one draw call per variant |
| **edge clump** ×4 variants per type | 2–4 trees with cards plus 3–5 visible trunks plus a shrub-belt card strip on the open side, stepped heights | **800–1200** | MultiMesh |
| **crown-cut clump** (option c) | Interior clump with a 4–5 m gap and 1–2 broken or leaning trunks | 400–600 | swapped at runtime |
| shrub cards | Crossed quads 2–5 m, bare hazel and willow twig mass | 8–16 | MultiMesh |
| hero tree (solitary oak, birch, roadside lime) | Tripo, see Trees | 1500–3000 | ≤ 10 per map |
| deadfall, stumps, boulders | Poly Haven CC0, decimated | 200–600 | MultiMesh |

Estimate: 115 tiles split 40 % edge and 60 % interior → 46 × 1000 + 69 × 250 ≈ **63k faces** with
the whole wood on screen (far zoom), in about **10 draw calls**. That leaves ~85k faces for houses,
props and units. Build all clumps in **Blender**: geometry nodes scatter the cards onto hull points, then
bake the clump. Textures: Poly Haven pine and fir bark and twig maps (CC0) for conifers. Broadleaf and
bare crown-mass textures need a 1 m-scale branch-mass texture, which no CC0 source here has. Brief:

```
ASSET: bare_broadleaf_crown_atlas   USE: alpha-cut texture for canopy-mass and clump cards   COVERS: 4 × 4 m per cell
SOURCE REFS: k_forest11 (density of bare crowns from above), oak3 and bare0 (branch structure), k_forest15 (few remaining leaves)
VIEW: straight top-down orthographic per cell, on a transparent background
CONTENT: 2 × 2 atlas, 4 cells, each a single bare deciduous crown seen from directly above: branches
  radiate from the centre 0.1–0.3 m thick, then twig masses 0.5–1.5 m; 40–55 % of the cell
  opaque; 0–10 % of the opaque area carries clusters of withered brown leaves 0.3–0.8 m
COLOUR: branches dark grey-brown, L* 20–32, chroma < 10; leaves dull brown L* 30–40; wet, never golden
MUST NOT: perspective trunks, ground, shadows, sky; a regular radial starburst; repeating identical
  branches; green leaves; outlines
TILING: no tiling; each cell self-contained and fading to full transparency 0.2 m inside its border
DELIVERABLE: 2048 × 2048 PNG RGBA (alpha = coverage), raw output, no post-processing by the generator
ACCEPT IF: alpha coverage 40–55 % per cell; no two cells mirror each other; at 4.5 px/m (downscaled to
  18 px per cell) each cell still reads as an irregular crown and not a disc or a star; mean L* of
  opaque pixels 20–35
```

The conifer equivalent needs no generation: render the Poly Haven pine_tree_01 and fir_tree_01 crowns from above
in Blender into an atlas (CC0 source, derived asset).

---

## Bridges

The underside is never seen at this camera, so **prestressed concrete beam and steel girder share one
silhouette** (flat deck, railings, piers). The steel girder is a material variant of the beam bridge
(rust-brown painted girder edge 1.2–1.8 m deep showing at the deck side), not a separate model. That
leaves three silhouettes, each with a destroyed state. Sizes are for a river 1–3 tiles (8–24 m) of water plus banks.

| id | type | dimensions | tiles | from above | destroyed state | route |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | concrete beam, 1–3 spans | deck 7–9 m wide (2 lanes plus kerbs), spans 12–18 m, deck 1.0–1.2 m thick, piers 1 m × deck width, parapet or guardrail 0.9 m; total length 16–40 m | 1 × 2–5 | Grey deck with asphalt, white kerb lines, dark slit of water each side, pier caps shown as darker bands on the water | **dbridge0/1/5**: one span dropped off a pier, the end in the water and the other still on the abutment (a "V"), deck broken into 2–4 slabs, railings hanging, rebar ends, pale concrete dust on the debris | Blender; the destroyed state is a Blender cell-fracture plus hand-placed slabs |
| B1s | steel girder variant | as B1, girders visible along the deck edge, steel railing | same | Rust-brown edge line | Girder twisted, deck sagging into the water | Blender |
| B2 | panel-truss (Bailey-type) military bridge | panels 3.0 m long × 1.5 m high, roadbed 3.7 m wide (Wikipedia, Bailey bridge); overall width ~4.5 m; single lane; spans up to 61 m unsupported, 15–45 m here, on concrete or crib abutments; timber or steel deck | **0.55** × 2–6 | Two dark lattice walls 1.5 m tall casting a shadow onto a narrow deck. Unmistakable even at 22 cm/px | **k_bailey1**: one end dropped off its seat, trusses buckled and twisted, deck planks splayed | Blender: one panel modelled, arrayed; ~2500 faces per 30 m |
| B3 | floating ribbon or pontoon bridge | bays about 6.7 m long × 8 m wide (approximate, **not confirmed against a datasheet**), deck 0.6–0.8 m above water; ramp bays 6–8 m at each bank; sits on the water and follows the river line | 1 × river width + 1–2 | Long flat olive-grey or dark steel strip on the water, bay joints every 6.7 m, ramp wedges onto the banks; anchor or tow boats optional | **pontoon1**: bays separated by 2–10 m gaps, one tilted and half sunk, ends drifting downstream at 10–20° | Blender |

Rules: the deck surface is at the road's height (Height is cosmetic and touches no rule, §8). Bridges stay generic: **no unit markings,
no national colours, no stencilled numbers**. Pontoon and panel bridges are the engineers' bridges
(§3.8): their destroyed and repaired states are information, so the destroyed version must read at
22 cm/px, where a gap of at least 4 m (18 px) is needed.

---

## Two characters for the two halves of a map

k_wd7 shows both in one frame. Give each player's side a distinct roof palette, tree mix and
infrastructure so a screenshot tells you whose half it is.

| | **Farmland hamlet** | **Pine-wood quarry and forestry side** |
| --- | --- | --- |
| buildings | H1, H2, H4: plaster and brick, grey шифер and dark-red metal roofs, sheds, long livestock barn F2, grain bins F4 | H3 and wooden H4 with graphite and green metal roofs, a small panel block H5 (workers' housing), steel hangar F3 (sawmill or depot), concrete yard fence |
| trees | Birch and willow lines along ditches, solitary oaks and limes in fields, orchards (bare pear and apple, bare0) | Pine plantation in straight rows, spruce, birch at the margins, deadfall, stumps in clear-cuts |
| ground props | Round hay bales, the trailer, decorative and profiled-sheet fences | Log stacks (Blender cylinders, 4 m logs Ø 0.3 m), sand or gravel pit edge, boulders, jersey blocks |
| infrastructure | Concrete poles along the road, a fuel station, a steel water tower | A lattice tower line in a forest cut, a brick water tower or silo battery as the landmark |
| bridges | Concrete beam bridge on the main road | Bailey-type bridge on the forestry track; the pontoon is the engineers' answer |
| palette | Pale plaster, grey roofs, ochre-khaki fields | Darker: green-black canopy, graphite roofs, sand-grey yard |

Keep both inside the mood target (river_target.jpg): ground L* 24–34, desaturated. The only saturated notes are the few
coloured roofs and fences, kept at low chroma, and fire.

## Must stay fictional or unbranded

No flags, insignia, national colour schemes (blue-yellow water towers and fences are common in
the real references: exclude them), shop or fuel brands, readable text, house numbers, road signs
with real names, vehicle maker badges, or recognisable real buildings. Military bridges are generic
types, never a named in-service system's markings. Real-war photos are reference for morphology only.
