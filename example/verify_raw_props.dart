import 'dart:typed_data';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;

void main() async {
  print('=== VERIFICACIÓN 1: ORIGEN CRUDO DE PROPIEDADES EN PROTOBUF ===');
  const url =
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles';

  final archive = await PmTilesArchive.from(url);
  // Wellington tile: zoom 14, x 16146, y 10258
  final tileId = ZXY(14, 16146, 10258).toTileId();
  final tile = await archive.tile(tileId);
  final rawBytes = Uint8List.fromList(tile.bytes());

  print('1. Tamaño del tile crudo descomprimido: ${rawBytes.length} bytes');

  // Decodificación directa del buffer Protobuf (sin capas intermedias de abstracción)
  final protoTile = raw.VectorTile.fromBuffer(rawBytes);
  print('2. Capas en el Protobuf: ${protoTile.layers.map((l) => l.name).toList()}');

  final protoLayer = protoTile.layers.first;
  print('3. Keys en el diccionario del tile: ${protoLayer.keys}');
  print('4. Total de features en el tile: ${protoLayer.features.length}');

  // Feature 0
  final f0 = protoLayer.features.first;
  print('\n5. Tags crudos del Feature 0 (pares key_index : value_index):');
  print('   ${f0.tags}');

  print('\n6. Mapeo crudo tags -> valores en el diccionario del Protobuf:');
  for (var i = 0; i < f0.tags.length; i += 2) {
    final keyIdx = f0.tags[i];
    final valIdx = f0.tags[i + 1];
    final key = protoLayer.keys[keyIdx];
    final rawVal = protoLayer.values[valIdx];
    print('   [$keyIdx:$valIdx] "$key" => string_val="${rawVal.stringValue}", int_val="${rawVal.intValue}"');
  }
}
