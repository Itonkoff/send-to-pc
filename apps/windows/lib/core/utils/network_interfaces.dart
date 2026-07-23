import 'dart:io';

class LocalIpv4Candidate {
  const LocalIpv4Candidate({
    required this.interfaceName,
    required this.address,
  });

  final String interfaceName;
  final String address;
}

Future<String> firstLocalIpv4Address() async {
  final addresses = await localIpv4Addresses();
  return addresses.isEmpty
      ? InternetAddress.loopbackIPv4.address
      : addresses.first;
}

Future<List<String>> localIpv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final candidates = <LocalIpv4Candidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) {
          candidates.add(
            LocalIpv4Candidate(
              interfaceName: interface.name,
              address: address.address,
            ),
          );
        }
      }
    }
    return sortedLocalIpv4Addresses(candidates);
  } on Object {
    return const <String>[];
  }
}

List<String> sortedLocalIpv4Addresses(Iterable<LocalIpv4Candidate> candidates) {
  final sorted = candidates
      .map((candidate) => (
            candidate: candidate,
            score: _candidateScore(candidate),
          ))
      .where((entry) => entry.score >= 0)
      .toList()
    ..sort((left, right) => right.score.compareTo(left.score));

  final addresses = <String>[];
  for (final entry in sorted) {
    if (!addresses.contains(entry.candidate.address)) {
      addresses.add(entry.candidate.address);
    }
  }
  return addresses;
}

String bestLocalIpv4Address(Iterable<LocalIpv4Candidate> candidates) {
  final addresses = sortedLocalIpv4Addresses(candidates);
  return addresses.isEmpty
      ? InternetAddress.loopbackIPv4.address
      : addresses.first;
}

int _candidateScore(LocalIpv4Candidate candidate) {
  if (!_isUsableIpv4(candidate.address)) {
    return -1000;
  }

  var score = 0;
  if (_isPrivateIpv4(candidate.address)) {
    score += 100;
  }
  if (!_isLikelyVirtualInterface(candidate.interfaceName)) {
    score += 80;
  }
  if (!_isWindowsSharedNetworkAddress(candidate.address)) {
    score += 25;
  }
  if (_isCommonHomeLan(candidate.address)) {
    score += 10;
  }
  return score;
}

bool _isUsableIpv4(String address) {
  final octets = _octets(address);
  if (octets == null) {
    return false;
  }
  return octets[0] != 0 &&
      octets[0] != 127 &&
      !(octets[0] == 169 && octets[1] == 254);
}

bool _isPrivateIpv4(String address) {
  final octets = _octets(address);
  if (octets == null) {
    return false;
  }
  return octets[0] == 10 ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
      (octets[0] == 192 && octets[1] == 168);
}

bool _isWindowsSharedNetworkAddress(String address) {
  return address.startsWith('192.168.137.');
}

bool _isCommonHomeLan(String address) {
  return address.startsWith('192.168.0.') || address.startsWith('192.168.1.');
}

bool _isLikelyVirtualInterface(String interfaceName) {
  final name = interfaceName.toLowerCase();
  const virtualMarkers = <String>[
    'bluetooth',
    'docker',
    'hyper-v',
    'loopback',
    'npcap',
    'tap',
    'tailscale',
    'vethernet',
    'virtual',
    'virtualbox',
    'vmware',
    'wintun',
    'wireguard',
    'wsl',
    'zerotier',
  ];
  return virtualMarkers.any(name.contains);
}

List<int>? _octets(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return null;
  }

  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return null;
    }
    octets.add(value);
  }
  return octets;
}