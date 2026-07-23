import 'package:flutter_test/flutter_test.dart';
import 'package:send_to_pc_windows/core/utils/network_interfaces.dart';

void main() {
  test('prefers a real LAN adapter over Windows shared virtual network', () {
    final address = bestLocalIpv4Address(const [
      LocalIpv4Candidate(
        interfaceName: 'vEthernet (Default Switch)',
        address: '192.168.137.1',
      ),
      LocalIpv4Candidate(interfaceName: 'Wi-Fi', address: '192.168.1.24'),
    ]);

    expect(address, '192.168.1.24');
  });

  test('returns sorted usable addresses for QR host alternatives', () {
    final addresses = sortedLocalIpv4Addresses(const [
      LocalIpv4Candidate(
        interfaceName: 'vEthernet (KubernetesLab)',
        address: '192.168.137.1',
      ),
      LocalIpv4Candidate(interfaceName: 'Wi-Fi', address: '192.168.1.24'),
      LocalIpv4Candidate(
        interfaceName: 'vEthernet (Default Switch)',
        address: '172.20.208.1',
      ),
    ]);

    expect(addresses, ['192.168.1.24', '172.20.208.1', '192.168.137.1']);
  });

  test('uses the shared virtual network when it is the only candidate', () {
    final address = bestLocalIpv4Address(const [
      LocalIpv4Candidate(
        interfaceName: 'vEthernet (Default Switch)',
        address: '192.168.137.1',
      ),
    ]);

    expect(address, '192.168.137.1');
  });

  test('falls back to loopback when no usable adapter is available', () {
    final address = bestLocalIpv4Address(const [
      LocalIpv4Candidate(interfaceName: 'Wi-Fi', address: '169.254.10.20'),
    ]);

    expect(address, '127.0.0.1');
  });
}