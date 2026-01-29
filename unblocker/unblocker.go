package unblocker

import (
	"context"
	"net"
	"strings"

	"github.com/coredns/coredns/plugin"
	"github.com/coredns/coredns/plugin/metadata"
	"github.com/coredns/coredns/request"

	"github.com/miekg/dns"
)

// Unblocker is a plugin that allows specific clients to bypass the blocker plugin
type Unblocker struct {
	Next          plugin.Handler
	allowlistPath string
	allowedIPs    map[string]bool
	allowedMACs   map[string]bool
	allowedNames  map[string]bool
}

// ServeDNS implements the plugin.Handler interface
func (u *Unblocker) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
	// If no allowlist configured, just pass through
	if u.allowlistPath == "" {
		return plugin.NextOrFailure(u.Name(), u.Next, ctx, w, r)
	}

	// Check if client should bypass blocking
	if u.isAllowed(ctx, w, r) {
		// Skip blocker by going to next plugin
		return plugin.NextOrFailure(u.Name(), u.Next, ctx, w, r)
	}

	// Not allowed, continue to blocker
	return plugin.NextOrFailure(u.Name(), u.Next, ctx, w, r)
}

// isAllowed checks if the client IP, MAC, or hostname is in the allowlist
func (u *Unblocker) isAllowed(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) bool {
	state := request.Request{W: w, Req: r}

	// Check client IP
	clientIP := state.IP()
	if u.allowedIPs[clientIP] {
		return true
	}

	// Check for metadata (MAC address from DHCP or other sources)
	if md := metadata.ValueFunc(ctx, "unblocker/mac"); md != nil {
		if macStr, ok := md.(string); ok {
			if u.allowedMACs[strings.ToLower(macStr)] {
				return true
			}
		}
	}

	// Check hostname from reverse DNS or omada plugin metadata
	if hostname := u.getClientHostname(ctx, clientIP); hostname != "" {
		if u.allowedNames[strings.ToLower(hostname)] {
			return true
		}
	}

	return false
}

// getClientHostname attempts to get hostname from metadata or reverse DNS
func (u *Unblocker) getClientHostname(ctx context.Context, ip string) string {
	// Try metadata first (set by omada plugin or other sources)
	if md := metadata.ValueFunc(ctx, "unblocker/hostname"); md != nil {
		if hostname, ok := md.(string); ok {
			return hostname
		}
	}

	// Fallback to reverse DNS lookup
	if names, err := net.LookupAddr(ip); err == nil && len(names) > 0 {
		return strings.TrimSuffix(names[0], ".")
	}

	return ""
}

// Name implements the plugin.Handler interface
func (u *Unblocker) Name() string {
	return "unblocker"
}
