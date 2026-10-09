package auth

import (
	"net"
	"net/http"
	"strings"
)

// ClientIP is the address a request came from. X-Real-IP (set by nginx in
// front of the WholeFlow services) is trusted only when the connection
// itself comes from this machine (loopback); anyone else could put any
// address in it to dodge the sign-in limits.
func ClientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if peer := net.ParseIP(host); peer != nil && peer.IsLoopback() {
		if ip := net.ParseIP(strings.TrimSpace(r.Header.Get("X-Real-IP"))); ip != nil {
			return ip.String()
		}
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.String()
	}
	return host
}

// IPKey is the rate-limit key of an address: IPv4 as it is, IPv6 by its /64
// (one customer usually gets a whole /64, so per-address limits on IPv6
// would be easy to sidestep).
func IPKey(ip string) string {
	p := net.ParseIP(ip)
	if p == nil {
		return ip
	}
	if v4 := p.To4(); v4 != nil {
		return v4.String()
	}
	return p.Mask(net.CIDRMask(64, 128)).String() + "/64"
}
