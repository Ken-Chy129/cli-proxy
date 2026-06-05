package server

import (
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/user/cli-proxy/internal/auth"
	"github.com/user/cli-proxy/internal/config"
	"github.com/user/cli-proxy/internal/dashboard"
	"github.com/user/cli-proxy/internal/executor"
	"github.com/user/cli-proxy/internal/handler"
	"github.com/user/cli-proxy/internal/router"
	"github.com/user/cli-proxy/internal/stats"
)

func Run(cfg *config.Config, r *router.Router, tokenStore *auth.TokenStore, statsDB *stats.DB,
	claudeOAuth *auth.ClaudeOAuth, codexOAuth *auth.CodexOAuth,
	claudeExec *executor.ClaudeOAuthExecutor, codexExec *executor.CodexExecutor) error {

	gin.SetMode(gin.ReleaseMode)
	engine := gin.New()
	engine.Use(gin.Recovery())

	chatHandler := handler.NewChatHandler(r, statsDB)
	adminHandler := handler.NewAdminHandler(cfg, r, tokenStore, statsDB, codexOAuth)
	imagesHandler := handler.NewImagesHandler(r, statsDB)

	authMW := APIKeyAuth(cfg.Server.APIKey)

	// Dashboard (protected)
	engine.GET("/", authMW, dashboard.Handler())

	// API routes (protected)
	api := engine.Group("/", authMW)
	api.POST("/v1/chat/completions", chatHandler.ChatCompletions)
	api.POST("/v1/images/generations", imagesHandler.ImagesGenerations)
	api.GET("/v1/models", chatHandler.ListModels)

	// Admin API (protected)
	admin := engine.Group("/api", authMW)
	admin.GET("/status", adminHandler.Status)
	admin.GET("/logs", adminHandler.Logs)
	admin.GET("/stats", adminHandler.Stats)
	admin.GET("/config", adminHandler.Config)
	admin.POST("/sync-models", adminHandler.SyncModels)
	admin.POST("/refresh-quota/:provider/:id", adminHandler.RefreshQuota)
	admin.DELETE("/accounts/:provider/:id", adminHandler.DeleteAccount)

	// OAuth login (protected)
	if claudeOAuth != nil {
		engine.GET("/auth/claude", authMW, func(c *gin.Context) {
			authURL, err := claudeOAuth.StartLogin()
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.Redirect(http.StatusTemporaryRedirect, authURL)
		})
	}
	if codexOAuth != nil {
		engine.GET("/auth/codex", authMW, func(c *gin.Context) {
			authURL, err := codexOAuth.StartLogin()
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
				return
			}
			c.Redirect(http.StatusTemporaryRedirect, authURL)
		})
	}

	// Health check (public, no auth)
	engine.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	addr := fmt.Sprintf(":%d", cfg.Server.Port)
	fmt.Printf("models: %v\n", r.AllModels())
	if cfg.Server.CertFile != "" && cfg.Server.KeyFile != "" {
		fmt.Printf("cli-proxy listening on %s (HTTPS)\n", addr)
		return engine.RunTLS(addr, cfg.Server.CertFile, cfg.Server.KeyFile)
	}
	fmt.Printf("cli-proxy listening on %s\n", addr)
	return engine.Run(addr)
}
