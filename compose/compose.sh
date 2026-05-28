#!/bin/bash

# List of directories containing compose.yaml files
COMPOSE_DIRS=(
  "/path/to/first/project"
  "/path/to/second/project"
  "/path/to/third/project"
  # Add more paths as needed
)

# Flag to check if docker image has been updated in any directory
IMAGE_UPDATE=false

process_compose_dir() {
  local dir="$1"
  echo "Processing directory: $dir"

  if [ -f "$dir/compose.yaml" ] || [ -f "$dir/docker-compose.yml" ]; then
    cd "$dir" || return

    # Get image names from compose config
    IMAGES=$(docker compose config | grep 'image:' | awk '{print $2}')
    declare -A DIGESTS_BEFORE

    for img in $IMAGES; do
      DIGESTS_BEFORE["$img"]=$(docker image inspect "$img" --format='{{.Id}}' 2>/dev/null)
    done

    echo "Running docker compose pull in $dir"
    docker compose pull

    IMAGE_CHANGE=false
    for img in $IMAGES; do
      NEW_ID=$(docker image inspect "$img" --format='{{.Id}}' 2>/dev/null)
      if [ "${DIGESTS_BEFORE[$img]}" != "$NEW_ID" ]; then
        IMAGE_CHANGE=true
        break
      fi
    done

    if [ "$IMAGE_CHANGE" = "true" ]; then
      echo "Image changed — running docker compose up -d --force-recreate in $dir"
      docker compose up -d --force-recreate
      IMAGE_UPDATE=true
    else
      echo "No image changes — skipping docker compose up -d in $dir"
    fi

    echo ""
  else
    echo "No compose file found in $dir — skipping."
  fi
}

for dir in "${COMPOSE_DIRS[@]}"; do
  process_compose_dir "$dir"
done

if [ "$IMAGE_UPDATE" = "true" ]; then
  echo "At least one update detected — running docker system prune -a -f"
  docker system prune -a -f
else
  echo "No image updates detected — skipping prune"
fi
