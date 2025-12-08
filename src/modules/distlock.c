/*
 * Distributed Lock Module for Redis
 *
 * This module implements distributed locks for preventing concurrent
 * execution of batch jobs.
 * Provides commands: LOCK.ACQUIRE, LOCK.RELEASE, LOCK.EXTEND
 *
 * Author: tkdwl05
 * Date: 2025-12-08
 */

#include "../redismodule.h"
#include <string.h>

/* LOCK.ACQUIRE lock_name identifier ttl_ms
 *
 * Acquires a distributed lock.
 * Returns: 1 if acquired, 0 if already held by another process
 */
int LockAcquire_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                             int argc) {
  if (argc != 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *lock_name = argv[1];
  RedisModuleString *identifier = argv[2];
  long long ttl_ms;

  if (RedisModule_StringToLongLong(argv[3], &ttl_ms) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid ttl_ms");
  }

  /* Build lock key */
  RedisModuleString *lock_key = RedisModule_CreateStringPrintf(
      ctx, "lock:%s", RedisModule_StringPtrLen(lock_name, NULL));

  /* SET lock_key identifier NX PX ttl_ms */
  RedisModuleCallReply *reply = RedisModule_Call(
      ctx, "SET", "ssccl", lock_key, identifier, "NX", "PX", ttl_ms);

  RedisModule_FreeString(ctx, lock_key);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to acquire lock");
  }

  int reply_type = RedisModule_CallReplyType(reply);
  RedisModule_FreeCallReply(reply);

  if (reply_type == REDISMODULE_REPLY_NULL) {
    return RedisModule_ReplyWithLongLong(ctx, 0); /* Lock not acquired */
  } else {
    return RedisModule_ReplyWithLongLong(ctx, 1); /* Lock acquired */
  }
}

/* LOCK.RELEASE lock_name identifier
 *
 * Releases a lock atomically (only if holder matches).
 * Uses Lua script for atomicity.
 * Returns: 1 if released, 0 if not held by this identifier
 */
int LockRelease_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                             int argc) {
  if (argc != 3) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *lock_name = argv[1];
  RedisModuleString *identifier = argv[2];

  /* Build lock key */
  RedisModuleString *lock_key = RedisModule_CreateStringPrintf(
      ctx, "lock:%s", RedisModule_StringPtrLen(lock_name, NULL));

  /* Lua script for atomic release */
  const char *lua_script = "if redis.call('get', KEYS[1]) == ARGV[1] then "
                           "return redis.call('del', KEYS[1]) "
                           "else return 0 end";

  RedisModuleCallReply *reply = RedisModule_Call(
      ctx, "EVAL", "clss", lua_script, (long long)1, lock_key, identifier);

  RedisModule_FreeString(ctx, lock_key);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to release lock");
  }

  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* LOCK.EXTEND lock_name identifier ttl_ms
 *
 * Extends lock TTL (for lock renewal).
 * Returns: 1 if extended, 0 if not held by this identifier
 */
int LockExtend_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                            int argc) {
  if (argc != 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *lock_name = argv[1];
  RedisModuleString *identifier = argv[2];
  long long ttl_ms;

  if (RedisModule_StringToLongLong(argv[3], &ttl_ms) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid ttl_ms");
  }

  /* Build lock key */
  RedisModuleString *lock_key = RedisModule_CreateStringPrintf(
      ctx, "lock:%s", RedisModule_StringPtrLen(lock_name, NULL));

  /* Lua script for atomic extend */
  const char *lua_script = "if redis.call('get', KEYS[1]) == ARGV[1] then "
                           "redis.call('pexpire', KEYS[1], ARGV[2]); "
                           "return 1 "
                           "else return 0 end";

  RedisModuleCallReply *reply =
      RedisModule_Call(ctx, "EVAL", "clssl", lua_script, (long long)1, lock_key,
                       identifier, ttl_ms);

  RedisModule_FreeString(ctx, lock_key);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to extend lock");
  }

  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* Module initialization */
int RedisModule_OnLoad(RedisModuleCtx *ctx, RedisModuleString **argv,
                       int argc) {
  REDISMODULE_NOT_USED(argv);
  REDISMODULE_NOT_USED(argc);

  if (RedisModule_Init(ctx, "distlock", 1, REDISMODULE_APIVER_1) ==
      REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "lock.acquire", LockAcquire_RedisCommand,
                                "write deny-oom", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "lock.release", LockRelease_RedisCommand,
                                "write", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "lock.extend", LockExtend_RedisCommand,
                                "write", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  return REDISMODULE_OK;
}
