package core

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/rules"
	RP "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func testWdttWhitelist(t *testing.T) *wdttWhitelistProvider {
	t.Helper()
	RP.SetTunnel(tunnel.Tunnel)
	path := filepath.Join(t.TempDir(), "white.txt")
	original := RP.NewRuleSetProvider(wdttWhitelistName, P.Domain, P.TextRule, 24*time.Hour,
		resource.NewHTTPVehicle(wdttWhitelistURL, path, "", nil, time.Second, wdttWhitelistLimit), nil, nil, rules.ParseRule)
	cfg := &config.Config{RuleProviders: map[string]P.RuleProvider{wdttWhitelistName: original}}
	installWdttWhitelist(cfg)
	p, ok := cfg.RuleProviders[wdttWhitelistName].(*wdttWhitelistProvider)
	if !ok {
		t.Fatal("managed provider was not installed")
	}
	t.Cleanup(func() { _ = p.Close() })
	return p
}

func TestWdttWhitelistRejectsMalformedUpdates(t *testing.T) {
	seed, err := wdttWhitelistBundle.ReadFile("data/wdtt-whitelist.txt")
	if err != nil || !validWdttWhitelist(seed) {
		t.Fatal("bundled whitelist is invalid", err)
	}
	for _, body := range []string{"", "# empty\n", "<html>blocked</html>", "*.ru", "+.ru", "*.test", "1.2.3.4", "valid.test\nMATCH,DIRECT", "bad/name.test", "bad_.test", strings.Repeat("a", wdttWhitelistLimit+1)} {
		if validWdttWhitelist([]byte(body)) {
			t.Errorf("accepted malformed body %.60q", body)
		}
	}
	p := testWdttWhitelist(t)
	if err := p.vehicle.Write([]byte("first.test\n")); err != nil {
		t.Fatal(err)
	}
	body := "second.test\n"
	status := http.StatusOK
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(status)
		_, _ = io.WriteString(w, body)
	}))
	defer server.Close()
	p.vehicle.Vehicle = resource.NewHTTPVehicle(server.URL, p.vehicle.Path(), "", nil, time.Second, wdttWhitelistLimit+1)
	if err := p.Initial(); err != nil {
		t.Fatal(err)
	}
	if !p.Match(&constant.Metadata{Host: "first.test"}, constant.RuleMatchHelper{}) {
		t.Fatal("cached list was not loaded")
	}
	if err := p.Update(); err != nil {
		t.Fatal(err)
	}
	if p.Match(&constant.Metadata{Host: "first.test"}, constant.RuleMatchHelper{}) || !p.Match(&constant.Metadata{Host: "second.test"}, constant.RuleMatchHelper{}) {
		t.Fatal("successful update did not replace matches")
	}
	for _, invalid := range []string{"", "<html>bad</html>", "valid.test\nMATCH,DIRECT"} {
		body = invalid
		if err := p.Update(); err == nil {
			t.Errorf("invalid update %q succeeded", invalid)
		}
		buf, _ := os.ReadFile(p.vehicle.Path())
		if !bytes.Equal(buf, []byte("second.test\n")) || !p.Match(&constant.Metadata{Host: "second.test"}, constant.RuleMatchHelper{}) {
			t.Fatal("invalid update replaced the last working copy")
		}
	}
	status = http.StatusServiceUnavailable
	if err := p.Update(); err == nil {
		t.Fatal("HTTP failure succeeded")
	}
}

func TestWdttWhitelistStartsOfflineAndRecoversInvalidCache(t *testing.T) {
	for _, corrupt := range []bool{false, true} {
		t.Run(fmt.Sprint(corrupt), func(t *testing.T) {
			p := testWdttWhitelist(t)
			if corrupt {
				if err := os.WriteFile(p.vehicle.Path(), []byte("<html>bad cache</html>"), 0o600); err != nil {
					t.Fatal(err)
				}
			}
			p.vehicle.Vehicle = resource.NewHTTPVehicle("http://127.0.0.1:0", p.vehicle.Path(), "", nil, time.Millisecond, wdttWhitelistLimit+1)
			if err := p.Initial(); err != nil || p.Count() == 0 {
				t.Fatal("offline startup lost bundled rules", err)
			}
			if !p.Match(&constant.Metadata{Host: "gosuslugi.ru"}, constant.RuleMatchHelper{}) {
				t.Fatal("bundled domain did not match")
			}
			if p.Match(&constant.Metadata{Host: "unlisted.gosuslugi.ru"}, constant.RuleMatchHelper{}) {
				t.Fatal("exact domain was broadened to all subdomains")
			}
		})
	}
}

