#!/bin/bash

log() {
    sev=$1
    shift
    msg="$@"
    ts=$(date +"%Y/%m/%d %H:%M:%S")
    echo -e "$ts : $sev : $msg"
}

loginfo() {
    log "INFO" "$@"
}

logwarn() {
    log "${MX_BOLD}WARNING${MX_RESET}" "$@"
}

logerr() {
    log "${MX_BOLD}ERROR${MX_RESET}" "$@"
}
