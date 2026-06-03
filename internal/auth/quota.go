package auth

type QuotaInfo struct {
	PlanType    string      `json:"plan_type,omitempty"`
	RateLimit   *RateLimit  `json:"rate_limit,omitempty"`
	Credits     *Credits    `json:"credits,omitempty"`
}

type RateLimit struct {
	Allowed      bool    `json:"allowed"`
	LimitReached bool    `json:"limit_reached"`
	UsedPercent  float64 `json:"used_percent,omitempty"`
	ResetAfterS  float64 `json:"reset_after_seconds,omitempty"`
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
