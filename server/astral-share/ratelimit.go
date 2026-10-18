package main

import (
	"sync"
	"time"
)

// RateLimiter 是按 key（通常为客户端 IP）计数的固定窗口限流器。
//
// 短码服务面向公网，创建接口必须限流，否则很容易被刷出大量房间码；
// 查询接口给得宽松一些，避免同一 NAT 下的多名玩家互相影响。
type RateLimiter struct {
	mu        sync.Mutex
	window    time.Duration
	limit     int
	entries   map[string]*rateEntry
	lastSweep time.Time
}

type rateEntry struct {
	start time.Time
	count int
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		window:    window,
		limit:     limit,
		entries:   make(map[string]*rateEntry),
		lastSweep: time.Now(),
	}
}

// Allow 返回该 key 在当前窗口内是否还有配额。
func (l *RateLimiter) Allow(key string) bool {
	if l == nil || l.limit <= 0 {
		return true
	}
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	if now.Sub(l.lastSweep) >= l.window {
		for k, e := range l.entries {
			if now.Sub(e.start) >= l.window {
				delete(l.entries, k)
			}
		}
		l.lastSweep = now
	}

	e := l.entries[key]
	if e == nil || now.Sub(e.start) >= l.window {
		l.entries[key] = &rateEntry{start: now, count: 1}
		return true
	}
	if e.count >= l.limit {
		return false
	}
	e.count++
	return true
}
