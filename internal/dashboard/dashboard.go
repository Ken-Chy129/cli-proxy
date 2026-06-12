package dashboard

import (
	"embed"
	"io/fs"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed static
var staticFiles embed.FS

func Handler() gin.HandlerFunc {
	sub, _ := fs.Sub(staticFiles, "static")
	return func(c *gin.Context) {
		c.FileFromFS("index.html", http.FS(sub))
	}
}

func StaticFS() http.FileSystem {
	sub, _ := fs.Sub(staticFiles, "static")
	return http.FS(sub)
}
