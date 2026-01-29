# Unblocker Plugin

The `unblocker` plugin allows specific clients to bypass DNS blocking by checking them against an allowlist of IP addresses, MAC addresses, or hostnames.

## Syntax

```
unblocker [ALLOWLIST_FILE]
```

- **ALLOWLIST_FILE**: Path to a file containing allowed clients (one per line). If omitted, the plugin passes all requests through unchanged.

## Allowlist File Format

The allowlist file supports three types of entries:
- **IP addresses**: `192.168.1.100`
- **MAC addresses**: `aa:bb:cc:dd:ee:ff` or `AA-BB-CC-DD-EE-FF`
- **Hostnames**: `mydevice.local` or `laptop.example.com`

Lines starting with `#` are treated as comments. Empty lines are ignored.

### Example Allowlist File

```
# Admin devices
192.168.1.10
192.168.1.11

# Kids devices (bypass blocking)
aa:bb:cc:dd:ee:ff
laptop.local
tablet.home

# Guest network
10.0.2.50
```

## Plugin Execution Order

The `unblocker` plugin should be placed **before** the `blocker` plugin in the plugin chain:

```
.:53 {
    metadata
    prometheus
    log
    omada { ... }
    unblocker /etc/coredns/allowlist.txt
    blocker /var/lib/coredns/blocklist.txt 1h hosts empty
    forward . 8.8.8.8
}
```

## How It Works

1. When a DNS query arrives, `unblocker` checks if the client is in the allowlist
2. **If allowed**: The request bypasses the blocker plugin entirely
3. **If not allowed**: The request continues to the blocker plugin for filtering

The plugin checks (in order):
1. Client IP address
2. Client MAC address (from metadata if available)
3. Client hostname (from reverse DNS or metadata)

## Metadata Support

The plugin can read MAC addresses and hostnames from metadata set by other plugins:
- `unblocker/mac`: MAC address
- `unblocker/hostname`: Hostname

This allows integration with the `omada` plugin or DHCP metadata.

## Examples

### Basic Usage

```
unblocker /etc/coredns/allowlist.txt
```

### No Filtering (Pass-through Mode)

```
unblocker
```

### Full Corefile Example

```
.:53 {
    metadata
    prometheus :9153
    log
    
    omada {
        controller_url https://192.168.1.1:8043
        site Default
        username admin
        password secret
    }
    
    unblocker /etc/coredns/allowlist.txt
    blocker /var/lib/coredns/blocklist.txt 1h hosts empty
    
    forward . 8.8.8.8 1.1.1.1
}
```

## Updating the Allowlist

The allowlist is loaded when CoreDNS starts. To update it:
1. Edit the allowlist file
2. Reload CoreDNS (send `SIGUSR1` or restart container)

## Notes

- IP matching is exact (no CIDR support currently)
- Hostnames are case-insensitive
- MAC addresses are case-insensitive and support both `:` and `-` separators
