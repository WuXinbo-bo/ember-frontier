"""Read-only extraction of the three immutable resident GLBs for texture artists.

Run with the bundled Python (Pillow + NumPy). No Blender, GLB write, import or app.
The raster previews are UV/shape diagnostics, never normal-camera VA evidence.
"""
from pathlib import Path
import hashlib
import io
import json
import math
import struct
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / "outputs/r3-3-character-uv-v1"
PROJECT = ROOT / "godot/afterglow"
PART_COLORS = {"root": "#d9954c", "head": "#cd707e", "arm_l": "#5c9dac",
               "arm_r": "#527dc4", "leg_l": "#8e9b58", "leg_r": "#a57ba7"}
FONT = "/System/Library/Fonts/Menlo.ttc"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def font(size):
    return ImageFont.truetype(FONT, size)


def read_glb(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw)
    assert magic == b"glTF" and version == 2 and length == len(raw)
    chunks = {}
    offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        chunks[kind] = raw[offset + 8:offset + 8 + size]
        offset += size + 8
    return raw, json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]


def accessor(doc, binary, index):
    item = doc["accessors"][index]
    assert not item.get("sparse") and not item.get("normalized")
    view = doc["bufferViews"][item["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[item["type"]]
    dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[item["componentType"]]
    size = np.dtype(dtype).itemsize
    return np.ndarray((item["count"], width), dtype=dtype, buffer=binary,
                      offset=view.get("byteOffset", 0) + item.get("byteOffset", 0),
                      strides=(view.get("byteStride", width * size), size)).copy()


def render(triangles, texture, direction):
    """Orthographic software raster of exact neutral GLB vertices/UVs."""
    width, height = 320, 440
    result = np.full((height, width, 3), [229, 226, 215], dtype=np.uint8)
    depth = np.full((height, width), -np.inf)
    eye = np.array(direction, dtype=float); eye /= np.linalg.norm(eye)
    right = np.cross([0, 1, 0], eye); right /= np.linalg.norm(right)
    up = np.cross(eye, right)
    center = np.array([0., 1., 0.])
    light = np.array([.35, .8, .6]); light /= np.linalg.norm(light)
    pixels = np.array(texture.convert("RGB"))
    for points, uv in triangles:
        relative = points - center
        screen = np.column_stack([relative @ right * 172 + width / 2,
                                  -relative @ up * 172 + height / 2,
                                  relative @ eye])
        lo = np.maximum(np.floor(screen[:, :2].min(axis=0)).astype(int), 0)
        hi = np.minimum(np.ceil(screen[:, :2].max(axis=0)).astype(int), [width-1, height-1])
        if np.any(hi < lo):
            continue
        x, y = np.meshgrid(np.arange(lo[0], hi[0]+1)+.5, np.arange(lo[1], hi[1]+1)+.5)
        a, b, c = screen
        denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(denominator) < 1e-8:
            continue
        u = ((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/denominator
        v = ((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/denominator
        w = 1-u-v
        z = u*a[2]+v*b[2]+w*c[2]
        target = depth[lo[1]:hi[1]+1, lo[0]:hi[0]+1]
        take = (u >= -1e-6) & (v >= -1e-6) & (w >= -1e-6) & (z > target)
        tuv = u[..., None]*uv[0] + v[..., None]*uv[1] + w[..., None]*uv[2]
        tx = np.clip((tuv[..., 0]*texture.width).astype(int), 0, texture.width-1)
        ty = np.clip((tuv[..., 1]*texture.height).astype(int), 0, texture.height-1)
        normal = np.cross(points[1]-points[0], points[2]-points[0])
        normal /= np.linalg.norm(normal)
        shade = .60 + .40*max(0, float(normal @ light))
        color = np.clip(pixels[ty, tx].astype(float)*shade, 0, 255).astype(np.uint8)
        result[lo[1]:hi[1]+1, lo[0]:hi[0]+1][take] = color[take]
        target[take] = z[take]
    return Image.fromarray(result)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source_tiles = json.loads((ROOT/"public/art/city-opening-v1/atlases/model_albedo.json").read_text())["tiles"]
    tile_names = {(v["pixel_rect"][0]//128, v["pixel_rect"][1]//128): k for k, v in source_tiles.items()}
    report = {"schema": "afterglow-resident-original-uv-v1", "uv_origin": "top-left in exported glTF TEXCOORD_0 and PNG",
              "scope": "immutable GLB original-UV extraction; diagnostic previews, NOT new finished skins or VA", "actors": []}
    for role in ["commuter", "neighbor", "shopkeeper"]:
        ident = "r1_resident_" + role
        path = PROJECT / "data/gameplay/actors" / (ident + ".glb")
        raw, doc, binary = read_glb(path)
        original = ROOT / "public/art/city-life-r1-v1/models/residents" / (ident + ".glb")
        assert original.read_bytes() == raw
        target = OUT / role; target.mkdir(exist_ok=True)
        view = doc["bufferViews"][doc["images"][0]["bufferView"]]
        packed = binary[view.get("byteOffset", 0):view.get("byteOffset", 0)+view["byteLength"]]
        (target/"source-original.png").write_bytes(packed)
        texture = Image.open(io.BytesIO(packed))
        assert texture.size == (512, 512) and texture.mode == "RGB"
        assert packed == (ROOT/"public/art/city-life-r1-v1/atlases/models"/(ident+".png")).read_bytes()
        assert packed == (PROJECT/"data/gameplay/actors"/(ident+"_model_albedo.png")).read_bytes()
        grid = doc["extras"]["city_local_atlas"]
        mapping = {(x, y): tile_names[sx, sy] for x, y, sx, sy in grid["tiles"]}
        wire = Image.new("RGBA", (512, 512)); draw_wire = ImageDraw.Draw(wire)
        masks = {}; parts = []; all_triangles = []; region_uses = {}
        # These assets' neutral transform hierarchy is translation-only. Fail
        # closed if a future model revision requires matrix/quaternion handling.
        for node in doc["nodes"]:
            assert not node.get("matrix") and not node.get("rotation") and not node.get("scale")
            if "mesh" not in node:
                continue
            part = node["name"]; color = PART_COLORS[part]
            mask = Image.new("L", (512, 512)); dm = ImageDraw.Draw(mask)
            part_wire = Image.new("RGBA", (512, 512)); dw = ImageDraw.Draw(part_wire)
            primitive_records = []
            for primitive in doc["meshes"][node["mesh"]]["primitives"]:
                positions = accessor(doc, binary, primitive["attributes"]["POSITION"])
                uv = accessor(doc, binary, primitive["attributes"]["TEXCOORD_0"]).astype(float)
                indices = accessor(doc, binary, primitive["indices"]).reshape(-1, 3)
                assert np.isfinite(uv).all() and (uv >= 0).all() and (uv <= 1).all()
                uses = {}
                for tri in indices:
                    coords = [tuple(p) for p in uv[tri]*512]
                    center = uv[tri].mean(axis=0)
                    semantic = mapping[(int(center[0]*4), int(center[1]*4))]
                    uses.setdefault(semantic, []).extend(uv[tri].tolist())
                    dm.polygon(coords, fill=255)
                    draw_wire.line(coords+[coords[0]], fill=color, width=1)
                    dw.line(coords+[coords[0]], fill=color, width=1)
                    points = positions[tri].astype(float)+np.array(node.get("translation", [0, 0, 0]))
                    all_triangles.append((points, uv[tri]))
                for semantic, points in uses.items():
                    values = np.array(points)*512
                    region_uses.setdefault(semantic, []).append({"part": part, "uv_bounds_px_continuous": values.min(axis=0).tolist()+values.max(axis=0).tolist()})
                primitive_records.append({"vertex_count": len(positions), "triangle_count": len(indices),
                                          "material": primitive.get("material"), "semantics": sorted(uses),
                                          "uv": uv.tolist(), "indices": indices.reshape(-1).tolist()})
            mask.save(target/("mask-"+part+".png")); part_wire.save(target/("uv-"+part+".png"))
            masks[part] = mask
            parts.append({"part": part, "mesh": doc["meshes"][node["mesh"]]["name"], "primitives": primitive_records})
        wire.save(target/"uv-wire.png")
        Image.alpha_composite(texture.convert("RGBA"), wire).save(target/"uv-over-original.png")
        overlap = sum(np.array(mask, dtype=np.uint16)//255 for mask in masks.values())
        overlap_image = Image.new("RGBA", (512, 512))
        overlap_pixels = np.zeros((512, 512, 4), dtype=np.uint8)
        overlap_pixels[overlap > 0] = [93, 154, 145, 180]
        overlap_pixels[overlap > 1] = [218, 92, 76, 230]
        Image.fromarray(overlap_pixels).save(target/"part-overlap.png")
        regions = []
        board = texture.convert("RGB").resize((1024, 1024), Image.Resampling.NEAREST)
        db = ImageDraw.Draw(board)
        for (x, y), semantic in mapping.items():
            rect = [x*128, y*128, 128, 128]
            regions.append({"semantic": semantic, "tile_px_xywh": rect,
                            "content_px_xywh": [x*128+2, y*128+2, 124, 124],
                            "gutter_px": 2, "uses": region_uses.get(semantic, [])})
            db.rectangle((x*256, y*256, (x+1)*256-1, (y+1)*256-1), outline="#f6cc69", width=2)
            db.rectangle((x*256+4, y*256+4, (x+1)*256-5, y*256+53), fill="#233a39")
            db.text((x*256+10, y*256+8), semantic, font=font(16), fill="white")
            db.text((x*256+10, y*256+30), f"x{x*128} y{y*128} / 128px", font=font(13), fill="#eddfaa")
        board.save(target/"atlas-regions-preview.png")
        previews = Image.new("RGB", (1280, 480), "#e5e2d7"); dp = ImageDraw.Draw(previews)
        for i, (name, direction) in enumerate([("FRONT +Z", [0, .1, 1]), ("BACK -Z", [0, .1, -1]), ("SIDE +X", [1, .1, 0]), ("THREE QUARTER", [.75, .5, 1])]):
            previews.paste(render(all_triangles, texture, direction), (i*320, 36))
            dp.text((i*320+16, 12), name, font=font(16), fill="#334b46")
        previews.save(target/"neutral-shape-texture-preview.png")
        detail = {"id": ident, "role": role, "source_glb": str(path.relative_to(ROOT)),
                  "source_glb_sha256": sha(raw), "source_atlas_sha256": sha(packed), "size": [512, 512],
                  "source_mode": "RGB", "alpha": "opaque; RGB or RGBA with alpha=255; no transparent clothing holes",
                  "uv_origin": "PNG top-left; UV pixel = (u*512,v*512); no vertical flip",
                  "material": doc["materials"][0], "regions": regions, "parts": parts,
                  "cross_part_overlapping_pixels": int((overlap > 1).sum()),
                  "limitations": ["front/back/side surfaces reuse UV, even inside one rigid part",
                                  "torso and sleeves share cloth; face and hands share skin",
                                  "commuter bag and trousers share cloth_charcoal; only commuter has a satchel mesh",
                                  "no skeletal skin weights: original rigid-part animation hierarchy remains authoritative"]}
        (target/"regions-and-uv.json").write_text(json.dumps(detail, ensure_ascii=False, indent=2))
        assert path.read_bytes() == raw and original.read_bytes() == raw
        report["actors"].append({k: v for k, v in detail.items() if k not in ["parts", "material", "regions"]})
        report["actors"][-1]["region_count"] = len(regions)
        report["actors"][-1]["triangle_count"] = len(all_triangles)
    report["artifacts"] = [{"path": str(p.relative_to(ROOT)), "sha256": sha(p.read_bytes())}
                           for p in sorted(OUT.rglob("*")) if p.is_file() and p.name != "manifest.json"]
    (OUT/"manifest.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(json.dumps({"output": str(OUT), "actors": [{k: a[k] for k in ["role", "region_count", "triangle_count", "cross_part_overlapping_pixels"]} for a in report["actors"]], "artifacts": len(report["artifacts"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
