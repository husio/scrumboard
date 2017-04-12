package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/garyburd/redigo/redis"
)

type RedisCache struct {
	pool *redis.Pool
}

var _ Cache = (*RedisCache)(nil)

func NewRedisCache(pool *redis.Pool) *RedisCache {
	return &RedisCache{
		pool: pool,
	}
}

func (rcs *RedisCache) Get(ctx context.Context, key string, dest interface{}) error {
	rc := rcs.pool.Get()
	defer rc.Close()

	switch raw, err := redis.Bytes(rc.Do("GET", key)); err {
	case nil:
		if err := json.Unmarshal(raw, dest); err != nil {
			return fmt.Errorf("cannot deserialize: %s", err)
		}
		return nil
	case redis.ErrNil:
		return ErrMiss
	default:
		return fmt.Errorf("redis failed: %s", err)
	}
}

func (rcs *RedisCache) Set(ctx context.Context, key string, value interface{}, exp time.Duration) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("cannot serialize: %s", err)
	}

	rc := rcs.pool.Get()
	defer rc.Close()

	if _, err := rc.Do("SET", key, raw, "PX", int(exp/time.Millisecond)); err != nil {
		return fmt.Errorf("redis failed: %s", err)
	}
	return nil
}

func (rcs *RedisCache) Add(ctx context.Context, key string, value interface{}, exp time.Duration) error {
	raw, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("cannot serialize: %s", err)
	}

	rc := rcs.pool.Get()
	defer rc.Close()

	switch resp, err := redis.Bytes(rc.Do("SET", key, raw, "PX", int(exp/time.Millisecond), "NX")); err {
	case nil, redis.ErrNil:
		// if set was successful, resp will be OK and not nil. From
		// redis documentation http://redis.io/commands/set
		//
		// > Simple string reply: OK if SET was executed correctly.
		// > Null reply: a Null Bulk Reply is returned if the SET
		// > operation was not performed because the user specified the
		// > NX or XX option but the condition was not met.
		if resp == nil {
			return ErrConflict
		}
		return nil
	default:
		return fmt.Errorf("redis failed: %s", err)
	}
}

func (rcs *RedisCache) Del(ctx context.Context, key string) error {
	rc := rcs.pool.Get()
	defer rc.Close()

	n, err := redis.Int(rc.Do("DEL", key))
	if err != nil {
		return fmt.Errorf("redis failed: %s", err)
	}
	if n == 0 {
		return ErrMiss
	}
	return nil
}
