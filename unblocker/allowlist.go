package unblocker

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"strings"
)

// loadAllowlist reads the allowlist file and populates the allowed IPs, MACs, and names
func (u *Unblocker) loadAllowlist() error {
	u.allowedIPs = make(map[string]bool)
	u.allowedMACs = make(map[string]bool)
	u.allowedNames = make(map[string]bool)

	file, err := os.Open(u.allowlistPath)
	if err != nil {
		return fmt.Errorf("failed to open allowlist file %s: %w", u.allowlistPath, err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	lineNum := 0

	for scanner.Scan() {
		lineNum++
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Determine entry type and add to appropriate map
		if ip := net.ParseIP(line); ip != nil {
			// Valid IP address
			u.allowedIPs[line] = true
		} else if isMACAddress(line) {
			// MAC address
			u.allowedMACs[strings.ToLower(line)] = true
		} else {
			// Assume it's a hostname/DNS name
			u.allowedNames[strings.ToLower(line)] = true
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading allowlist file: %w", err)
	}

	return nil
}

// isMACAddress checks if a string is a valid MAC address
func isMACAddress(s string) bool {
	// MAC addresses are typically in format: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX
	_, err := net.ParseMAC(s)
	return err == nil
}