func TestWdttRoutingFollowsAutomaticAndManualSelection(t *testing.T) {
	vlessRouter, _ := outbound.NewRematch(outbound.RematchOption{Name: "VLESS [1]", TargetSubRule: new("VLESS rules [1]")})
	wdttRouter, _ := outbound.NewRematch(outbound.RematchOption{Name: "WDTT [1]", TargetSubRule: new("WDTT rules [1]")})
	vless := adapter.NewProxy(vlessRouter)
	wdtt := adapter.NewProxy(wdttRouter)
	automatic := selectorOver(t, "Auto [1]", vless, wdtt)
	root := selectorOver(t, "VLESS / WDTT [1]", automatic, vless, wdtt)
	proxies := map[string]constant.Proxy{
		root.Name(): root, automatic.Name(): automatic, vless.Name(): vless, wdtt.Name(): wdtt,
		"DIRECT": namedProxy("DIRECT"), "primary": namedProxy("primary"), "backup": namedProxy("backup"),
	}
	parse := func(lines ...string) []constant.Rule {
		result := make([]constant.Rule, 0, len(lines))
		for _, line := range lines {
			parts := strings.Split(line, ",")
			payload, target := "", parts[len(parts)-1]
			if len(parts) == 3 {
				payload = parts[1]
			}
			rule, err := rules.ParseRule(parts[0], payload, target, nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			result = append(result, rule)
		}
		return result
	}
	RP.SetTunnel(tunnel.Tunnel)
	white := RP.NewInlineProvider("white", P.Domain, []string{"allowed.test"}, rules.ParseRule)
	tunnel.UpdateProxies(proxies, nil)
	tunnel.UpdateRules(parse("MATCH,VLESS / WDTT [1]"), map[string][]constant.Rule{
		"VLESS rules [1]": parse("DOMAIN,blocked.test,primary", "MATCH,DIRECT"),
		"WDTT rules [1]":  parse("RULE-SET,white,DIRECT", "MATCH,backup"),
	}, map[string]P.RuleProvider{"white": white})
	tunnel.SetMode(tunnel.Rule)
	t.Cleanup(func() { tunnel.UpdateRules(nil, nil, nil); tunnel.UpdateProxies(nil, nil) })
	check := func(host, want string) {
		t.Helper()
		for _, network := range []constant.NetWork{constant.TCP, constant.UDP} {
			proxy, err := tunnel.ResolveRoute(&constant.Metadata{Host: host, NetWork: network, DstPort: 443})
			if err != nil || proxy.Name() != want {
				t.Fatalf("%s/%s: proxy=%v, err=%v, want %s", host, network, proxy, err, want)
			}
		}
	}
	check("blocked.test", "primary")
	check("ordinary.test", "DIRECT")
	for _, selection := range []ChangeProxyParams{
		{GroupName: automatic.Name(), ProxyName: wdtt.Name()},
		{GroupName: root.Name(), ProxyName: vless.Name()},
		{GroupName: root.Name(), ProxyName: wdtt.Name()},
		{GroupName: automatic.Name(), ProxyName: vless.Name()},
		{GroupName: root.Name(), ProxyName: automatic.Name()},
	} {
		before := wdttRoutingTarget()
		connection := newPipeTracker(t)
		if result := handleChangeProxy(&selection); result.Message != "" {
			t.Fatal(result.Message)
		}
		stillOpen := statistic.DefaultManager.Get(connection.ID()) != nil
		if stillOpen != (before == wdttRoutingTarget()) {
			t.Fatal("connections must close only when the effective routing scheme changes")
		}
		_ = connection.Close()
		check("allowed.test", "DIRECT")
		if wdttRoutingTarget() == wdtt.Name() {
			check("ordinary.test", "backup")
			check("blocked.test", "backup")
		} else {
			check("ordinary.test", "DIRECT")
			check("blocked.test", "primary")
		}
	}
}
