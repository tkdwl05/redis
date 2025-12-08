# Makefile for Redis Modules
# Builds: cachelock.so, taskqueue.so, distlock.so

# Detect OS
uname_S := $(shell sh -c 'uname -s 2>/dev/null || echo not')

# Compiler settings
CC=gcc
LD=ld

# Compile flags for Linux / macOS
ifeq ($(uname_S),Linux)
	SHOBJ_CFLAGS = -W -Wall -fno-common -g -ggdb -std=c99 -O2 -fPIC
	SHOBJ_LDFLAGS = -shared
else
	SHOBJ_CFLAGS = -W -Wall -dynamic -fno-common -g -ggdb -std=c99 -O2
	SHOBJ_LDFLAGS = -bundle -undefined dynamic_lookup
endif

# Module targets
all: cachelock.so taskqueue.so distlock.so

# Cache Lock Module
cachelock.so: cachelock.o
	$(LD) -o $@ $< $(SHOBJ_LDFLAGS) -lc

cachelock.o: cachelock.c ../redismodule.h
	$(CC) -I. $(SHOBJ_CFLAGS) -c cachelock.c -o cachelock.o

# Task Queue Module
taskqueue.so: taskqueue.o
	$(LD) -o $@ $< $(SHOBJ_LDFLAGS) -lc

taskqueue.o: taskqueue.c ../redismodule.h
	$(CC) -I. $(SHOBJ_CFLAGS) -c taskqueue.c -o taskqueue.o

# Distributed Lock Module
distlock.so: distlock.o
	$(LD) -o $@ $< $(SHOBJ_LDFLAGS) -lc

distlock.o: distlock.c ../redismodule.h
	$(CC) -I. $(SHOBJ_CFLAGS) -c distlock.c -o distlock.o

# Clean
clean:
	rm -f *.o *.so

# Test
test: all
	@echo "Modules built successfully!"
	@echo ""
	@echo "To load in Redis:"
	@echo "  redis-server --loadmodule ./cachelock.so \\"
	@echo "               --loadmodule ./taskqueue.so \\"
	@echo "               --loadmodule ./distlock.so"

.PHONY: all clean test
