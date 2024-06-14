#!/bin/bash

chmod +x wizardscan.sh

SCRIPT_NAME="wizardscan.sh"

if ! command -v shc &> /dev/null
then
    sudo apt-get update -y
    sudo apt-get install -y shc
fi

if [[ ! -f $SCRIPT_NAME ]]; then
    exit 1
fi

if [[ ! -x $SCRIPT_NAME ]]; then
    chmod +x $SCRIPT_NAME
fi

shc -f $SCRIPT_NAME -o wizardscan

if [[ -f "wizardscan" ]]; then
    sudo mv wizardscan /usr/local/bin/
else
    exit 1
fi

if [[ ! -f "/usr/local/bin/wizardscan" ]]; then
    exit 1
fi
