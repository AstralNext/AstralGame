package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const (
	shareCodeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
	shareCodeLength   = 6

	// adminEntriesLimit 是后台一次最多返回的条数，避免数据量大了拖垮页面。
	adminEntriesLimit = 1000
)

// Entry 是服务端保存的一条短码。
//
// Payload 保留客户端提交的原始 JSON，GET 时原样返回，
// 这样客户端新增字段（peers/display_name 等）不需要服务端同步改协议。
type Entry struct {
	Code        string          `json:"code"`
	AdminToken  string          `json:"admin_token"`
	Fingerprint string          `json:"fingerprint"`
	Payload     json.RawMessage `json:"payload"`
	CreatedAt   time.Time       `json:"created_at"`
	LastSeen    time.Time       `json:"last_seen"`
	ExpiresAt   time.Time       `json:"expires_at"`
}

// Store 是 SQLite 短码存储。
//
// 关键语义：
//   - 相同 network_name + network_secret（指纹）只保留一条短码；
//   - 每次 create 命中、GET、heartbeat 都滑动续期；
//   - 过期条目由后台 Sweep 回收，持久化交给 SQLite（WAL）。
type Store struct {
	db  *sql.DB
	ttl time.Duration
	now func() time.Time
}

// NewStore 打开（必要时创建）SQLite 数据库并建表。
func NewStore(path string, ttl time.Duration) (*Store, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("创建数据目录失败: %w", err)
	}

	dsn := "file:" + filepath.ToSlash(path) +
		"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("打开数据库失败: %w", err)
	}
	// modernc sqlite 单写连接最稳，短码服务并发量很小，不值得为吞吐引入锁竞争。
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("连接数据库失败: %w", err)
	}

	s := &Store{db: db, ttl: ttl, now: time.Now}
	if n, err := s.migrateLegacySchema(); err != nil {
		db.Close()
		return nil, err
	} else if n > 0 {
		log.Printf("store: 已从旧版表结构迁移 %d 条短码", n)
	}
	if _, err := db.Exec(codesSchema); err != nil {
		db.Close()
		return nil, fmt.Errorf("初始化表结构失败: %w", err)
	}
	if n, err := s.Sweep(); err == nil && n > 0 {
		log.Printf("store: 清理 %d 条过期短码", n)
	}
	if total, err := s.countAll(); err == nil {
		log.Printf("store: SQLite 就绪 (%s)，现有 %d 条记录", path, total)
	}
	return s, nil
}

const codesSchema = `
CREATE TABLE IF NOT EXISTS codes (
	code        TEXT PRIMARY KEY,
	admin_token TEXT NOT NULL,
	fingerprint TEXT NOT NULL UNIQUE,
	payload     BLOB NOT NULL,
	created_at  INTEGER NOT NULL,
	last_seen   INTEGER NOT NULL,
	expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_codes_expires ON codes(expires_at);
CREATE INDEX IF NOT EXISTS idx_codes_last_seen ON codes(last_seen);
`

