package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/garyburd/redigo/redis"
	"github.com/husio/scrumboard/server/auth"
	"github.com/husio/scrumboard/server/cache"
	"github.com/husio/scrumboard/server/pubsub"
	"github.com/husio/scrumboard/server/scrumboard"
	"github.com/husio/scrumboard/server/surf"
)

func main() {
	debug := env("DEBUG", "false") == "true"
	httpPort := env("PORT", "8000")
	staticPath := env("STATIC", "./dist")
	redisUrl := env("REDIS_URL", "redis://localhost:6379/2")
	templatesPath := env("TEMPLATES", "./templates/**.tmpl")
	// registered as http://scrumboard.dev:8000 (edit your /etc/hosts)
	githubClientId := env("GITHUB_CLIENT_ID", "f52ce2105e1023495aca")
	githubSecret := env("GITHUB_SECRET", "8bb88273d8832e29194140c0926ccc5de1961371")

	redisPool := &redis.Pool{
		MaxIdle:     3,
		MaxActive:   10,
		IdleTimeout: 90 * time.Second,
		Wait:        true,
		Dial:        func() (redis.Conn, error) { return redis.DialURL(redisUrl) },
	}

	html := surf.LoadTemplates(templatesPath)
	html.Debug = debug
	boardStore := scrumboard.NewRedisBoardStore(redisPool)
	providers := []auth.Provider{
		auth.GithubProvider(!debug, githubClientId, githubSecret),
	}
	cache := cache.NewRedisCache(redisPool)
	authApp := auth.NewApp(cache, html, providers, debug)
	hub := pubsub.Snapshot(redisPool, pubsub.NewMemoryHub())
	scrumBoardApp := scrumboard.NewApp(html, authApp, boardStore, hub, debug)

	rt := surf.NewRouter()
	rt.Get(`/`, scrumBoardApp)
	rt.Any(`/new`, scrumBoardApp)
	rt.Get(`/ws/.*`, scrumBoardApp)
	rt.Get(`/b/.*`, scrumBoardApp)
	rt.Get(`/login`, authApp)
	rt.Get(`/login/.*`, authApp)
	rt.Get(`/logout`, authApp)
	rt.Get(`/static/.*`, http.StripPrefix("/static", http.FileServer(http.Dir(staticPath))))

	log.Printf("starting HTTP server: 0.0.0.0:%s", httpPort)
	if err := http.ListenAndServe("0.0.0.0:"+httpPort, rt); err != nil {
		log.Fatalf("server failed: %s", err)
	}
}

func env(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
