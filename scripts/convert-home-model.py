"""Package the supplied single-mesh GLB as a textured USDZ using Apple's USD tools.
Usage: python3 scripts/convert-home-model.py input.glb output.usdz
The restricted input contract fails rather than silently discarding unsupported data.
"""
import json, pathlib, struct, subprocess, sys, tempfile
source, output = map(pathlib.Path, sys.argv[1:])
data = source.read_bytes()
magic, version, length = struct.unpack_from('<III', data)
assert magic == 0x46546C67 and version == 2 and length == len(data)
size, kind = struct.unpack_from('<II', data, 12)
assert kind == 0x4E4F534A
asset = json.loads(data[20:20+size])
bin_size, bin_kind = struct.unpack_from('<II', data, 20+size)
assert bin_kind == 0x004E4942
binary = data[28+size:28+size+bin_size]
assert len(asset['nodes']) == len(asset['meshes']) == len(asset['materials']) == 1
assert asset['nodes'][0] == {'mesh': 0, 'matrix': [1.,0.,0.,0.,0.,1.,0.,0.,0.,0.,1.,0.,0.,0.,0.,1.]}
assert not any(asset.get(k) for k in ['skins', 'animations', 'extensionsRequired'])
primitive, = asset['meshes'][0]['primitives']
assert primitive.get('mode', 4) == 4 and set(primitive['attributes']) == {'POSITION','NORMAL','TEXCOORD_0'}
material = asset['materials'][0]
assert material.get('alphaMode','OPAQUE') == 'OPAQUE' and not material.get('extensions')
pbr = material['pbrMetallicRoughness']
assert pbr['baseColorFactor'] == [1.,1.,1.,1.] and pbr['baseColorTexture'].get('texCoord',0) == 0
assert not any(material.get(k) for k in ['normalTexture','occlusionTexture','emissiveTexture'])
assert not pbr.get('metallicRoughnessTexture')
def read(index):
    a = asset['accessors'][index]; assert not a.get('sparse') and not a.get('normalized')
    v = asset['bufferViews'][a['bufferView']]; assert v['buffer'] == 0
    code = {5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']]
    count = {'SCALAR':1,'VEC2':2,'VEC3':3}[a['type']]
    fmt = '<'+code*count; stride = v.get('byteStride',struct.calcsize(fmt))
    start = v.get('byteOffset',0)+a.get('byteOffset',0)
    return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(a['count'])]
positions = read(primitive['attributes']['POSITION']); normals = read(primitive['attributes']['NORMAL'])
uv = [(u,1-v) for u,v in read(primitive['attributes']['TEXCOORD_0'])]
indices = [v[0] for v in read(primitive['indices'])]
assert len(indices)%3 == 0 and max(indices)<len(positions) and len(normals)==len(uv)==len(positions)
image = asset['images'][asset['textures'][pbr['baseColorTexture']['index']]['source']]
assert image['mimeType']=='image/jpeg'
v = asset['bufferViews'][image['bufferView']]; start=v.get('byteOffset',0)
def vectors(values): return '['+', '.join('('+', '.join(format(x,'.9g') for x in row)+')' for row in values)+']'
with tempfile.TemporaryDirectory(prefix='friday-model-') as directory:
    folder=pathlib.Path(directory)
    (folder/'albedo.jpg').write_bytes(binary[start:start+v['byteLength']])
    scene='''#usda 1.0
(defaultPrim = "HomeModel"\n metersPerUnit = 1\n upAxis = "Y")
def Xform "HomeModel" {
 def Mesh "Design" (prepend apiSchemas = ["MaterialBindingAPI"]) {
  uniform token subdivisionScheme = "none"
  uniform bool doubleSided = true
  rel material:binding = </HomeModel/Original>
'''
    scene+=f'  point3f[] points = {vectors(positions)}\n  normal3f[] normals = {vectors(normals)} (interpolation = "vertex")\n'
    scene+=f'  texCoord2f[] primvars:st = {vectors(uv)} (interpolation = "vertex")\n'
    scene+='  int[] faceVertexCounts = ['+', '.join(['3']*(len(indices)//3))+']\n'
    scene+='  int[] faceVertexIndices = '+json.dumps(indices)+'\n }\n'
    scene+=''' def Material "Original" {
  token outputs:surface.connect = </HomeModel/Original/Surface.outputs:surface>
  def Shader "Surface" {
   uniform token info:id = "UsdPreviewSurface"
   color3f inputs:diffuseColor.connect = </HomeModel/Original/Albedo.outputs:rgb>
'''
    scene+=f'   float inputs:metallic = {pbr["metallicFactor"]}\n   float inputs:roughness = {pbr["roughnessFactor"]}\n'
    scene+='''   token outputs:surface
  }
  def Shader "Albedo" {
   uniform token info:id = "UsdUVTexture"
   asset inputs:file = @albedo.jpg@
   token inputs:sourceColorSpace = "sRGB"
   token inputs:wrapS = "repeat"
   token inputs:wrapT = "repeat"
   float2 inputs:st.connect = </HomeModel/Original/UV.outputs:result>
   float3 outputs:rgb
  }
  def Shader "UV" {
   uniform token info:id = "UsdPrimvarReader_float2"
   string inputs:varname = "st"
   float2 outputs:result
  }
 }
}
'''
    (folder/'home.usda').write_text(scene)
    subprocess.run(['usdcat',str(folder/'home.usda'),'-o',str(folder/'home.usdc')],check=True)
    output.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run(['usdzip',str(output.resolve()),'home.usdc','albedo.jpg'],cwd=folder,check=True)
print(f'Packaged {len(positions)} vertices, {len(indices)//3} triangles, original JPEG and PBR settings: {output}')
