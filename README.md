# CoreDNS Cybertron

Custom CoreDNS server combining [TP-Link Omada network device resolution](https://github.com/dougbw/coredns_omada) with [DNS-based ad blocking](https://github.com/icyflame/blocker).

## Features

- **Local Device DNS**: Automatically resolves DNS for devices on your TP-Link Omada network
  - DHCP clients, reservations, and network devices (APs, switches, gateways)
  - No manual DNS record management needed
  
- **Ad Blocking**: Blocks ads, trackers, and malicious domains
  - Uses [StevenBlack unified hosts file](https://github.com/StevenBlack/hosts)
  - Updated hourly via automated sidecar container
  - ~150,000+ blocked domains
  
- **Smart Plugin Ordering**: Local devices bypass ad-blocking
  - Plugin execution: metadata → prometheus → log → omada → blocker → forward
  - Ensures your local network devices always resolve, even if on blocklists

## Quick Start

### 1. Create Configuration

Copy the example Corefile and customize it:

```bash
cp Corefile.example Corefile
```

Edit `Corefile` and update the Omada settings:

```
omada {
    controller_url https://YOUR_OMADA_IP:8043
    site YOUR_SITE_NAME
    username YOUR_USERNAME
    password YOUR_PASSWORD
    refresh_minutes 5
    refresh_login_hours 24
    resolve_clients true
    resolve_devices true
    resolve_dhcp_reservations true
}
```

### 2. Start with Docker Compose

```bash
docker compose up -d
```

This starts:
- CoreDNS server on port 53 (UDP/TCP)
- Prometheus metrics on port 9153
- Automatic hourly blocklist updates

### 3. Test DNS Resolution

```bash
# Test local device resolution (via omada plugin)
dig @localhost your-device.local

# Test blocked domain (via blocker plugin)
dig @localhost doubleclick.net

# Check metrics
curl http://localhost:9153/metrics | grep coredns
```

## Manual Build

### Prerequisites

- Docker with Buildx support
- For multi-platform builds: QEMU user-mode emulation

### Build Image

```bash
./scripts/build.sh
```

Or manually:

```bash
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --tag sekkyo/coredns_cybertron:latest \
    --load \
    .
```

### Verify Plugins

```bash
docker run --rm sekkyo/coredns_cybertron:latest -plugins
```

You should see both `omada` and `blocker` in the output.

## Configuration

### Corefile Options

#### Omada Plugin

```
omada {
    controller_url https://192.168.1.254:8043  # Omada controller URL
    site Default                               # Site name (or omit for first site)
    username admin                             # Controller username
    password secret                            # Controller password
    refresh_minutes 5                          # Zone refresh interval
    refresh_login_hours 24                     # Re-login interval
    resolve_clients true                       # Resolve DHCP clients
    resolve_devices true                       # Resolve network devices
    resolve_dhcp_reservations true             # Resolve DHCP reservations
}
```

#### Blocker Plugin

```
blocker <blocklist_file> <update_interval> <format> <response_type>
```

- `blocklist_file`: Path to blocklist file (e.g., `/var/lib/coredns/blocklist.txt`)
- `update_interval`: How often to check for file changes (e.g., `1h`, `30m`)
- `format`: `hosts` or `abp` (AdBlock Plus syntax)
- `response_type`: `empty` (0.0.0.0/::) or `nxdomain`

Example:
```
blocker /var/lib/coredns/blocklist.txt 1h hosts empty
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BLOCKLIST_PATH` | Path to blocklist file | `/var/lib/coredns/blocklist.txt` |

## Architecture

### Plugin Execution Order

The `plugin.cfg` defines the execution order:

1. **metadata** - Enables metadata for request tracking
2. **prometheus** - Metrics collection
3. **log** - Request logging
4. **omada** - Local device resolution (matches local devices first)
5. **blocker** - Ad/tracker blocking (only sees non-local requests)
6. **forward** - Upstream DNS forwarding

This order ensures local devices always resolve, even if they appear on blocklists.

### Multi-Stage Docker Build

The Dockerfile uses a multi-stage build:

1. **Builder stage**: Clones CoreDNS and plugins, modifies `plugin.cfg`, builds binary
2. **Runtime stage**: Minimal Debian-slim image with only the CoreDNS binary

### Blocklist Updates

The `blocklist-updater` sidecar container:
- Downloads StevenBlack hosts file hourly
- Writes to shared volume mounted by CoreDNS
- CoreDNS automatically reloads when file changes (based on `update_interval`)

## Monitoring

### Prometheus Metrics

Metrics are exposed on port 9153:

```bash
curl http://localhost:9153/metrics
```

Key metrics:
- `coredns_blocker_requests_blocked_total` - Total blocked requests
- `coredns_dns_request_duration_seconds` - Request latency
- `coredns_dns_requests_total` - Total DNS requests

### Logs

View logs:

```bash
docker compose logs -f coredns
```

Log format includes metadata showing blocked requests:
```
[INFO] 192.168.1.100 - "A IN doubleclick.net udp 41 false 512" NOERROR true
```

The last field indicates if the request was blocked.

## Troubleshooting

### Omada Connection Issues

Check Omada controller connectivity:

```bash
docker compose exec coredns curl -k https://YOUR_OMADA_IP:8043
```

Ensure:
- Controller URL is correct (include port, usually 8043)
- Username/password are correct
- User has at least viewer permissions
- Network connectivity from container to controller

### Blocklist Not Updating

Check updater logs:

```bash
docker compose logs -f blocklist-updater
```

Verify blocklist file:

```bash
docker compose exec coredns wc -l /var/lib/coredns/blocklist.txt
```

Should show ~150,000+ lines for StevenBlack unified hosts.

### DNS Resolution Issues

Test plugin order:

```bash
# Should resolve (local device)
dig @localhost gateway.local

# Should be blocked (ad domain)
dig @localhost ads.example.com

# Should resolve (legitimate domain)
dig @localhost github.com
```

Check CoreDNS health:

```bash
docker compose exec coredns /usr/local/bin/coredns -health
```

## QNAP QuTS Deployment

### Prerequisites

- QNAP NAS running QuTS or QTS
- Container Station installed
- SSH access to QNAP (optional, for command line setup)

### Deployment Steps

#### Option 1: Container Station GUI

1. **Open Container Station** and click **Create Container**

2. **Configure Container**:
   - **Image**: `ghcr.io/sekkyo/coredns_cybertron:latest`
   - **Name**: `coredns_cybertron`
   - **Network Mode**: Bridge (or custom network)

3. **Port Mappings**:
   - `53:53/UDP` (DNS)
   - `53:53/TCP` (DNS over TCP)
   - `9153:9153/TCP` (Metrics)

4. **Volume Bindings**:
   - Create a shared folder for config: `/share/Container/coredns/`
   - Mount `/share/Container/coredns/Corefile` → `/etc/coredns/Corefile`
   - Create volume `blocklist-data` for blocklist storage

5. **Create Blocklist Updater Container**:
   - **Image**: `curlimages/curl:latest`
   - **Name**: `blocklist_updater`
   - **Command**: 
     ```
     sh -c "while true; do curl -sSL -f -o /data/blocklist.txt https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts && sleep 3600; done"
     ```
   - **Volume**: Same `blocklist-data` volume mounted to `/data`

#### Option 2: SSH/Command Line

1. **SSH into QNAP**:
   ```bash
   ssh admin@your-qnap-ip
   ```

2. **Create directories**:
   ```bash
   mkdir -p /share/Container/coredns
   cd /share/Container/coredns
   ```

3. **Download files**:
   ```bash
   wget https://raw.githubusercontent.com/Sekkyo/coredns_cybertron/main/docker-compose.yml
   wget https://raw.githubusercontent.com/Sekkyo/coredns_cybertron/main/Corefile.example
   cp Corefile.example Corefile
   ```

4. **Edit Corefile** with your Omada settings:
   ```bash
   vi Corefile
   ```

5. **Start with Docker Compose**:
   ```bash
   docker-compose up -d
   ```

### Network Configuration

#### Making QNAP Use CoreDNS as System DNS

1. Go to **Control Panel** → **Network & File Services** → **Network**
2. Under **TCP/IP**, click **Edit**
3. Set **DNS Server** to:
   - Primary: `127.0.0.1` (localhost)
   - Secondary: `1.1.1.1` (fallback)

#### Configuring DHCP Server (if using QNAP as DHCP server)

1. Go to **DHCP Server** settings
2. Set DNS server option to QNAP's IP address
3. Clients will now use CoreDNS for resolution

### QNAP-Specific Considerations

- **Port Conflicts**: QNAP uses port 53 for the `dnsmasq` proxy. Disable it in **Network Services** or use a different port mapping (e.g., `1053`)
- **Auto-Start**: Enable "Auto-restart" in Container Station for both containers
- **Resource Limits**: Set appropriate CPU/memory limits (512MB RAM recommended)
- **Firewall**: Ensure port 53 (UDP/TCP) is accessible from your network
- **Persistence**: Use QNAP's shared folders for volumes to survive reboots

### Verification

```bash
# Test from QNAP shell
nslookup github.com localhost

# Test from network client
nslookup github.com your-qnap-ip

# Check container logs
docker logs coredns_cybertron
docker logs blocklist_updater
```

### Performance Notes

CoreDNS is lightweight and runs well on QNAP devices. Expected resource usage:
- **Memory**: ~50-100MB
- **CPU**: <1% idle, <5% under load
- **Storage**: ~20MB blocklist file

## Advanced Usage

### Custom Blocklists

Replace StevenBlack with your own blocklist:

1. Edit `docker-compose.yml` and change the URL in `blocklist-init` and `blocklist-updater`
2. Ensure format matches the Corefile setting (`hosts` or `abp`)

### Multiple DNS Zones

Add multiple server blocks in Corefile:

```
local:53 {
    omada { ... }
    forward . 192.168.1.1
}

.:53 {
    blocker /var/lib/coredns/blocklist.txt 1h hosts empty
    forward . 8.8.8.8
}
```

### Kubernetes Deployment

See [kubernetes/](kubernetes/) directory for example manifests (TODO).

## License

This project combines:
- [CoreDNS](https://github.com/coredns/coredns) - Apache 2.0
- [coredns_omada](https://github.com/dougbw/coredns_omada) - Apache 2.0
- [blocker](https://github.com/icyflame/blocker) - MIT

See individual project licenses for details.

## Contributing

Contributions welcome! Please open an issue or PR.

## Support

- [CoreDNS Documentation](https://coredns.io/manual/toc/)
- [Omada Plugin Docs](https://github.com/dougbw/coredns_omada)
- [Blocker Plugin Docs](https://github.com/icyflame/blocker)
