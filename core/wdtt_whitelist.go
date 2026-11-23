package core

import (
	"embed"
	"errors"
	"io"
	"io/fs"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/rules"
	RP "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
)

const wdttWhitelistName = "FlClash WDTT whitelist"
const wdttWhitelistURL = "https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt"
const wdttWhitelistLimit = 1 << 20

//go:embed data/wdtt-whitelist.txt
var wdttWhitelistBundle embed.FS

type wdttWhitelistVehicle struct{ P.Vehicle }

func validWdttWhitelist(buf []byte) bool {
	if len(buf) == 0 || len(buf) > wdttWhitelistLimit {
		return false
	}
	count := 0
	for line := range strings.SplitSeq(string(buf), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if len(line) > 253 || !strings.Contains(line, ".") {
			return false
		}
		if _, err := netip.ParseAddr(line); err == nil {
			return false
		}
		for label := range strings.SplitSeq(line, ".") {
			if len(label) == 0 || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
				return false
			}
			for _, char := range label {
				if !(char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || char == '-') {
					return false
				}
			}
		}
		count++
	}
	return count > 0
}

func (v *wdttWhitelistVehicle) Write(buf []byte) error {
	if !validWdttWhitelist(buf) {
		return errors.New("invalid WDTT whitelist: expected a non-empty domain list")
	}
	path := v.Path()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".wdtt-whitelist-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(buf); err != nil {
		_ = file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

type wdttWhitelistProvider struct {
	*RP.RuleSetProvider
	vehicle *wdttWhitelistVehicle
}

func (p *wdttWhitelistProvider) Initial() error {
	if buf, err := os.ReadFile(p.vehicle.Path()); err == nil && !validWdttWhitelist(buf) {
		seed, err := wdttWhitelistBundle.ReadFile("data/wdtt-whitelist.txt")
		if err != nil {
			return err
		}
		if err = p.vehicle.Write(seed); err != nil {
			return err
		}
		_ = os.Chtimes(p.vehicle.Path(), time.Unix(0, 0), time.Unix(0, 0))
	}
	return p.RuleSetProvider.Initial()
}

func installWdttWhitelist(cfg *config.Config) {
	original := cfg.RuleProviders[wdttWhitelistName]
	source, ok := original.(interface{ Vehicle() P.Vehicle })
	if !ok || source.Vehicle().Url() != wdttWhitelistURL || original.Behavior() != P.Domain {
		return
	}
	vehicle := &wdttWhitelistVehicle{resource.NewHTTPVehicle(
		wdttWhitelistURL, source.Vehicle().Path(), "", nil, resource.DefaultHttpTimeout, wdttWhitelistLimit+1,
	)}
	seed, _ := wdttWhitelistBundle.ReadFile("data/wdtt-whitelist.txt")
	provider := RP.NewRuleSetProvider(
		wdttWhitelistName, P.Domain, P.TextRule, 24*time.Hour, vehicle,
		strings.Split(strings.TrimSpace(string(seed)), "\n"),
		func() (fs.File, error) { return wdttWhitelistBundle.Open("data/wdtt-whitelist.txt") }, rules.ParseRule,
	)
	if closer, ok := original.(io.Closer); ok {
		_ = closer.Close()
	}
	cfg.RuleProviders[wdttWhitelistName] = &wdttWhitelistProvider{provider.(*RP.RuleSetProvider), vehicle}
}

func wdttRoutingTarget() string {
	for name, proxy := range tunnel.AllProxies() {
		if !strings.HasPrefix(name, "VLESS / WDTT [") {
			continue
		}
		for depth := 0; proxy != nil && depth < 8; depth++ {
			if proxy.Type() == constant.Rematch {
				return proxy.Name()
			}
			proxy = proxy.Unwrap(nil, false)
		}
	}
	return ""
}
