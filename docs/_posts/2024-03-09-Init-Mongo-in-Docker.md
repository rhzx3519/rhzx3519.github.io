---
layout: post
title:  "Init Mongo in Docker"
date:   2024-03-09 13:30:00 +1100
categories: database
tags: mongo docker
---

This artile introduces a method about how to initialize data for mongodb in docker. We will use `mongoimport` 
to import data after the mongodb started in docker.    
We start another container used to execute `mongoimport`, which is mongo-seed.

```yaml
version: "3.5"
services:
  mongo:
    image: mongo:latest
    environment:
      MONGO_INITDB_ROOT_USERNAME:
      MONGO_INITDB_ROOT_PASSWORD:
    ports:
      - "27018:27017"
    networks:
      - go-mongo
    healthcheck:
      test: echo 'db.runCommand("ping").ok' | mongosh localhost:27017/testing --quiet
  mongo-seed:
    image: mongo:latest
    restart: no
    environment:
      MONGO_HOSTNAME: 'mongo'
      MONGO_DBNAME: 'testing'
    volumes:
      - ./db/mongo/:/mongo-seed/
    command: |
      bash /mongo-seed/mongo_seed.sh
    depends_on:
      - mongo
    networks:
      - go-mongo

networks:
  go-mongo: {}

```

`mongo_seed.sh` will read _json_ files and import it into mongodb.
```shell
#!/bin/bash

cd "$(dirname "$0")"
SHELL_DIR="$(pwd)"

# load dotenv
if [ -f `${SHELL_DIR}/.env` ]
then
  export $(cat .env | xargs)
fi

for jsonfile in `ls -l ${SHELL_DIR} | grep '^-' | grep '.json$' | awk '{print $NF}'`
do
  mongoimport --host $MONGO_HOST --port $MONGO_PORT \
    --db $MONGO_DB \
    --file $jsonfile --collection ${jsonfile%.*}
done
```


# Reference
1. [mongo-in-docker](https://github.com/rhzx3519/mongo-in-docker)
