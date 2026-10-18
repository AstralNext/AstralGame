package main

import (
	"crypto/rand"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"math"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

//go:embed templates/*.html
var templateFS embed.FS

const adminSessionCookie = "astral_share_admin"

const (
	// loginMaxFailures 是同一 IP 连续失败的容忍次数，超过后封禁。
	loginMaxFailures = 5
	// loginBlockDuration 是封禁时长。
	loginBlockDuration = 15 * time.Minute
)

// Admin 提供 Web 管理后台：登录、概览、搜索、作废。
type Admin struct {
	store        *Store
	masterToken  string
	trustProxy   bool
	onlineWindow time.Duration
	ttl          time.Duration
	allowIPs     []*net.IPNet
	sessions     *sessionStore
	loginLimiter *RateLimiter
	loginGuard   *loginGuard
	templates    *template.Template
}

func NewAdmin(
	store *Store,
	masterToken string,
	trustProxy bool,
	onlineWindow, ttl time.Duration,
	allowIPs []*net.IPNet,
) (*Admin, error) {
	tmpl, err := template.ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, err
	}
	return &Admin{
		store:        store,
		masterToken:  masterToken,
		trustProxy:   trustProxy,
		onlineWindow: onlineWindow,
		ttl:          ttl,
		allowIPs:     allowIPs,
		sessions:     newSessionStore(12 * time.Hour),
		loginLimiter: NewRateLimiter(10, time.Minute),
		loginGuard:   newLoginGuard(),
		templates:    tmpl,
	}, nil
}

// parseIPAllowlist 解析逗号 / 空白分隔的 IP 或 CIDR 列表。
//
// 返回空列表表示不启用 IP 白名单。
func parseIPAllowlist(raw string) ([]*net.IPNet, error) {
	fields := strings.FieldsFunc(raw, func(r rune) bool {
		return r == ',' || r == ';' || unicode.IsSpace(r)
	})
	nets := make([]*net.IPNet, 0, len(fields))
	for _, field := range fields {
		item := strings.TrimSpace(field)
		if item == "" {
			continue
		}
		if strings.Contains(item, "/") {
			_, network, err := net.ParseCIDR(item)
			if err != nil {
				return nil, fmt.Errorf("非法的 IP 段 %q", item)
			}
			nets = append(nets, network)
			continue
		}
		ip := net.ParseIP(item)
		if ip == nil {
			return nil, fmt.Errorf("非法的 IP %q", item)
		}
		bits := 128
		if v4 := ip.To4(); v4 != nil {
			ip = v4
			bits = 32
		}
		nets = append(nets, &net.IPNet{IP: ip, Mask: net.CIDRMask(bits, bits)})
	}
	return nets, nil
}

// ipAllowed 判断请求来源 IP 是否在白名单内；白名单为空时放行全部。
func (a *Admin) ipAllowed(r *http.Request) bool {
	if len(a.allowIPs) == 0 {
		return true
	}
	ip := net.ParseIP(clientIP(r, a.trustProxy))
	if ip == nil {
		return false
	}
	for _, network := range a.allowIPs {
		if network.Contains(ip) {
			return true
		}
	}
	return false
}

// loginGuard 按 IP 统计登录失败次数，超过阈值后临时封禁。
type loginGuard struct {
	mu      sync.Mutex
	records map[string]*loginRecord
}

type loginRecord struct {
	failures     int
	lastFailure  time.Time
	blockedUntil time.Time
}

func newLoginGuard() *loginGuard {
	return &loginGuard{records: make(map[string]*loginRecord)}
}

// blocked 返回该 IP 是否处于封禁期，以及剩余时长。
func (g *loginGuard) blocked(ip string, now time.Time) (bool, time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()
	rec, ok := g.records[ip]
	if !ok {
		return false, 0
	}
	if rec.blockedUntil.After(now) {
		return true, rec.blockedUntil.Sub(now)
	}
	if !rec.blockedUntil.IsZero() {
		delete(g.records, ip)
	}
	return false, 0
}

