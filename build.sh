#!/bin/bash
POSTGRES_IMAGE=postgres:11-alpine 
CLAIR_VERSION=v2.1.6 
CLAIR_LOCAL_SCAN_IMAGE=clair-db-downloader

# Pull the DB image
docker pull $POSTGRES_IMAGE

# Clean old dump
rm vulnerability.sql
rm clear.sql

# Start the DB
mkdir -pv ./database 
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
docker run -d --name clair-temp-db \
    -e 'PGDATA=/var/lib/postgresql/clair' \
    -e POSTGRES_PASSWORD=password \
    -v "$DIR/database:/var/lib/postgresql/clair" \
    $POSTGRES_IMAGE

# Loop until DB is ready
until docker run --rm -it --link clair-temp-db:postgres -e PGPASSWORD=password $POSTGRES_IMAGE pg_isready -U postgres -h postgres; do sleep 1; done

# Start clair
docker run -d --name clair-db-downloader \
    --link clair-temp-db:postgres \
    -v "$DIR/clair/config.yaml:/config/config.yaml" \
    quay.io/coreos/clair:v2.1.6 -config /config/config.yaml

# TODO: Check that it has pulled definitions
# For now, simply sleep 10 min
date
sleep 600
date

# Create the dumps - likely faster if run in the same container
docker exec clair-temp-db /bin/sh -c  "pg_dump -U postgres -a -t feature -t keyvalue -t namespace -t schema_migrations -t vulnerability -t vulnerability_fixedin_feature" > vulnerability.sql  
docker exec clair-temp-db /bin/sh -c "pg_dump -U postgres -c -s" > clear.sql

# Spit out logs for debugging/CI
docker logs clair-db-downloader

# Cleanup
docker kill clair-db-downloader
docker rm clair-db-downloader
docker kill clair-temp-db
docker rm clair-temp-db