// migrateLegacySchema 把旧版 codes 表迁移到当前结构。
//
// 旧版列：code / payload / admin_hash / expires_at / created_at（秒）。
// 迁移会保留短码与载荷，补算房间指纹并重新生成管理令牌；
// 旧表重命名为 codes_legacy 留作回滚，不会删除。
func (s *Store) migrateLegacySchema() (int, error) {
	cols, err := tableColumns(s.db, "codes")
	if err != nil {
		return 0, fmt.Errorf("读取表结构失败: %w", err)
	}
	if len(cols) == 0 {
		return 0, nil
	}
	has := func(name string) bool {
		for _, c := range cols {
			if c == name {
				return true
			}
		}
		return false
	}
	if has("fingerprint") && has("admin_token") && has("last_seen") {
		return 0, nil
	}

	tx, err := s.db.Begin()
	if err != nil {
		return 0, fmt.Errorf("启动迁移事务失败: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec("ALTER TABLE codes RENAME TO codes_legacy"); err != nil {
		return 0, fmt.Errorf("重命名旧表失败: %w", err)
	}
	if _, err := tx.Exec(codesSchema); err != nil {
		return 0, fmt.Errorf("创建新表失败: %w", err)
	}

	rows, err := tx.Query("SELECT code, payload, created_at, expires_at FROM codes_legacy")
	if err != nil {
		return 0, fmt.Errorf("读取旧数据失败: %w", err)
	}
	type legacyRow struct {
		code    string
		payload []byte
		created int64
		expires int64
	}
	var legacy []legacyRow
	for rows.Next() {
		var row legacyRow
		if err := rows.Scan(&row.code, &row.payload, &row.created, &row.expires); err != nil {
			rows.Close()
			return 0, fmt.Errorf("解析旧数据失败: %w", err)
		}
		legacy = append(legacy, row)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, fmt.Errorf("遍历旧数据失败: %w", err)
	}

	now := s.now()
	migrated := 0
	for _, row := range legacy {
		if row.expires <= now.Unix() {
			continue
		}
		var info payloadInfo
		_ = json.Unmarshal(row.payload, &info)
		fingerprint := "legacy:" + row.code
		if strings.TrimSpace(info.NetworkName) != "" && info.NetworkSecret != "" {
			fingerprint = fingerprintRoom(info.NetworkName, info.NetworkSecret)
		}
		token, err := newAdminToken()
		if err != nil {
			return 0, err
		}
		res, err := tx.Exec(
			"INSERT OR IGNORE INTO codes "+
				"(code, admin_token, fingerprint, payload, created_at, last_seen, expires_at) "+
				"VALUES (?, ?, ?, ?, ?, ?, ?)",
			row.code, token, fingerprint, row.payload,
			row.created*1000, row.created*1000, row.expires*1000,
		)
		if err != nil {
			return 0, fmt.Errorf("迁移短码 %s 失败: %w", row.code, err)
		}
		if n, _ := res.RowsAffected(); n > 0 {
			migrated++
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("提交迁移失败: %w", err)
	}
	return migrated, nil
}

func tableColumns(db *sql.DB, table string) ([]string, error) {
	rows, err := db.Query("PRAGMA table_info(" + table + ")")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var cols []string
	for rows.Next() {
		var (
			cid     int
			name    string
			ctype   string
			notNull int
			dflt    sql.NullString
			pk      int
		)
		if err := rows.Scan(&cid, &name, &ctype, &notNull, &dflt, &pk); err != nil {
			return nil, err
		}
		cols = append(cols, name)
	}
	return cols, rows.Err()
}

func (s *Store) Close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

const entryColumns = "code, admin_token, fingerprint, payload, created_at, last_seen, expires_at"

type rowScanner interface {
	Scan(dest ...any) error
}

func scanEntry(row rowScanner) (*Entry, error) {
	var (
		e                        Entry
		payload                  []byte
		createdAt, last, expires int64
	)
	if err := row.Scan(&e.Code, &e.AdminToken, &e.Fingerprint, &payload, &createdAt, &last, &expires); err != nil {
		return nil, err
	}
	e.Payload = cloneRaw(payload)
	e.CreatedAt = time.UnixMilli(createdAt)
	e.LastSeen = time.UnixMilli(last)
	e.ExpiresAt = time.UnixMilli(expires)
	return &e, nil
}

// CreateOrReuse 按房间指纹签发或复用短码，并滑动续期。
func (s *Store) CreateOrReuse(fingerprint string, payload json.RawMessage) (*Entry, bool, error) {
	now := s.now()
	next := cloneRaw(payload)

	row := s.db.QueryRow(
		"SELECT "+entryColumns+" FROM codes WHERE fingerprint = ?", fingerprint)
	e, err := scanEntry(row)
	switch {
	case err == nil:
		if e.ExpiresAt.After(now) {
			// 同一房间的服务器列表 / 显示名可能变化，用最新载荷覆盖。
			expires := now.Add(s.ttl)
			if _, execErr := s.db.Exec(
				"UPDATE codes SET payload = ?, last_seen = ?, expires_at = ? WHERE code = ?",
				[]byte(next), now.UnixMilli(), expires.UnixMilli(), e.Code,
			); execErr != nil {
				return nil, false, fmt.Errorf("更新短码失败: %w", execErr)
			}
			e.Payload = next
			e.LastSeen = now
			e.ExpiresAt = expires
			return e, true, nil
		}
		if _, execErr := s.db.Exec("DELETE FROM codes WHERE code = ?", e.Code); execErr != nil {
			return nil, false, fmt.Errorf("清理过期短码失败: %w", execErr)
		}
	case errors.Is(err, sql.ErrNoRows):
		// 正常路径：没有同房间的短码，下面新建。
	default:
		return nil, false, fmt.Errorf("查询短码失败: %w", err)
	}

	expires := now.Add(s.ttl)
	e, reused, err := s.insert(fingerprint, next, now, expires)
	if err != nil {
		return nil, false, err
	}
	return e, reused, nil
}

// insert 处理两种唯一约束冲突：
//   - fingerprint 冲突：同房间并发建房，复用已存在的记录；
//   - code 冲突：短码随机碰撞，换一个短码重试。
func (s *Store) insert(
	fingerprint string,
	payload json.RawMessage,
	now, expires time.Time,
) (*Entry, bool, error) {
	for attempt := 0; attempt < 10; attempt++ {
		code, err := newShareCode()
		if err != nil {
			return nil, false, err
		}
		token, err := newAdminToken()
		if err != nil {
			return nil, false, err
		}
		_, err = s.db.Exec(
			"INSERT INTO codes (code, admin_token, fingerprint, payload, created_at, last_seen, expires_at) "+
				"VALUES (?, ?, ?, ?, ?, ?, ?)",
			code, token, fingerprint, []byte(payload),
			now.UnixMilli(), now.UnixMilli(), expires.UnixMilli(),
		)
		if err == nil {
			return &Entry{
				Code:        code,
				AdminToken:  token,
				Fingerprint: fingerprint,
				Payload:     cloneRaw(payload),
				CreatedAt:   now,
				LastSeen:    now,
				ExpiresAt:   expires,
			}, false, nil
		}
		if !isUniqueViolation(err) {
			return nil, false, fmt.Errorf("写入短码失败: %w", err)
		}

		row := s.db.QueryRow(
			"SELECT "+entryColumns+" FROM codes WHERE fingerprint = ?", fingerprint)
		existing, scanErr := scanEntry(row)
		if scanErr == nil {
			if existing.ExpiresAt.After(now) {
				return existing, true, nil
			}
			// 过期记录还占着唯一约束，删掉后重试。
			if _, delErr := s.db.Exec("DELETE FROM codes WHERE code = ?", existing.Code); delErr != nil {
				return nil, false, fmt.Errorf("清理过期短码失败: %w", delErr)
			}
			continue
		}
		if !errors.Is(scanErr, sql.ErrNoRows) {
			return nil, false, fmt.Errorf("复用并发短码失败: %w", scanErr)
		}
		// 短码碰撞：重新生成短码。
	}
	return nil, false, errors.New("分配短码失败")
}

// Get 查询短码并滑动续期；过期条目会立即删除。
func (s *Store) Get(code string) (*Entry, bool) {
	now := s.now()
	row := s.db.QueryRow("SELECT "+entryColumns+" FROM codes WHERE code = ?", code)
	e, err := scanEntry(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, false
		}
		log.Printf("store: 查询短码失败: %v", err)
		return nil, false
	}
	if !e.ExpiresAt.After(now) {
		if _, err := s.db.Exec("DELETE FROM codes WHERE code = ?", code); err != nil {
			log.Printf("store: 删除过期短码失败: %v", err)
		}
		return nil, false
	}

	expires := now.Add(s.ttl)
	if _, err := s.db.Exec(
		"UPDATE codes SET last_seen = ?, expires_at = ? WHERE code = ?",
		now.UnixMilli(), expires.UnixMilli(), code,
	); err != nil {
		log.Printf("store: 续期短码失败: %v", err)
	}
	e.LastSeen = now
	e.ExpiresAt = expires
	return e, true
}

type opStatus int

const (
	opOK opStatus = iota
	opNotFound
	opForbidden
)

// Heartbeat 校验管理令牌并续期。
func (s *Store) Heartbeat(code, token string) (*Entry, opStatus) {
	now := s.now()
	row := s.db.QueryRow("SELECT "+entryColumns+" FROM codes WHERE code = ?", code)
	e, err := scanEntry(row)
	if err != nil {
		if !errors.Is(err, sql.ErrNoRows) {
			log.Printf("store: 心跳查询失败: %v", err)
		}
		return nil, opNotFound
	}
	if !e.ExpiresAt.After(now) {
		if _, err := s.db.Exec("DELETE FROM codes WHERE code = ?", code); err != nil {
			log.Printf("store: 删除过期短码失败: %v", err)
		}
		return nil, opNotFound
	}
	if !tokenEqual(e.AdminToken, token) {
		return nil, opForbidden
	}

	expires := now.Add(s.ttl)
	if _, err := s.db.Exec(
		"UPDATE codes SET last_seen = ?, expires_at = ? WHERE code = ?",
		now.UnixMilli(), expires.UnixMilli(), code,
	); err != nil {
		log.Printf("store: 心跳续期失败: %v", err)
	}
	e.LastSeen = now
	e.ExpiresAt = expires
	return e, opOK
}

// Delete 用短码自己的管理令牌作废。
func (s *Store) Delete(code, token string) opStatus {
	now := s.now()
	row := s.db.QueryRow("SELECT "+entryColumns+" FROM codes WHERE code = ?", code)
	e, err := scanEntry(row)
	if err != nil {
		return opNotFound
	}
	if !e.ExpiresAt.After(now) {
		if _, err := s.db.Exec("DELETE FROM codes WHERE code = ?", code); err != nil {
			log.Printf("store: 删除过期短码失败: %v", err)
		}
		return opNotFound
	}
	if !tokenEqual(e.AdminToken, token) {
		return opForbidden
	}
	if _, err := s.db.Exec("DELETE FROM codes WHERE code = ?", code); err != nil {
		log.Printf("store: 删除短码失败: %v", err)
		return opNotFound
	}
	return opOK
}

// DeleteForce 用主管理员令牌强制作废（Web 后台 / 运维）。
func (s *Store) DeleteForce(code string) bool {
	res, err := s.db.Exec("DELETE FROM codes WHERE code = ?", code)
	if err != nil {
		log.Printf("store: 强制作废失败: %v", err)
		return false
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false
	}
	return n > 0
}

// Sweep 清理所有过期短码，返回清理数量。
func (s *Store) Sweep() (int, error) {
	res, err := s.db.Exec("DELETE FROM codes WHERE expires_at <= ?", s.now().UnixMilli())
	if err != nil {
		return 0, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}
	return int(n), nil
}

func (s *Store) countAll() (int, error) {
	var n int
	err := s.db.QueryRow("SELECT COUNT(*) FROM codes").Scan(&n)
	return n, err
}

// Run 启动后台任务：定时清理过期条目。
func (s *Store) Run(ctx context.Context) {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if n, err := s.Sweep(); err != nil {
				log.Printf("store: 清理过期短码失败: %v", err)
			} else if n > 0 {
				log.Printf("store: 清理 %d 条过期短码", n)
			}
		}
	}
}

