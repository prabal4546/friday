const PRINT_SIZE_MM = 80;

export function objToBinaryStl(obj: string): ArrayBuffer {
  const points: number[][] = [];
  const triangles: number[][] = [];
  for (const line of obj.split("\n")) {
    const parts = line.trim().split(/\s+/);
    if (parts[0] === "v") {
      const [x, y, z] = parts.slice(1, 4).map(Number);
      points.push([x, -z, y]);
    } else if (parts[0] === "f") {
      const corners = parts.slice(1).map((corner) => {
        const index = parseInt(corner, 10);
        return index < 0 ? points.length + index : index - 1;
      });
      for (let i = 1; i + 1 < corners.length; i++) {
        triangles.push([corners[0], corners[i], corners[i + 1]]);
      }
    }
  }
  if (triangles.length === 0 || triangles.some((triangle) => triangle.some((i) => points[i] === undefined))) {
    throw new Error("The OBJ file has no usable faces");
  }

  const min = [0, 1, 2].map((axis) => Math.min(...points.map((point) => point[axis])));
  const max = [0, 1, 2].map((axis) => Math.max(...points.map((point) => point[axis])));
  const scale = PRINT_SIZE_MM / Math.max(...max.map((value, axis) => value - min[axis]), Number.EPSILON);
  const placed = points.map((point) => point.map((value, axis) => (value - min[axis]) * scale));

  const buffer = new ArrayBuffer(84 + triangles.length * 50);
  const stl = new DataView(buffer);
  stl.setUint32(80, triangles.length, true);
  triangles.forEach((triangle, index) => {
    const [a, b, c] = triangle.map((i) => placed[i]);
    const u = b.map((value, axis) => value - a[axis]);
    const w = c.map((value, axis) => value - a[axis]);
    const normal = [u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]];
    const length = Math.hypot(...normal) || 1;
    [...normal.map((value) => value / length), ...a, ...b, ...c].forEach((value, i) => {
      stl.setFloat32(84 + index * 50 + i * 4, value, true);
    });
  });
  return buffer;
}
