package auth

import (
	"math"
	"net/http"
	"strconv"
	"sync"
)

type QuotaInfo struct {
	PlanType    string      `json:"plan_type,omitempty"`
	RateLimit   *RateLimit  `json:"rate_limit,omitempty"`
	Credits     *Credits    `json:"credits,omitempty"`
}

type RateLimit struct {
	Allowed      bool    `json:"allowed"`
	LimitReached bool    `json:"limit_reached"`
	UsedPercent  float64 `json:"used_percent"`
	ResetMinutes int     `json:"reset_minutes,omitempty"`
}

type Credits struct {
	HasCredits bool   `json:"has_credits"`
	Unlimited  bool   `json:"unlimited"`
	Balance    string `json:"balance,omitempty"`
}

type ModelInfo struct {
	Slug        string `json:"slug"`
	DisplayName string `json:"display_name"`
	Description string `json:"description,omitempty"`
}

// QuotaCache stores quota info extracted from response headers.
var QuotaCache = &quotaCache{data: make(map[string]*QuotaInfo)}

type quotaCache struct {
	mu   sync.RWMutex
	data map[string]*QuotaInfo
}

func (c *quotaCache) Get(provider string) *QuotaInfo {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.data[provider]
}

func (c *quotaCache) Set(provider string, info *QuotaInfo) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.data[provider] = info
}

// ParseCodexRateLimitHeaders extracts quota from Codex response headers.
// Headers: x-codex-primary-used-percent, x-codex-primary-window-minutes, etc.
func ParseCodexRateLimitHeaders(h http.Header) *QuotaInfo {
	pctStr := h.Get("x-codex-primary-used-percent")
	if pctStr == "" {
		return nil
	}
	pct, err := strconv.ParseFloat(pctStr, 64)
	if err != nil {
		return nil
	}

	info := &QuotaInfo{
		RateLimit: &RateLimit{
			UsedPercent:  math.Round(pct*100) / 100,
			Allowed:      true,
			LimitReached: pct >= 100,
		},
	}

	if winStr := h.Get("x-codex-primary-window-minutes"); winStr != "" {
		if v, err := strconv.Atoi(winStr); err == nil {
			info.RateLimit.ResetMinutes = v
		}
	}

	// Credits from headers
	if h.Get("x-codex-credits-has-credits") == "true" {
		info.Credits = &Credits{
			HasCredits: true,
			Unlimited:  h.Get("x-codex-credits-unlimited") == "true",
			Balance:    h.Get("x-codex-credits-balance"),
		}
	}

	return info
}