func newShareCode() (string, error) {
	buf := make([]byte, shareCodeLength)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("生成短码失败: %w", err)
	}
	var b strings.Builder
	b.Grow(shareCodeLength)
	for _, v := range buf {
		b.WriteByte(shareCodeAlphabet[int(v)%len(shareCodeAlphabet)])
	}
	return b.String(), nil
}

func newAdminToken() (string, error) {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("生成管理令牌失败: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "unique constraint") || strings.Contains(msg, "constraint failed: unique")
}

// fingerprintRoom 用房间名 + 房间密码做指纹。
//
// 指纹只保存 SHA-256，索引键里不含明文密码；后台展示时才从载荷里读原文。
func fingerprintRoom(networkName, networkSecret string) string {
	sum := sha256.Sum256([]byte(networkName + "\x00" + networkSecret))
	return hex.EncodeToString(sum[:])
}

func tokenEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}

func normalizeShareCode(raw string) (string, bool) {
	var b strings.Builder
	for _, r := range strings.ToUpper(strings.TrimSpace(raw)) {
		switch r {
		case '-', ' ', '_':
			continue
		case 'I', 'L':
			b.WriteByte('1')
		case 'O':
			b.WriteByte('0')
		default:
			b.WriteRune(r)
		}
	}
	code := b.String()
	if len(code) != shareCodeLength {
		return "", false
	}
	for i := 0; i < len(code); i++ {
		if !strings.ContainsRune(shareCodeAlphabet, rune(code[i])) {
			return "", false
		}
	}
	return code, true
}

