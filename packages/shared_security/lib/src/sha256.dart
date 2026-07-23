import 'dart:async';
import 'dart:io';

const _mask32 = 0xffffffff;

const _k = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

class Sha256Hasher {
  final List<int> _h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  final List<int> _buffer = <int>[];
  var _lengthInBytes = 0;
  var _closed = false;

  void add(List<int> data) {
    if (_closed) {
      throw StateError('SHA-256 hasher is already closed.');
    }
    if (data.isEmpty) {
      return;
    }

    _lengthInBytes += data.length;
    var offset = 0;

    if (_buffer.isNotEmpty) {
      final needed = 64 - _buffer.length;
      final copied = needed < data.length ? needed : data.length;
      _buffer.addAll(data.take(copied));
      offset += copied;
      if (_buffer.length == 64) {
        _processBlock(_buffer, 0);
        _buffer.clear();
      }
    }

    while (offset + 64 <= data.length) {
      _processBlock(data, offset);
      offset += 64;
    }

    if (offset < data.length) {
      _buffer.addAll(data.skip(offset));
    }
  }

  String close() {
    if (_closed) {
      throw StateError('SHA-256 hasher is already closed.');
    }
    _closed = true;

    final bitLength = _lengthInBytes * 8;
    _buffer.add(0x80);
    while (_buffer.length % 64 != 56) {
      _buffer.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      _buffer.add((bitLength >> shift) & 0xff);
    }

    for (var offset = 0; offset < _buffer.length; offset += 64) {
      _processBlock(_buffer, offset);
    }

    final output = StringBuffer();
    for (final word in _h) {
      output.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return output.toString();
  }

  void _processBlock(List<int> bytes, int offset) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i += 1) {
      final base = offset + (i * 4);
      w[i] = ((bytes[base] << 24) |
              (bytes[base + 1] << 16) |
              (bytes[base + 2] << 8) |
              bytes[base + 3]) &
          _mask32;
    }
    for (var i = 16; i < 64; i += 1) {
      w[i] = (_smallSigma1(w[i - 2]) +
              w[i - 7] +
              _smallSigma0(w[i - 15]) +
              w[i - 16]) &
          _mask32;
    }

    var a = _h[0];
    var b = _h[1];
    var c = _h[2];
    var d = _h[3];
    var e = _h[4];
    var f = _h[5];
    var g = _h[6];
    var h = _h[7];

    for (var i = 0; i < 64; i += 1) {
      final t1 = (h + _bigSigma1(e) + _choice(e, f, g) + _k[i] + w[i]) &
          _mask32;
      final t2 = (_bigSigma0(a) + _majority(a, b, c)) & _mask32;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _mask32;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask32;
    }

    _h[0] = (_h[0] + a) & _mask32;
    _h[1] = (_h[1] + b) & _mask32;
    _h[2] = (_h[2] + c) & _mask32;
    _h[3] = (_h[3] + d) & _mask32;
    _h[4] = (_h[4] + e) & _mask32;
    _h[5] = (_h[5] + f) & _mask32;
    _h[6] = (_h[6] + g) & _mask32;
    _h[7] = (_h[7] + h) & _mask32;
  }
}

Future<String> sha256OfStream(Stream<List<int>> stream) async {
  final hasher = Sha256Hasher();
  await for (final chunk in stream) {
    hasher.add(chunk);
  }
  return hasher.close();
}

Future<String> sha256OfFile(File file) => sha256OfStream(file.openRead());

String sha256OfBytes(List<int> bytes) {
  final hasher = Sha256Hasher()..add(bytes);
  return hasher.close();
}

int _rightRotate(int value, int bits) {
  return ((value >> bits) | (value << (32 - bits))) & _mask32;
}

int _bigSigma0(int value) {
  return _rightRotate(value, 2) ^ _rightRotate(value, 13) ^ _rightRotate(value, 22);
}

int _bigSigma1(int value) {
  return _rightRotate(value, 6) ^ _rightRotate(value, 11) ^ _rightRotate(value, 25);
}

int _smallSigma0(int value) {
  return _rightRotate(value, 7) ^ _rightRotate(value, 18) ^ (value >> 3);
}

int _smallSigma1(int value) {
  return _rightRotate(value, 17) ^ _rightRotate(value, 19) ^ (value >> 10);
}

int _choice(int x, int y, int z) {
  return (x & y) ^ (((~x) & _mask32) & z);
}

int _majority(int x, int y, int z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

