/*
 * Task Queue Module for Redis
 *
 * This module implements a task queue using Redis Streams with consumer groups.
 * Provides commands: TASK.PUBLISH, TASK.CONSUME, TASK.ACK, TASK.RETRY
 *
 * Author: tkdwl05
 * Date: 2025-12-08
 */

#include "../redismodule.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* TASK.PUBLISH stream payload [retry_count]
 *
 * Publishes a task to the stream with metadata.
 * Returns: Stream entry ID
 */
int TaskPublish_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                             int argc) {
  if (argc < 3 || argc > 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *stream = argv[1];
  RedisModuleString *payload = argv[2];
  long long retry_count = 0;

  if (argc == 4) {
    if (RedisModule_StringToLongLong(argv[3], &retry_count) != REDISMODULE_OK) {
      return RedisModule_ReplyWithError(ctx, "ERR invalid retry_count");
    }
  }

  /* Get current timestamp */
  long long timestamp = (long long)time(NULL);

  /* XADD stream * payload <data> timestamp <ts> retry_count <rc> */
  RedisModuleCallReply *reply =
      RedisModule_Call(ctx, "XADD", "sccsclcl", stream, "*", "payload", payload,
                       "timestamp", timestamp, "retry_count", retry_count);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to publish task");
  }

  /* Forward the stream ID to client */
  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* TASK.CONSUME consumer_group consumer_name stream [count] [block_ms]
 *
 * Consumes tasks from stream using consumer groups.
 * Returns: Array of stream entries
 */
int TaskConsume_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                             int argc) {
  if (argc < 4 || argc > 6) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *consumer_group = argv[1];
  RedisModuleString *consumer_name = argv[2];
  RedisModuleString *stream = argv[3];
  long long count = 1;
  long long block_ms = 0;

  if (argc >= 5) {
    if (RedisModule_StringToLongLong(argv[4], &count) != REDISMODULE_OK) {
      return RedisModule_ReplyWithError(ctx, "ERR invalid count");
    }
  }

  if (argc == 6) {
    if (RedisModule_StringToLongLong(argv[5], &block_ms) != REDISMODULE_OK) {
      return RedisModule_ReplyWithError(ctx, "ERR invalid block_ms");
    }
  }

  /* XREADGROUP GROUP consumer_group consumer_name [BLOCK ms] COUNT count
   * STREAMS stream > */
  RedisModuleCallReply *reply;
  if (block_ms > 0) {
    reply = RedisModule_Call(ctx, "XREADGROUP", "cssclclcsc", "GROUP",
                             consumer_group, consumer_name, "BLOCK", block_ms,
                             "COUNT", count, "STREAMS", stream, ">");
  } else {
    reply =
        RedisModule_Call(ctx, "XREADGROUP", "cssclcsc", "GROUP", consumer_group,
                         consumer_name, "COUNT", count, "STREAMS", stream, ">");
  }

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to consume tasks");
  }

  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* TASK.ACK stream consumer_group stream_id
 *
 * Acknowledges task completion.
 * Returns: Number of messages acknowledged
 */
int TaskAck_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                         int argc) {
  if (argc != 4) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *stream = argv[1];
  RedisModuleString *consumer_group = argv[2];
  RedisModuleString *stream_id = argv[3];

  /* XACK stream consumer_group stream_id */
  RedisModuleCallReply *reply =
      RedisModule_Call(ctx, "XACK", "sss", stream, consumer_group, stream_id);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to acknowledge task");
  }

  RedisModule_ReplyWithCallReply(ctx, reply);
  RedisModule_FreeCallReply(reply);

  return REDISMODULE_OK;
}

/* TASK.RETRY stream stream_id payload retry_count retry_stream
 * dead_letter_stream max_retries
 *
 * Retries a failed task or moves to dead-letter queue.
 */
int TaskRetry_RedisCommand(RedisModuleCtx *ctx, RedisModuleString **argv,
                           int argc) {
  if (argc != 8) {
    return RedisModule_WrongArity(ctx);
  }

  RedisModuleString *stream = argv[1];
  RedisModuleString *stream_id = argv[2];
  RedisModuleString *payload = argv[3];
  long long retry_count, max_retries;
  RedisModuleString *retry_stream = argv[5];
  RedisModuleString *dead_letter_stream = argv[6];

  if (RedisModule_StringToLongLong(argv[4], &retry_count) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid retry_count");
  }
  if (RedisModule_StringToLongLong(argv[7], &max_retries) != REDISMODULE_OK) {
    return RedisModule_ReplyWithError(ctx, "ERR invalid max_retries");
  }

  long long new_retry_count = retry_count + 1;
  RedisModuleString *target_stream;

  if (new_retry_count < max_retries) {
    target_stream = retry_stream;
  } else {
    target_stream = dead_letter_stream;
  }

  /* Add to target stream */
  long long timestamp = (long long)time(NULL);
  RedisModuleCallReply *reply =
      RedisModule_Call(ctx, "XADD", "sccscsclcl", target_stream, "*", "payload",
                       payload, "original_id", stream_id, "timestamp",
                       timestamp, "retry_count", new_retry_count);

  if (reply == NULL) {
    return RedisModule_ReplyWithError(ctx, "ERR failed to retry task");
  }

  RedisModule_FreeCallReply(reply);
  return RedisModule_ReplyWithSimpleString(ctx, "OK");
}

/* Module initialization */
int RedisModule_OnLoad(RedisModuleCtx *ctx, RedisModuleString **argv,
                       int argc) {
  REDISMODULE_NOT_USED(argv);
  REDISMODULE_NOT_USED(argc);

  if (RedisModule_Init(ctx, "taskqueue", 1, REDISMODULE_APIVER_1) ==
      REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "task.publish", TaskPublish_RedisCommand,
                                "write deny-oom", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "task.consume", TaskConsume_RedisCommand,
                                "readonly", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "task.ack", TaskAck_RedisCommand, "write",
                                1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  if (RedisModule_CreateCommand(ctx, "task.retry", TaskRetry_RedisCommand,
                                "write deny-oom", 1, 1, 1) == REDISMODULE_ERR)
    return REDISMODULE_ERR;

  return REDISMODULE_OK;
}