func cloneRaw(raw json.RawMessage) json.RawMessage {
	if len(raw) == 0 {
		return json.RawMessage(`{}`)
	}
	return append(json.RawMessage(nil), raw...)
}

// Stats 是控制台顶部的汇总数据。
type Stats struct {
	Total        int `json:"total"`
	Online       int `json:"online"`
	ExpiringSoon int `json:"expiring_soon"`
	Created24h   int `json:"created_24h"`
}

func (s *Store) Stats(now time.Time, onlineWindow time.Duration) Stats {
	var stats Stats
	nowMs := now.UnixMilli()
	err := s.db.QueryRow(`
SELECT
	COALESCE(SUM(CASE WHEN expires_at > ? THEN 1 ELSE 0 END), 0),
	COALESCE(SUM(CASE WHEN expires_at > ? AND last_seen >= ? THEN 1 ELSE 0 END), 0),
	COALESCE(SUM(CASE WHEN expires_at > ? AND expires_at <= ? THEN 1 ELSE 0 END), 0),
	COALESCE(SUM(CASE WHEN expires_at > ? AND created_at >= ? THEN 1 ELSE 0 END), 0)
FROM codes`,
		nowMs,
		nowMs, now.Add(-onlineWindow).UnixMilli(),
		nowMs, now.Add(24*time.Hour).UnixMilli(),
		nowMs, now.Add(-24*time.Hour).UnixMilli(),
	).Scan(&stats.Total, &stats.Online, &stats.ExpiringSoon, &stats.Created24h)
	if err != nil {
		log.Printf("store: 统计失败: %v", err)
	}
	return stats
}