// fail 记录一次失败；达到阈值时开始封禁并返回 true。
func (g *loginGuard) fail(ip string, now time.Time) (bool, time.Duration) {
	g.mu.Lock()
	defer g.mu.Unlock()

	g.pruneLocked(now)

	rec := g.records[ip]
	if rec == nil || now.Sub(rec.lastFailure) > time.Hour {
		rec = &loginRecord{}
		g.records[ip] = rec
	}
	rec.failures++
	rec.lastFailure = now
	if rec.failures >= loginMaxFailures {
		rec.failures = 0
		rec.blockedUntil = now.Add(loginBlockDuration)
		return true, loginBlockDuration
	}
	return false, 0
}

// reset 在登录成功后清空该 IP 的失败计数。
func (g *loginGuard) reset(ip string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	delete(g.records, ip)
}

// pruneLocked 定期回收过期记录，避免被大量伪造 IP 撑大内存。
func (g *loginGuard) pruneLocked(now time.Time) {
	if len(g.records) < 1024 {
		return
	}
	for ip, rec := range g.records {
		if rec.blockedUntil.After(now) {
			continue
		}
		if now.Sub(rec.lastFailure) > time.Hour {
			delete(g.records, ip)
		}
	}
}

// rejectBlocked 返回封禁响应，并写入 Retry-After。
func rejectBlocked(w http.ResponseWriter, remain time.Duration) {
	seconds := int(math.Ceil(remain.Seconds()))
	if seconds < 1 {
		seconds = 1
	}
	w.Header().Set("Retry-After", strconv.Itoa(seconds))
	http.Error(w, "登录失败次数过多，请 15 分钟后再试", http.StatusTooManyRequests)
}

type dashboardData struct {
	Version             string
	TTLHours            int
	OnlineWindowMinutes int
}

type loginData struct {
	Error bool
}

func (a *Admin) handleLoginPage(w http.ResponseWriter, r *http.Request) {
	if !a.ipAllowed(r) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	if c, err := r.Cookie(adminSessionCookie); err == nil && a.sessions.valid(c.Value) {
		http.Redirect(w, r, "/admin", http.StatusSeeOther)
		return
	}
	a.render(w, "login.html", loginData{Error: r.URL.Query().Get("error") != ""})
}

func (a *Admin) handleLogin(w http.ResponseWriter, r *http.Request) {
	if !a.ipAllowed(r) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	ip := clientIP(r, a.trustProxy)
	if blocked, remain := a.loginGuard.blocked(ip, time.Now()); blocked {
		rejectBlocked(w, remain)
		return
	}
	if !a.loginLimiter.Allow(ip) {
		http.Error(w, "尝试过于频繁，请稍后再试", http.StatusTooManyRequests)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
	if err := r.ParseForm(); err != nil {
		http.Redirect(w, r, "/admin/login?error=1", http.StatusSeeOther)
		return
	}
	token := strings.TrimSpace(r.PostFormValue("token"))
	if !tokenEqual(token, a.masterToken) {
		if blocked, remain := a.loginGuard.fail(ip, time.Now()); blocked {
			log.Printf("admin: IP %s 登录失败次数过多，已封禁 %s", ip, loginBlockDuration)
			rejectBlocked(w, remain)
			return
		}
		http.Redirect(w, r, "/admin/login?error=1", http.StatusSeeOther)
		return
	}
	a.loginGuard.reset(ip)

	sessionID, err := a.sessions.create()
	if err != nil {
		http.Error(w, "无法创建会话", http.StatusInternalServerError)
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     adminSessionCookie,
		Value:    sessionID,
		Path:     "/admin",
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Secure:   r.TLS != nil,
		MaxAge:   int((12 * time.Hour).Seconds()),
	})
	http.Redirect(w, r, "/admin", http.StatusSeeOther)
}

