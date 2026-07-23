import 'dart:convert';
import 'dart:io';

import 'package:shared_models/shared_models.dart';
import 'package:shared_storage/shared_storage.dart';

import '../settings/app_data_paths.dart';

class PairedDeviceRepository {
  PairedDeviceRepository({String? appDataPath})
      : _file = File(joinPath(AppDataPaths.root(overridePath: appDataPath), 'paired_devices.json'));

  final File _file;

  Future<List<PairedDevice>> load() async {
    if (!await _file.exists()) {
      return <PairedDevice>[];
    }

    final decoded = jsonDecode(await _file.readAsString());
    if (decoded is! List) {
      return <PairedDevice>[];
    }

    return decoded
        .whereType<Map>()
        .map((entry) => PairedDevice.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  Future<void> save(List<PairedDevice> devices) async {
    await _file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _file.writeAsString(
      encoder.convert(devices.map((device) => device.toJson()).toList()),
    );
  }
}