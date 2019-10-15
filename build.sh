#!/usr/bin/env bash

CACHE_METHOD=image

BUILDER_IMAGE=lifecycle-cache-error/builder
RUN_IMAGE=cnbs/run:bionic

set -euo pipefail

COLOR_OFF='\033[0m'
CYAN='\033[0;36m'

# shellcheck disable=SC2054 disable=SC2191
DOCKER_DAEMON_ACCESS=( --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,bind-propagation=rprivate,readonly --user root )

PACK_UID=1000
PACK_GID=1000

APP_VOLUME="lifecycle-app"
LAYERS_VOLUME="lifecycle-layers"
CACHE_IMAGE="lifecycle-cache-error/layers-cache"
CACHE_VOLUME="layers-cache"

if [[ "${DEBUG:-}" == "true" ]]; then
  set -x
fi

prefix(){
  local label
  label="$1"

  # shellcheck disable=SC2059
  printf "${CYAN}===> ${label^^}${COLOR_OFF}\n"

  awk "{ print \"[${CYAN}${label,,}${COLOR_OFF}] \" \$0 }"
}

docker_run() {
  docker run \
         --attach "STDOUT" \
         --attach "STDERR" \
         --rm \
         --mount type=volume,src="$APP_VOLUME",dst=/workspace \
         --mount type=volume,src="$LAYERS_VOLUME",dst=/layers \
         "$@"
}

detect() {
  local app_dir app_name container_name
  app_dir="$1"
  app_name="$2"
  container_name="detect-${app_name}"

  docker create \
         --name "$container_name" \
         --rm \
         --mount type=volume,src="$APP_VOLUME",dst=/workspace \
         --mount type=volume,src="$LAYERS_VOLUME",dst=/layers \
         "$BUILDER_IMAGE" \
         /lifecycle/detector \
         >/dev/null

  # we need to populate the lifecycle-app volume with the app before this container runs.
  tar --owner $PACK_UID --group $PACK_GID -C "${app_dir}/." -cf - . \
    | docker cp - "$container_name":/workspace

  docker start --attach "$container_name"
}

restore() {
  local app_name
  app_name="$1"

  if [[ "$CACHE_METHOD" == volume ]]; then
    docker_run \
      -v "$CACHE_VOLUME:/cache" \
      "${DOCKER_DAEMON_ACCESS[@]}" \
      "$BUILDER_IMAGE" \
      /lifecycle/restorer \
      -path /cache
  else
    docker_run \
      "${DOCKER_DAEMON_ACCESS[@]}" \
      "$BUILDER_IMAGE" \
      /lifecycle/restorer \
      -image "$CACHE_IMAGE"
  fi
}

analyze() {
  local image_tag image_repository
  image_tag="$1"
  image_repository="$(cut -d: -f1 <<<"$image_tag")"

  docker_run \
    "${DOCKER_DAEMON_ACCESS[@]}" \
    "$BUILDER_IMAGE" \
    /lifecycle/analyzer \
    -daemon \
    "$image_repository"
}

build() {
  docker_run \
    "$BUILDER_IMAGE" \
    /lifecycle/builder
}

export_image() {
  local image_tag
  image_tag="$1"

  docker_run \
    "${DOCKER_DAEMON_ACCESS[@]}" \
    "$BUILDER_IMAGE" \
    /lifecycle/exporter \
    -image "$RUN_IMAGE" \
    -daemon \
    "$image_tag"
}

cache() {
  local app_name
  app_name="$1"

  if [[ "$CACHE_METHOD" == volume ]]; then
    docker_run \
      -v "$CACHE_VOLUME:/cache" \
      "${DOCKER_DAEMON_ACCESS[@]}" \
      "$BUILDER_IMAGE" \
      /lifecycle/cacher \
      -path /cache
  else
    docker_run \
      "${DOCKER_DAEMON_ACCESS[@]}" \
      "$BUILDER_IMAGE" \
      /lifecycle/cacher \
      -image "$CACHE_IMAGE"
  fi
}

cleanup() {
  {
    docker volume rm "$APP_VOLUME"
    docker volume rm "$LAYERS_VOLUME"
  } | prefix "cleanup"
}

main() {
  local image_tag app_dir app_name

  app_dir="$1"
  app_name="$2"
  image_tag="$3"

  docker pull "$RUN_IMAGE"

  trap cleanup exit
  detect "$app_dir" "$app_name" |& prefix "detect"
  restore "$app_name" |& prefix "restore"
  analyze "$image_tag" |& prefix "analyze"
  build |& prefix "build"
  export_image "$image_tag" |& prefix "export"
  cache "$app_name" |& prefix "cache"
}

main "$@"
