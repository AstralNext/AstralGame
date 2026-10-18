package main

import (
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

const maxPayloadBytes = 32 << 10

// API 提供客户端使用的短码接口：
//
//	POST   /v1/codes                 创建或复用短码（按房间指纹去重 + 滑动续期）
//	GET    /v1/codes/{code}          查询短码（滑动续期）
//	DELETE /v1/codes/{code}          作废短码（X-Admin-Token）
//	POST   /v1/codes/{code}/heartbeat 心跳续期（X-Admin-Token）
//	GET    /v1/health                健康检查
type API struct {
	store         *Store
	masterToken   string
	trustProxy    bool
	onlineWindow  time.Duration
	startedAt     time.Time
	createLimiter *RateLimiter
	fetchLimiter  *RateLimiter
	writeLimiter  *RateLimiter
}

func NewAPI(store *Store, masterToken string, trustProxy bool, onlineWindow time.Duration) *API {
	return &API{
		store:         store,
		masterToken:   masterToken,
		trustProxy:    trustProxy,
		onlineWindow:  onlineWindow,
		startedAt:     time.Now(),
		createLimiter: NewRateLimiter(30, time.Minute),
		fetchLimiter:  NewRateLimiter(240, time.Minute),
		writeLimiter:  NewRateLimiter(120, time.Minute),
	}
}

type createResponse struct {
	Code       string `json:"code"`
	AdminToken string `json:"admin_token"`
	ExpiresAt  string `json:"expires_at"`
	Reused     bool   `json:"reused"`
}

func (a *API) handleCreate(w http.ResponseWriter, r *http.Request) {
	if !a.createLimiter.Allow(clientIP(r, a.trustProxy)) {
		writeAPIError(w, http.StatusTooManyRequests, "创建过于频繁，请稍后再试")
		return
	}

	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxPayloadBytes))
	if err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			writeAPIError(w, http.StatusRequestEntityTooLarge, "邀请载荷过大")
			return
		}
		writeAPIError(w, http.StatusBadRequest, "读取请求失败")
		return
	}

	var payload payloadInfo
	if err := json.Unmarshal(body, &payload); err != nil {
		writeAPIError(w, http.StatusBadRequest, "请求不是合法的 JSON")
		return
	}
	if err := validatePayload(&payload); err != nil {
		writeAPIError(w, http.StatusBadRequest, err.Error())
		return
	}

	fingerprint := fingerprintRoom(payload.NetworkName, payload.NetworkSecret)
	entry, reused, err := a.store.CreateOrReuse(fingerprint, body)
	if err != nil {
		writeAPIError(w, http.StatusInternalServerError, "生成短码失败")
		return
	}

	status := http.StatusCreated
	if reused {
		status = http.StatusOK
	}
	writeJSON(w, status, createResponse{
		Code:       entry.Code,
		AdminToken: entry.AdminToken,
		ExpiresAt:  entry.ExpiresAt.UTC().Format(time.RFC3339),
		Reused:     reused,
	})
}

func (a *API) handleGet(w http.ResponseWriter, r *http.Request) {
	code, ok := normalizeShareCode(r.PathValue("code"))
	if !ok {
		http.Error(w, "invalid or expired code", http.StatusNotFound)
		return
	}
	if !a.fetchLimiter.Allow(clientIP(r, a.trustProxy)) {
		writeAPIError(w, http.StatusTooManyRequests, "查询过于频繁，请稍后再试")
		return
	}

	entry, ok := a.store.Get(code)
	if !ok {
		http.Error(w, "invalid or expired code", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(entry.Payload)
}

func (a *API) handleDelete(w http.ResponseWriter, r *http.Request) {
	code, ok := normalizeShareCode(r.PathValue("code"))
	if !ok {
		http.Error(w, "invalid or expired code", http.StatusNotFound)
		return
	}
	if !a.writeLimiter.Allow(clientIP(r, a.trustProxy)) {
		writeAPIError(w, http.StatusTooManyRequests, "操作过于频繁")
		return
	}

	token := strings.TrimSpace(r.Header.Get("X-Admin-Token"))
	if token == "" {
		writeAPIError(w, http.StatusForbidden, "missing admin token")
		return
	}

	status := opNotFound
	if tokenEqual(token, a.masterToken) {
		if a.store.DeleteForce(code) {
			status = opOK
		}
	} else {
		status = a.store.Delete(code, token)
	}

	switch status {
	case opOK:
		w.WriteHeader(http.StatusNoContent)
	case opForbidden:
		writeAPIError(w, http.StatusForbidden, "invalid admin token")
	default:
		http.Error(w, "invalid or expired code", http.StatusNotFound)
	}
}

func (a *API) handleHeartbeat(w http.ResponseWriter, r *http.Request) {
	code, ok := normalizeShareCode(r.PathValue("code"))
	if !ok {
		writeAPIError(w, http.StatusNotFound, "invalid or expired code")
		return
	}
	if !a.writeLimiter.Allow(clientIP(r, a.trustProxy)) {
		writeAPIError(w, http.StatusTooManyRequests, "操作过于频繁")
		return
	}

	token := strings.TrimSpace(r.Header.Get("X-Admin-Token"))
	if token == "" {
		writeAPIError(w, http.StatusForbidden, "missing admin token")
		return
	}

	entry, status := a.store.Heartbeat(code, token)
	switch status {
	case opOK:
		writeJSON(w, http.StatusOK, map[string]string{
			"code":       entry.Code,
			"expires_at": entry.ExpiresAt.UTC().Format(time.RFC3339),
		})
	case opForbidden:
		writeAPIError(w, http.StatusForbidden, "invalid admin token")
	default:
		writeAPIError(w, http.StatusNotFound, "invalid or expired code")
	}
}

func (a *API) handleHealth(w http.ResponseWriter, r *http.Request) {
	stats := a.store.Stats(time.Now(), a.onlineWindow)
	writeJSON(w, http.StatusOK, map[string]any{
		"status":         "ok",
		"version":        version,
		"uptime_seconds": int64(time.Since(a.startedAt).Seconds()),
		"codes":          stats.Total,
		"online":         stats.Online,
	})
}

func validatePayload(p *payloadInfo) error {
	if strings.TrimSpace(p.NetworkName) == "" {
		return errors.New("network_name 不能为空")
	}
	if p.NetworkSecret == "" {
		return errors.New("network_secret 不能为空")
	}
	if len(p.NetworkName) > 128 {
		return errors.New("network_name 过长")
	}
	if len(p.NetworkSecret) > 512 {
		return errors.New("network_secret 过长")
	}
	if len(p.GameID) > 64 {
		return errors.New("game_id 过长")
	}
	if len(p.GameName) > 256 {
		return errors.New("game_name 过长")
	}
	if len(p.DisplayName) > 128 {
		return errors.New("display_name 过长")
	}
	if len(p.Peers) > 64 {
		return errors.New("peers 过多")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeAPIError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func clientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
			first := strings.TrimSpace(strings.Split(forwarded, ",")[0])
			if first != "" {
				return first
			}
		}
		if realIP := strings.TrimSpace(r.Header.Get("X-Real-IP")); realIP != "" {
			return realIP
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
