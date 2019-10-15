PACK?=$(shell which pack)

.PHONY: builder test

test: builder
	./build.sh ./app app lifecycle-cache-error/app

builder:
	$(PACK) create-builder --builder-config builder.toml lifecycle-cache-error/builder
