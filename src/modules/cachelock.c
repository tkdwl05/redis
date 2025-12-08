/*
 * Cache Stampede Prevention Module for Redis
 *
 * This module implements cache stampede prevention using mutex-based locking.
 * It provides three commands:
 * - CACHE.LOCK: Acquire a lock for cache loading
 * - CACHE.SET: Set cache value and release lock
 * - CACHE.GET: Get cached value
 *
 * Author: tkdwl05
 * Date: 2025-12-08
 */

#include "../redismodule.h"
#include <stdlib.h>
#include <string.h>

/* CACHE.LOCK key ttl_ms loader_timeout_ms
 *
 * Attempts to acquire a mutex lock for cache loading to prevent stampede.
 *
 * Returns:
 * - "LOAD" if this client should load data from DB
 * - "WAIT" if another client is already loading
 *
 * Implementation:
 * Uses SET lock:{key} 1 NX PX ttl_ms internally
 */
int CacheLock_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                           int argc) {
  if (argc != 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *key = argv[1];
  long long ttl_ms;
  long long loader_timeout_ms;

  if (RedisModule_StringToLongLong(argv[2], &ttl_ms) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid ttl_ms");
  }
  if (RedisModule_StringToLongLong(argv[3], &loader_timeout_ms) !=
      REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid loader_timeout_ms");
  }

  /* Build lock key: "lock:{original_key}" */
  RedisModuleString *lock_key = RedisModule_CreateStringPrintf(
      ctx, "lock:%s", RedisModule_StringPtrLen(key, NULL));

  /* Try to acquire lock using SET NX PX */
  RedisModuleCallReply *reply =
      RedisModule_Call(ctx, "SET", "scccl", lock_key, "1", "NX", "PX", ttl_ms);

  if (reply == NULL) {
    RedisModule_FreeString(ctx, lock_key);
    return RedisModule_ReplyWithError(ctx, "ERR failed to acquire lock");
  }

  int reply_type = RedisModule_CallReplyType(reply);
  RedisModule_FreeCallReply(reply);
  RedisModule_FreeString(ctx, lock_key);

  if (reply_type == REDISMODULE_REPLY_NULL) {
    /* Lock already held by another client */
    return RedisModule_ReplyWithSimpleString(ctx, "WAIT");
  } else {
    /* Lock acquired successfully */
    return RedisModule_ReplyWithSimpleString(ctx, "LOAD");
  }
}

/* CACHE.SET key value ttl_ms
 *
 * Sets the cache value and releases the lock.
 * This implements write-through caching.
 *
 * Returns: OK on success
 */
int CacheSet_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                          int argc) {
  if (argc != 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *key = argv[1];
  RedisModuleString *value = argv[2];
  long long ttl_ms;

  if (RedisModule_StringToLongLong(argv[3], &ttl_ms) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid ttl_ms");
  }

  /* Set the cache value with TTL */
  RedisModuleCallReply *set_reply =
      RedisModule_Call(ctx, "SET", "sscl", key, value, "PX", ttl_ms);

  if (set_reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to set cache");
  }
  RedisModule_FreeCallReply(set_reply);

  /* Release the lock by deleting lock key */
  RedisModuleString *lock_key = RedisModule_CreateStringPrintf(
      ctx, "lock:%s", RedisModule_StringPtrLen(key, NULL));

  RedisModuleCallReply *del_reply = RedisModule_Call(ctx, "DEL", "s", lock_key);
  RedisModule_FreeString(ctx, lock_key);

  if (del_reply != NULL) {
    RedisModule_FreeCallReply(del_reply);
  }

  return RedisModule_ReplyWithSimpleString(ctx, "OK");
}

/* CACHE.GET key
 *
 * Gets the cached value.
 *
 * Returns:
 * - The cached value if exists
 * - NULL if not in cache
 */
int CacheGet_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                          int argc) {
  if (argc != 2) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *key = argv[1];

  /* Get the value from Redis */
  RedisModuleCallReply *reply = RedisModule_Call(ctx, "GET", "s", key);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to get cache");
  }

  /* Forward the reply to the client */
  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* Module initialization */
int RedisModule_OnLoad(RedisModuleCtx *ctx, RedisModuleString **argv,
                       int argc) {
  REDISMODULE_NOT_USED(argv);
  REDISMODULE_NOT_USED(argc);

  if (RedisModule_Init(ctx, "cachelock", 1, REDISMODULE_APIVER_1) ==
      REDISMODULE_ERR)
    return REDISMODULE_ERR;

  /* Register CACHE.LOCK command */
  if (RedisModule_CreateCommand(ctx, "cache.lock", CacheLock_RedisCommand,
                                "write deny-oom", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  /* Register CACHE.SET command */
  if (RedisModule_CreateCommand(ctx, "cache.set", CacheSet_RedisCommand,
                                "write deny-oom", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  /* Register CACHE.GET command */
  if (RedisModule_CreateCommand(ctx, "cache.get", CacheGet_RedisCommand,
                                "readonly fast", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  return REDISMODULE_OK;
}
