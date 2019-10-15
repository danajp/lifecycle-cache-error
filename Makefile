PACK?=$(shell which pack)

.PHONY: test-cache-image test-cache-volume builder

test-cache-image: builder
	CACHE_METHOD=image ./build.sh ./app app lifecycle-cache-error/app

test-cache-volume: builder
	CACHE_METHOD=volume ./build.sh ./app app lifecycle-cache-error/app

builder:
	$(PACK) create-builder --builder-config builder.toml lifecycle-cache-error/builder
