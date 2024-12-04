REGISTRY=${REGISTRY:-@container_registry@}
TAG=${TAG:-@tag@}
VERSION=${VERSION:-@version@}

skopeo copy --insecure-policy docker-archive:/dev/stdin "docker://$REGISTRY/$TAG:$VERSION" < @container@
