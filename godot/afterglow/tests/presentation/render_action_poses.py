"""Inspect native exported poses; software lighting is diagnostic, never VA.

Uses the existing bundled NumPy/Pillow. It never writes production resources.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def raster(frame, textures, width, height, pixels_per_metre):
    eye = np.array([24., 29., 31.]); eye /= np.linalg.norm(eye)
    right = np.cross([0., 1., 0.], eye); right /= np.linalg.norm(right)
    up = np.cross(eye, right)
    light = np.array([.35, .8, .6]); light /= np.linalg.norm(light)
    color = np.full((height, width, 3), [229, 226, 215], dtype=np.uint8)
    depth = np.full((height, width), -np.inf)
    projected = []
    for surface in frame["surfaces"]:
        points = np.array(surface["vertices"], dtype=float)
        uv = np.array(surface["uv"], dtype=float)
        indices = np.array(surface["indices"], dtype=int).reshape(-1, 3)
        relative = points - [0., 1., 0.]
        screen = np.column_stack([relative @ right * pixels_per_metre + width / 2,
                                  -relative @ up * pixels_per_metre + height / 2,
                                  relative @ eye])
        projected.append(screen[:, :2])
        texture = textures[surface["texture"]]
        for index in indices:
            tri = screen[index]
            lo = np.maximum(np.floor(tri[:, :2].min(axis=0)).astype(int), 0)
            hi = np.minimum(np.ceil(tri[:, :2].max(axis=0)).astype(int), [width-1, height-1])
            if np.any(hi < lo):
                continue
            x, y = np.meshgrid(np.arange(lo[0], hi[0]+1)+.5, np.arange(lo[1], hi[1]+1)+.5)
            a, b, c = tri
            denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(denominator) < 1e-9:
                continue
            u = ((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/denominator
            v = ((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/denominator
            w = 1-u-v
            z = u*a[2]+v*b[2]+w*c[2]
            old = depth[lo[1]:hi[1]+1, lo[0]:hi[0]+1]
            take = (u >= -1e-7) & (v >= -1e-7) & (w >= -1e-7) & (z > old)
            tuv = u[..., None]*uv[index[0]] + v[..., None]*uv[index[1]] + w[..., None]*uv[index[2]]
            # Resident atlas UVs stay inside 0..1; tool metre UVs repeat.
            tx = np.floor(np.mod(tuv[..., 0], 1.)*texture.shape[1]).astype(int)
            ty = np.floor(np.mod(tuv[..., 1], 1.)*texture.shape[0]).astype(int)
            vertices = points[index]
            normal = np.cross(vertices[1]-vertices[0], vertices[2]-vertices[0])
            length = np.linalg.norm(normal)
            if length < 1e-12:
                continue
            normal /= length
            shade = .60 + .40*max(0., float(normal @ light))
            pixels = np.clip(texture[ty, tx].astype(float)*surface["albedo"]*shade, 0, 255).astype(np.uint8)
            color[lo[1]:hi[1]+1, lo[0]:hi[0]+1][take] = pixels[take]
            old[take] = z[take]
    return Image.fromarray(color), projected


def main():
    root = Path(sys.argv[1]).resolve()
    data = json.loads((root / "action-poses.json").read_text())
    textures = {key: np.array(Image.open(value["path"]).convert("RGB")) for key, value in data["textures"].items()}
    board = Image.new("RGB", (1280, 640), "#e5e2d7")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc", 13)
    metrics = []
    for i, frame in enumerate(data["frames"]):
        closeup, projected = raster(frame, textures, 320, 430, 175.)
        actual, actual_points = raster(frame, textures, 320, 125, 800./24.)
        board.paste(closeup, (i*320, 40)); board.paste(actual, (i*320, 495))
        draw.text((i*320+10, 12), f"Use {frame['fraction']:.2f} cycle / real rig", font=font, fill="#334b46")
        draw.text((i*320+10, 474), "800px height / ortho size24", font=font, fill="#334b46")
        all_points = np.concatenate(actual_points)
        metrics.append({"fraction": frame["fraction"], "projected_bounds_pixels": np.ptp(all_points, axis=0).tolist(), "hand_origin": frame["hand_origin"]})
    draw.text((10, 622), "SOFTWARE DIAGNOSTIC: native pose/UV, approximate light. No world, reach, Metal screenshot or VA proof.", font=font, fill="#334b46")
    board.save(root / "native-use-pose-contact.png")
    (root / "projection-metrics.json").write_text(json.dumps({"scope": "offline geometric projection at production default camera direction and fixed size24 / 800px reference; not observed player zoom", "frames": metrics}, indent=2))
    print(json.dumps({"preview": str(root / "native-use-pose-contact.png"), "frames": metrics}))


if __name__ == "__main__":
    main()
