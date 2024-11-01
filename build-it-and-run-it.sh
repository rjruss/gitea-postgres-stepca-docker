#!/bin/bash
. .env
if [[ $(id -u) -eq 0 ]]; then
    echo "This script is best to run when logged in as user $LOCAL_DOCKER_USER"
    exit 1
fi

INCLUDE_DOCKER_FILE="c_docker_compose.yml"
echo "build base image"
docker compose -f mx-base-img.yml --progress plain build  --no-cache

if docker images | grep -q "base-img"; then
	echo "build step, postgres and gitea together"
	echo "include:" > ${INCLUDE_DOCKER_FILE}
	while read i; do
	echo "  - ${i}" >> ${INCLUDE_DOCKER_FILE}
	done < <(ls *extracted*yml)

	docker compose -f ${INCLUDE_DOCKER_FILE} --progress plain build  --no-cache
	echo "startup"
	docker compose -f ${INCLUDE_DOCKER_FILE} up
else
	echo "some issue building base image exiting"
	exit 1
fi

