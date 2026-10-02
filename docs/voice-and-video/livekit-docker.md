# LiveKit media addresses behind Docker

The `chat.daccord.gg` voice investigation on 2026-10-02 reproduced intermittent
20-second joins to `wss://livekit.daccord.gg`. Six local joins succeeded; two of
four remote joins failed. Native WebRTC captured the Corsair VOID ELITE microphone
on the system default source. On the failed joins, the publisher connected but
the subscriber never completed ICE nomination.

The server advertised `172.20.0.5:7882/udp` and `172.20.0.5:7881/tcp`, its private
Docker bridge addresses. Public STUN candidates used changing ports; incoming
host-candidate checks got no responses, and successful public pairs remained
unnominated. The original Portainer stack started LiveKit with `--dev` behind a
bridge while publishing only TCP 7881 and UDP 7882.

A diagnostic client supplied the public address at those same media ports,
without changing the live server. All four remote joins then connected in
0.9–1.6 seconds.

The correction was deployed to Portainer environment 3, stack 2 (`daccord`), on
2026-10-02. Four subsequent joins without the diagnostic workaround connected
in 986–1241 ms, with no microphone errors. Both publisher and subscriber selected
`135.125.226.81:7882/udp` and completed ICE nomination. Human audible playback
still needs to be confirmed with another participant.

The installed Daccord app also joined successfully on the first attempt with
the microphone enabled and no LiveKit error. The temporary test join was left
after verification.

Use an explicit production configuration advertising the public host at the
published media ports. The configuration below is now deployed to the live service. See the server
[deployment guide](https://github.com/DaccordProject/accordserver/blob/master/docs/livekit-deployment.md)
for reusable Compose and Portainer instructions. The
live stack's existing network, credentials, and proxy labels were retained.

```yaml
livekit:
  image: livekit/livekit-server:latest
  networks: [daccord]
  command:
    - "--keys"
    - "${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"
  environment:
    LIVEKIT_CONFIG: |
      port: 7880
      rtc:
        node_ip: ${LIVEKIT_NODE_IP:-135.125.226.81}
        use_external_ip: false
        tcp_port: 7881
        udp_port: 7882
  ports:
    - "7881:7881/tcp"
    - "7882:7882/udp"
```

Set `LIVEKIT_NODE_IP` to the deployment's public IPv4. `use_external_ip: false`
allows that explicit address to take effect. Keep Caddy's existing upstream for
WebSocket signaling on port 7880, and allow TCP 7881 and UDP 7882 through the host
firewall. Redeploying LiveKit interrupts existing voice calls.

After redeployment, verify the advertised host candidates use the public IP and
ports 7881/7882. Repeat joins and channel switches, confirm both publisher and
subscriber ICE connections complete, and check microphone levels and audible
remote playback. A speaking avatar alone does not verify audio reception.

References: [LiveKit configuration](https://github.com/livekit/livekit/blob/master/config-sample.yaml),
[deployment](https://docs.livekit.io/transport/self-hosting/deployment/), and
[ports and firewall](https://docs.livekit.io/transport/self-hosting/ports-firewall/).
