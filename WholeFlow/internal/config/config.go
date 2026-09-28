// Package config loads application settings from the environment, an optional
// .env file, and (for the Tally port) TallyPrime's own tally.ini.
package config

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	TallyHost string
	TallyPort int
	// PortSource explains where TallyPort came from, e.g. "TALLY_PORT env" or
	// "C:\Program Files\TallyPrime\tally.ini". Shown on the status page.
	PortSource string
	// TallyINI holds what we could read from tally.ini (nil if not found).
	TallyINI *TallyINI

	TallyTimeout   time.Duration
	DefaultCompany string
	ShopGroups     []string
	// SupplierGroups are the Tally groups whose ledgers are suppliers.
	SupplierGroups []string

	ListenAddr string
	LogDir     string
	// DebugRaw stores every raw Tally XML response under LogDir/raw.
	// Responses contain accounting data, so keep this off outside development.
	DebugRaw bool

	Warnings []string
}

// TallyINI is the subset of tally.ini relevant to the HTTP/XML server.
type TallyINI struct {
	Path         string
	ServerPort   int
	ClientServer string // "Server", "Client", "Both", "None"
	ODBCEnabled  string
}

var defaultINIPaths = []string{
	`C:\Program Files\TallyPrime\tally.ini`,
	`C:\Program Files (x86)\TallyPrime\tally.ini`,
	`C:\TallyPrime\tally.ini`,
}

// Load reads .env (without overriding real environment variables) and builds the config.
func Load() (*Config, error) {
	loadDotEnv(".env")

	c := &Config{
		TallyHost:      env("TALLY_HOST", "localhost"),
		DefaultCompany: env("TALLY_COMPANY", ""),
		ListenAddr:     env("APP_ADDR", "127.0.0.1:8080"),
		LogDir:         env("LOG_DIR", "logs"),
		DebugRaw:       envBool("TALLY_DEBUG_RAW", false),
	}

	secs, err := strconv.Atoi(env("TALLY_TIMEOUT_SECONDS", "30"))
	if err != nil || secs <= 0 {
		return nil, fmt.Errorf("TALLY_TIMEOUT_SECONDS must be a positive integer")
	}
	c.TallyTimeout = time.Duration(secs) * time.Second

	for _, g := range strings.Split(env("SHOP_GROUPS", "Sundry Debtors"), ",") {
		if g = strings.TrimSpace(g); g != "" {
			c.ShopGroups = append(c.ShopGroups, g)
		}
	}
	if len(c.ShopGroups) == 0 {
		return nil, fmt.Errorf("SHOP_GROUPS must name at least one Tally group")
	}

	for _, g := range strings.Split(env("SUPPLIER_GROUPS", "Sundry Creditors"), ",") {
		if g = strings.TrimSpace(g); g != "" {
			c.SupplierGroups = append(c.SupplierGroups, g)
		}
	}

	c.TallyINI = findTallyINI(os.Getenv("TALLY_INI"))

	if p := os.Getenv("TALLY_PORT"); p != "" {
		port, err := strconv.Atoi(p)
		if err != nil || port <= 0 || port > 65535 {
			return nil, fmt.Errorf("TALLY_PORT %q is not a valid port", p)
		}
		c.TallyPort, c.PortSource = port, "TALLY_PORT setting"
		if c.TallyINI != nil && c.TallyINI.ServerPort != 0 && c.TallyINI.ServerPort != port {
			c.Warnings = append(c.Warnings, fmt.Sprintf(
				"TALLY_PORT=%d differs from ServerPort=%d in %s", port, c.TallyINI.ServerPort, c.TallyINI.Path))
		}
	} else if c.TallyINI != nil && c.TallyINI.ServerPort != 0 {
		c.TallyPort, c.PortSource = c.TallyINI.ServerPort, c.TallyINI.Path
	} else {
		// 9000 is TallyPrime's factory default; flag loudly that it is a guess.
		c.TallyPort, c.PortSource = 9000, "TallyPrime default (tally.ini not found; set TALLY_PORT)"
		c.Warnings = append(c.Warnings, "Tally port not configured and tally.ini not found; assuming 9000")
	}

	if c.TallyINI != nil {
		switch strings.ToLower(c.TallyINI.ClientServer) {
		case "server", "both", "":
		default:
			c.Warnings = append(c.Warnings, fmt.Sprintf(
				"tally.ini has 'Client Server=%s'; TallyPrime must act as Server (or Both) for data access",
				c.TallyINI.ClientServer))
		}
	}
	return c, nil
}

func findTallyINI(explicit string) *TallyINI {
	paths := defaultINIPaths
	if explicit != "" {
		paths = []string{explicit}
	}
	for _, p := range paths {
		if ini, err := parseTallyINI(p); err == nil {
			return ini
		}
	}
	return nil
}

func parseTallyINI(path string) (*TallyINI, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	ini := &TallyINI{Path: path}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "[") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		// Tally is inconsistent about spacing in keys ("ServerPort" vs "Server Port").
		key := strings.ToLower(strings.ReplaceAll(k, " ", ""))
		v = strings.TrimSpace(v)
		switch key {
		case "serverport":
			if n, err := strconv.Atoi(v); err == nil {
				ini.ServerPort = n
			}
		case "clientserver":
			ini.ClientServer = v
		case "enableodbcserver":
			ini.ODBCEnabled = v
		}
	}
	return ini, sc.Err()
}

// LoadDotEnv reads KEY=value lines from path into the environment without
// overriding variables that are already set. Missing files are ignored. The
// sync service uses it to read .env from its data directory and the
// executable's directory, whatever the working directory is.
func LoadDotEnv(path string) { loadDotEnv(path) }

func loadDotEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k = strings.TrimSpace(k)
		v = strings.Trim(strings.TrimSpace(v), `"'`)
		if _, exists := os.LookupEnv(k); !exists {
			os.Setenv(k, v)
		}
	}
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	switch strings.ToLower(env(key, "")) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	}
	return def
}
