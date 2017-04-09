package cache

import (
	"errors"
	"time"

	"golang.org/x/net/context"
)

// Cache represents high level cache client with custom serialization
// for stored data. It is important is that it represents cache. Provided
// implementation might flush it's memory at any time and user must be prepared
// to loose all stored data.
type Cache interface {
	// Get value stored under given key. Returns ErrMiss if key is not
	// used.
	Get(ctx context.Context, key string, dest interface{}) error

	// Set value under given key. If key is already in use, overwrite it's
	// value with given one and set new expiration time.
	Set(ctx context.Context, key string, value interface{}, exp time.Duration) error

	// Add set value under given key only if key is not used. It returns
	// ErrConflict if trying to set value for key that is already in use.
	Add(ctx context.Context, key string, value interface{}, exp time.Duration) error

	// Del deletes value under given key. It returns ErrCacheMiss if given
	// key is not used.
	Del(ctx context.Context, key string) error
}

var (
	// ErrMiss is returned when performing operation on key is not in use.
	ErrMiss = errors.New("cache miss")

	// ErrConflict is returned when performing operation on existing key,
	// which cause conflict.
	ErrConflict = errors.New("conflict")
)
