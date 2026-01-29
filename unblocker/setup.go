package unblocker

import (
	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/plugin"
)

func init() {
	plugin.Register("unblocker", setup)
}

func setup(c *caddy.Controller) error {
	u, err := parseUnblocker(c)
	if err != nil {
		return plugin.Error("unblocker", err)
	}

	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		u.Next = next
		return u
	})

	return nil
}

func parseUnblocker(c *caddy.Controller) (*Unblocker, error) {
	u := &Unblocker{
		allowlistPath: "",
	}

	for c.Next() {
		args := c.RemainingArgs()
		
		if len(args) == 0 {
			// No allowlist file specified - unblocker is disabled, just pass through
			u.allowlistPath = ""
			return u, nil
		}

		if len(args) > 1 {
			return nil, c.ArgErr()
		}

		u.allowlistPath = args[0]
	}

	// Load allowlist if path is specified
	if u.allowlistPath != "" {
		if err := u.loadAllowlist(); err != nil {
			return nil, err
		}
	}

	return u, nil
}
