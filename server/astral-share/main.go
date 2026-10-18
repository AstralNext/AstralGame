package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const version = "2.0.0"

func main() {
	var (
		addr         = flag.String("addr", envOr("ASTRAL_SHARE_ADDR", ":8080"), "监听地址")
		dataPath     = flag.String("data", envOr("ASTRAL_SHARE_DATA", "data/codes.db"), "SQLite 数据库路径")
		ttl          = flag.Duration("ttl", envDuration("ASTRAL_SHARE_TTL", 7*24*time.Hour), "短码有效期，每次访问滑动续期")
		adminToken   = flag.String("admin-token", envOr("ASTRAL_SHARE_ADMIN_TOKEN", "song520"), "管理员密码")
		adminAllowIP = flag.String("admin-allow-ips", os.Getenv("ASTRAL_SHARE_ADMIN_ALLOW_IPS"), "后台 IP 白名单，逗号分隔，支持 CIDR；留空不限制")
		onlineWindow = flag.Duration("online-window", envDuration("ASTRAL_SHARE_ONLINE_WINDOW", 10*time.Minute), "在线判定窗口")
		trustProxy   = flag.Bool("trust-proxy", envBool("ASTRAL_SHARE_TRUST_PROXY", false), "信任 X-Forwarded-For / X-Real-IP")
	)
	flag.Parse()

	if *ttl <= 0 {
		log.Fatalf("配置错误: --ttl 必须大于 0")
	}
	if *onlineWindow <= 0 {
		log.Fatalf("配置错误: --online-window 必须大于 0")
	}
	if *onlineWindow > *ttl {
		log.Printf("警告: 在线窗口 (%s) 大于短码有效期 (%s)，在线状态会失真", *onlineWindow, *ttl)
	}

	if strings.TrimSpace(*adminToken) == "" {
		log.Fatalf("配置错误: 后台密码不能为空")
	}
	if strings.TrimSpace(*adminToken) == "song520" {
		log.Printf("提示: 正在使用默认后台密码，可通过 --admin-token 或 ASTRAL_SHARE_ADMIN_TOKEN 修改")
	}

	allowNets, err := parseIPAllowlist(*adminAllowIP)
	if err != nil {
		log.Fatalf("解析后台 IP 白名单失败: %v", err)
	}
	if len(allowNets) > 0 {
		log.Printf("后台 IP 白名单已启用，共 %d 条规则", len(allowNets))
	} else {
		log.Printf("提示: 未配置后台 IP 白名单，仅启用失败锁定（5 次失败封禁 15 分钟）")
	}

	store, err := NewStore(*dataPath, *ttl)
	if err != nil {
		log.Fatalf("初始化存储失败: %v", err)
	}

	api := NewAPI(store, *adminToken, *trustProxy, *onlineWindow)
	admin, err := NewAdmin(store, *adminToken, *trustProxy, *onlineWindow, *ttl, allowNets)
	if err != nil {
		log.Fatalf("初始化管理后台失败: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", api.handleHealth)
	mux.HandleFunc("POST /v1/codes", api.handleCreate)
	mux.HandleFunc("GET /v1/codes/{code}", api.handleGet)
	mux.HandleFunc("DELETE /v1/codes/{code}", api.handleDelete)
	mux.HandleFunc("POST /v1/codes/{code}/heartbeat", api.handleHeartbeat)

	mux.HandleFunc("GET /admin/login", admin.handleLoginPage)
	mux.HandleFunc("POST /admin/login", admin.handleLogin)
	mux.HandleFunc("POST /admin/logout", admin.handleLogout)
	mux.HandleFunc("GET /admin", admin.require(admin.handleDashboard))
	mux.HandleFunc("GET /admin/api/overview", admin.require(admin.handleOverview))
	mux.HandleFunc("POST /admin/api/revoke", admin.require(admin.handleRevoke))

	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/admin", http.StatusFound)
	})

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go store.Run(ctx)

	srv := &http.Server{
		Addr:              *addr,
		Handler:           withMiddleware(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		log.Printf("astral-share %s 启动: %s (ttl=%s, online=%s)", version, *addr, *ttl, *onlineWindow)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErr <- err
		}
	}()

	select {
	case err := <-serverErr:
		log.Fatalf("服务异常退出: %v", err)
	case <-ctx.Done():
		log.Printf("收到退出信号，正在关闭")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("关闭 HTTP 服务失败: %v", err)
	}
	stop()
	if err := store.Close(); err != nil {
		log.Printf("关闭数据库失败: %v", err)
	}
	log.Printf("已退出")
}

func withMiddleware(next http.Handler) http.Handler {
	return recoverMiddleware(accessLog(securityHeaders(next)))
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		if strings.HasPrefix(r.URL.Path, "/admin") {
			h.Set("Content-Security-Policy",
				"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "+
					"connect-src 'self'; img-src data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	if r.status != 0 {
		return
	}
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

func accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		if rec.status == 0 {
			rec.status = http.StatusOK
		}
		log.Printf("%s %s %d %dB %s", r.Method, maskPath(r.URL.Path), rec.status, rec.bytes, time.Since(start).Round(time.Millisecond))
	})
}

func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				log.Printf("panic: %s %s: %v", r.Method, maskPath(r.URL.Path), v)
				http.Error(w, "internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// maskPath 在访问日志里隐藏短码，避免日志泄露可用邀请码。
func maskPath(path string) string {
	const prefix = "/v1/codes/"
	if !strings.HasPrefix(path, prefix) {
		return path
	}
	rest := strings.TrimPrefix(path, prefix)
	if rest == "" {
		return path
	}
	if i := strings.IndexByte(rest, '/'); i >= 0 {
		return prefix + "***" + rest[i:]
	}
	return prefix + "***"
}

func envOr(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func envDuration(key string, fallback time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		log.Printf("环境变量 %s=%q 不是合法时长，使用默认值 %s", key, raw, fallback)
		return fallback
	}
	return d
}

func envBool(key string, fallback bool) bool {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		log.Printf("环境变量 %s=%q 不是合法布尔值，使用默认值 %v", key, raw, fallback)
		return fallback
	}
	return v
}