// AdminEntry 是 Web 后台展示用视图：不包含管理令牌，网络密码按运维需要明文展示。
type AdminEntry struct {
	Code          string    `json:"code"`
	GameID        string    `json:"game_id"`
	GameName      string    `json:"game_name"`
	DisplayName   string    `json:"display_name"`
	NetworkName   string    `json:"network_name"`
	NetworkSecret string    `json:"network_secret"`
	PeerCount     int       `json:"peer_count"`
	PeerURIs      []string  `json:"peer_uris,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
	LastSeen      time.Time `json:"last_seen"`
	ExpiresAt     time.Time `json:"expires_at"`
	Online        bool      `json:"online"`
	ExpiringSoon  bool      `json:"expiring_soon"`
}

type payloadInfo struct {
	V             int        `json:"v"`
	GameID        string     `json:"game_id"`
	GameName      string     `json:"game_name"`
	NetworkName   string     `json:"network_name"`
	NetworkSecret string     `json:"network_secret"`
	Peers         []peerInfo `json:"peers"`
	DisplayName   string     `json:"display_name"`
}

type peerInfo struct {
	URI string `json:"uri"`
}

func (s *Store) AdminEntries(now time.Time, onlineWindow time.Duration) []AdminEntry {
	rows, err := s.db.Query(
		"SELECT "+entryColumns+" FROM codes WHERE expires_at > ? "+
			"ORDER BY last_seen DESC LIMIT ?",
		now.UnixMilli(), adminEntriesLimit,
	)
	if err != nil {
		log.Printf("store: 读取后台列表失败: %v", err)
		return nil
	}
	defer rows.Close()

	soon := now.Add(24 * time.Hour)
	out := make([]AdminEntry, 0, 64)
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			log.Printf("store: 解析后台列表失败: %v", err)
			continue
		}
		var payload payloadInfo
		_ = json.Unmarshal(e.Payload, &payload)

		view := AdminEntry{
			Code:          e.Code,
			GameID:        payload.GameID,
			GameName:      payload.GameName,
			DisplayName:   payload.DisplayName,
			NetworkName:   payload.NetworkName,
			NetworkSecret: payload.NetworkSecret,
			PeerCount:     len(payload.Peers),
			CreatedAt:     e.CreatedAt,
			LastSeen:      e.LastSeen,
			ExpiresAt:     e.ExpiresAt,
			Online:        now.Sub(e.LastSeen) <= onlineWindow,
			ExpiringSoon:  !e.ExpiresAt.After(soon),
		}
		for i, peer := range payload.Peers {
			if i >= 8 {
				break
			}
			if uri := strings.TrimSpace(peer.URI); uri != "" {
				view.PeerURIs = append(view.PeerURIs, uri)
			}
		}
		out = append(out, view)
	}
	if err := rows.Err(); err != nil {
		log.Printf("store: 遍历后台列表失败: %v", err)
	}
	return out
}
