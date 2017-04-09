package auth

import (
	"errors"
	"fmt"
	"net/http"

	"golang.org/x/oauth2"
)

type Provider struct {
	Name         string
	Codename     string
	clientID     string
	clientSecret string
	endpoint     oauth2.Endpoint
	scopes       []string

	fetchUser func(*http.Client) (*providerUser, error)
}

func (p *Provider) Config(r *http.Request) *oauth2.Config {
	// local development requires http
	// TODO
	scheme := "http"
	if r.URL.Scheme == "" {
		scheme = "http"
	}

	redirect := fmt.Sprintf("%s://%s/login/%s/success", scheme, r.Host, p.Codename)
	return &oauth2.Config{
		ClientID:     p.clientID,
		ClientSecret: p.clientSecret,
		RedirectURL:  redirect,
		Endpoint:     p.endpoint,
		Scopes:       p.scopes,
	}
}

var ErrInvalidProfile = errors.New("invalid provider's profile")

type providerUser struct {
	ID         int    `json:"id"`
	Email      string `json:"email"`
	Provider   string `json:"provider"`
	Name       string `json:"name"`
	ProfileURL string `json:"profileUrl"`
}
