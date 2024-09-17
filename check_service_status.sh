#!/bin/bash

usage() {
    echo "Usage: $0 -s|--service <service_name>"
    exit 3 

if [ $# -eq 0 ]; then
    usage
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            echo "Invalid input"
            usage
            ;;
    esac
done

if [ -z "$SERVICE" ]; then
    echo "Error: Service name is required"
    usage
fi

if systemctl is-active --quiet "$SERVICE"; then
    echo "OK - $SERVICE is running"
    exit 0 
else
    echo "CRITICAL - $SERVICE is not running"
    exit 2
fi
