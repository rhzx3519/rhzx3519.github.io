#!/usr/bin/env bash

set -e
trap exit INT

SHELL_DIR=$(cd "$(dirname "$0")";pwd)
DOCS_DIR=$SHELL_DIR/docs

(
  cd $DOCS_DIR
  bundle install
  bundle exec jekyll serve --trace
)
