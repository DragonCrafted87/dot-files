Morning checks, in order:

```sh
ip route
ip rule
ping -c2 9.9.9.9
nslookup example.com 192.168.0.1
nslookup -type=A prayers.stealthdragonland.net 192.168.0.1
nslookup -type=AAAA prayers.stealthdragonland.net 192.168.0.1
logread -e openvpn | tail -20
logread -e unbound | tail -20
```

Good:

- one default on `eth0`, `172.111.235.0/24` on `tun0`, no `0.0.0.0/1`
- `from 192.168.8.11 lookup 100` and same for `.41`
- ping works
- `example.com` has A records
- `prayers` A is `192.168.8.11`, AAAA is empty (no SERVFAIL)

Then from a phone: Wi‑Fi page and LTE page once each.

**Cloudflare forward** — only if the above is clean:

```sh
uci set unbound.fwd_cloudflare.enabled='0'
uci commit unbound
service unbound restart
nslookup example.com 192.168.0.1
```

That returns Unbound to recursing itself (via WAN). If `example.com` SERVFAILs or hangs, turn the forward back on:

```sh
uci set unbound.fwd_cloudflare.enabled='1'
uci commit unbound
service unbound restart
```

Recursion is nicer long-term; Cloudflare is the safer default if overnight DNS was the original failure mode. No rush to disable it the first good morning.
