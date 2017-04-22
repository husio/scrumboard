package scrumboard

import (
	"math/rand"
	"sync"
	"time"
)

var boardnames = boardNamesGenerator{
	rnd: rand.New(rand.NewSource(time.Now().UnixNano())),
	names: []string{
		"Sisters of the Outpost",
		"The Power of Moradin",
		"The Wondrous Revenge from Beyond",
		"Bandit of the Marshes",
		"The Sage Below the Festival",
		"The Vengeful Key Expedition",
		"The Ghoul Below the Charming Tavern",
		"The Crown from Above",
		"The Mage Within the Library",
		"Messenger of the Unspeakable Circus",
		"Under the Traveling Arena",
		"The Key of Moradin",
		"Within the Lingering Halls",
		"The Rage Bribe",
		"Within Moradin's Grove",
		"The Strength of Corellon",
		"Under Bahamut's Realm",
		"The Scorched Verse Ring",
		"Through Gruumsh's Stockade",
		"Before the Fair",
	},
}

type boardNamesGenerator struct {
	mu    sync.Mutex
	rnd   *rand.Rand
	names []string
}

// Random returns one of predefined names
func (b *boardNamesGenerator) Random() string {
	b.mu.Lock()
	defer b.mu.Unlock()

	n := b.rnd.Intn(len(b.names))
	return b.names[n]
}
