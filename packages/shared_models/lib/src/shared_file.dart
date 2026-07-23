class SharedFile {
  const SharedFile({
    required this.id,
    required this.uri,
    required this.fileName,
    required this.mimeType,
    this.size,
  });

  final String id;
  final String uri;
  final String fileName;
  final String mimeType;
  final int? size;

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      id: json['id'] as String,
      uri: json['uri'] as String,
      fileName: json['fileName'] as String,
      mimeType: json['mimeType'] as String,
      size: json['size'] as int?,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'uri': uri,
      'fileName': fileName,
      'mimeType': mimeType,
      'size': size,
    };
  }
}

