/// Gateway protocol opcodes.
class GatewayOpcodes {
  static const int event = 0;
  static const int heartbeat = 1;
  static const int identify = 2;
  static const int resume = 3;
  static const int heartbeatAck = 4;
  static const int hello = 5;
  static const int reconnect = 6;
  static const int invalidSession = 7;
  static const int presenceUpdate = 8;
  static const int voiceStateUpdate = 9;
}
