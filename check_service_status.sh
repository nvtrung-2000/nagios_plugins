#!/bin/bash

NAGIOS_OK=0
NAGIOS_WARNING=1
NAGIOS_CRITICAL=2
NAGIOS_UNKNOWN=3
SERVICE=""

usage() {
    printf "Usage: %s -s|--service <service_name>\n" "$0" >&2
    exit $NAGIOS_UNKNOWN
}

check_service_status() {
    local service="$1"

    if systemctl is-active --quiet "$service"; then
        printf "OK - %s is running\n" "$service"
        return $NAGIOS_OK
    elif systemctl is-enabled --quiet "$service"; then
        printf "CRITICAL - %s is installed but not running\n" "$service"
        return $NAGIOS_CRITICAL
    else
        printf "CRITICAL - %s is not installed or not running\n" "$service"
        return $NAGIOS_CRITICAL
    fi
}

main() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -s|--service)
                SERVICE="$2"
                shift 2
                ;;
            -*)
                printf "Unknown option: %s\n" "$1" >&2
                usage
                ;;
            *)
                printf "Invalid input\n" >&2
                usage
                ;;
        esac
    done

    if [[ -z "$SERVICE" ]]; then
        printf "Error: Service name is required\n" >&2
        usage
    fi

    check_service_status "$SERVICE"
    exit $?
}

main "$@"
