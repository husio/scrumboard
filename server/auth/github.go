package auth

import (
	"encoding/json"
	"net/http"

	"golang.org/x/oauth2"
)

func fetchGithubUser(c *http.Client) (*providerUser, error) {
	// https://developer.github.com/v3/users/#get-the-authenticated-user
	resp, err := c.Get("https://api.github.com/user")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var user struct {
		ID         int    `json:"id"`
		Email      string `json:"email"`
		Login      string `json:"login"`
		ProfileURL string `json:"html_url"`
		Name       string `json:"name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, err
	}

	u := &providerUser{
		ID:         user.ID,
		Email:      user.Email,
		Provider:   "github",
		Name:       user.Name,
		ProfileURL: user.ProfileURL,
	}
	if u.Name == "" {
		u.Name = user.Login
	}
	return u, nil
}

func GithubProvider(clientID, clientSecret string) Provider {
	return Provider{
		Name:         "GitHub",
		Codename:     "github",
		fetchUser:    fetchGithubUser,
		clientID:     clientID,
		clientSecret: clientSecret,
		endpoint: oauth2.Endpoint{
			AuthURL:  "https://github.com/login/oauth/authorize",
			TokenURL: "https://github.com/login/oauth/access_token",
		},
		// https://developer.github.com/v3/oauth/#scopes
		scopes: []string{"email", "public_repo", "repo"},
	}
}