func (a *Admin) handleLogout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(adminSessionCookie); err == nil {
		a.sessions.destroy(c.Value)
	}
	http.SetCookie(w, &http.Cookie{
		Name:     adminSessionCookie,
		Value:    "",
		Path:     "/admin",
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Secure:   r.TLS != nil,
		MaxAge:   -1,
	})
	http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
}

func (a *Admin) handleDashboard(w http.ResponseWriter, r *http.Request) {
	a.render(w, "dashboard.html", dashboardData{
		Version:             version,
		TTLHours:            int(a.ttl.Hours()),
		OnlineWindowMinutes: int(a.onlineWindow.Minutes()),
	})
}

func (a *Admin) handleOverview(w http.ResponseWriter, r *http.Request) {
	now := time.Now()
	stats := a.store.Stats(now, a.onlineWindow)
	entries := a.store.AdminEntries(now, a.onlineWindow)

	query := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	status := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("status")))

	filtered := make([]AdminEntry, 0, len(entries))
	for _, e := range entries {
		if query != "" {
			haystack := strings.ToLower(e.Code + " " + e.GameID + " " + e.GameName + " " +
				e.DisplayName + " " + e.NetworkName)
			if !strings.Contains(haystack, query) {
				continue
			}
		}
		switch status {
		case "online":
			if !e.Online {
				continue
			}
		case "idle":
			if e.Online {
				continue
			}
		case "expiring":
			if !e.ExpiringSoon {
				continue
			}
		}
		filtered = append(filtered, e)
	}
	if len(filtered) > 500 {
		filtered = filtered[:500]
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"stats":                 stats,
		"codes":                 filtered,
		"now":                   now,
		"online_window_seconds": int(a.onlineWindow.Seconds()),
		"ttl_seconds":           int(a.ttl.Seconds()),
	})
}

func (a *Admin) handleRevoke(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 4<<10)
	var req struct {
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeAPIError(w, http.StatusBadRequest, "请求不是合法的 JSON")
		return
	}
	code, ok := normalizeShareCode(req.Code)
	if !ok {
		writeAPIError(w, http.StatusBadRequest, "短码格式不正确")
		return
	}
	if !a.store.DeleteForce(code) {
		writeAPIError(w, http.StatusNotFound, "短码不存在或已过期")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "code": code})
}

// require 校验后台会话；API 请求返回 401 JSON，页面请求跳转登录页。
func (a *Admin) require(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !a.ipAllowed(r) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		cookie, err := r.Cookie(adminSessionCookie)
		if err != nil || !a.sessions.valid(cookie.Value) {
			if strings.HasPrefix(r.URL.Path, "/admin/api/") {
				writeAPIError(w, http.StatusUnauthorized, "unauthorized")
				return
			}
			http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
			return
		}
		next(w, r)
	}
}

func (a *Admin) render(w http.ResponseWriter, name string, data any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	if err := a.templates.ExecuteTemplate(w, name, data); err != nil {
		log.Printf("admin: 渲染 %s 失败: %v", name, err)
		http.Error(w, "页面渲染失败", http.StatusInternalServerError)
	}
}

// sessionStore 保存后台登录会话，只存内存；服务重启后需要重新登录。
type sessionStore struct {
	mu    sync.Mutex
	items map[string]time.Time
	ttl   time.Duration
}

func newSessionStore(ttl time.Duration) *sessionStore {
	return &sessionStore{items: make(map[string]time.Time), ttl: ttl}
}

func (s *sessionStore) create() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	id := base64.RawURLEncoding.EncodeToString(buf)
	now := time.Now()

	s.mu.Lock()
	defer s.mu.Unlock()
	for key, expiry := range s.items {
		if !expiry.After(now) {
			delete(s.items, key)
		}
	}
	s.items[id] = now.Add(s.ttl)
	return id, nil
}

func (s *sessionStore) valid(id string) bool {
	if id == "" {
		return false
	}
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	expiry, ok := s.items[id]
	if !ok {
		return false
	}
	if !expiry.After(now) {
		delete(s.items, id)
		return false
	}
	return true
}

func (s *sessionStore) destroy(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.items, id)
}
