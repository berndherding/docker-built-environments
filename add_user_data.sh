#!/bin/bash

# a script for replacing the variables REGISTRY_IP 
# and COMPOSE_YAML in a cloud formation template

REGISTRY_IP=$1
YAML_FILE=$2
TMPL_FILE=$3

YAML_TEXT=$(cat "$YAML_FILE" | sed -e 's/"/\\"/g' | awk '
  {
    print "\""$0"\\n\","
  }
')

(
  awk '/.*COMPOSE_YAML.*/ {p=1}       !p' "$TMPL_FILE"
  echo "$YAML_TEXT"
  awk '/.*COMPOSE_YAML.*/ {p=1; next}  p' "$TMPL_FILE"
) | sed -e "s/REGISTRY_IP/$REGISTRY_IP/"
