#!/bin/bash

set -o pipefail

declare LOG_DEBUG="$LOG_DEBUG"

log(){
  local LEVEL="${1^^}" && shift
  [ "$LEVEL" != "DEBUG" ] || [ ! -z "$LOG_DEBUG" ] || return 0 
  echo "[ $(date -R) ] $LEVEL - $*" >&2
}

#kubectl(){
#  log DEBUG "kubectl $*"
#  "$(which kubectl)" "$@"
#}

leader_elect(){
  local LEADER_LIFETIME=${LEADER_LIFETIME:-60} \
    LEADER_RENEW="${LEADER_RENEW:-20}" \
    LEADER_HOLDER="${LEADER_HOLDER:-configmap/leader-election}" \
    MEMBER="${MEMBER:-$HOSTNAME}" \
    LEADER_ANNOTATION="${LEADER_ANNOTATION:-leader}" \
    LEADER_EXPIRES_ANNOTATION="$LEADER_EXPIRES_ANNOTATION" \
    LEADER_EXEC_ARGS=()

  while ARG="$1" && shift; do
    case "$ARG" in
    "--holder")
      LEADER_HOLDER="$1" && shift || return 1
      ;;
    "--member")
      MEMBER="$1" && shift || return 1
      ;;
    "--lifetime")
      LEADER_LIFETIME="$1" && shift || return 1
      ;;
    "--renew")
      LEADER_RENEW="$1" && shift || return 1
      ;;
    "--annotation")
      LEADER_ANNOTATION="$1" && shift || return 1
      ;;
    "--expires-annotation")
      LEADER_EXPIRES_ANNOTATION="$1" && shift || return 1
      ;;
    "--debug")
      LOG_DEBUG='Y'
      ;;
    "--")
      LEADER_EXEC_ARGS=("${LEADER_EXEC_ARGS[@]}" "$@")
      break
      ;;
    *)
      LEADER_EXEC_ARGS=("${LEADER_EXEC_ARGS[@]}" "$ARG")
      ;;
    esac
  done
  local LEADER_EXPIRES_ANNOTATION="${LEADER_EXPIRES_ANNOTATION:-${LEADER_ANNOTATION:-leader}.expires}"

  local RESOURCE_VERSION LEADER_EXPIRES LEADER_MEMBER NOW LEADER_EXEC_PID ROLE_ACTIVE

  leader_renew(){
    local EXPIRES="$((NOW + LEADER_LIFETIME))"
    VERSION="$(kubectl annotate "$LEADER_HOLDER" "$LEADER_ANNOTATION"="$MEMBER" "$LEADER_EXPIRES_ANNOTATION"="$EXPIRES" --resource-version="$RESOURCE_VERSION" --overwrite -o jsonpath="{.metadata.resourceVersion}")"
    [ ! -z "$VERSION" ] && RESOURCE_VERSION="$VERSION" && LEADER_MEMBER="$MEMBER" && LEADER_EXPIRES="$EXPIRES"
  }

  while true; do
      read -r RESOURCE_VERSION LEADER_EXPIRES LEADER_MEMBER < <(export LEADER_ANNOTATION LEADER_EXPIRES_ANNOTATION; kubectl get "$LEADER_HOLDER" -o json --ignore-not-found | \
          jq -r '"\(.metadata.resourceVersion) \(.metadata.annotations[env.LEADER_EXPIRES_ANNOTATION]//0) \(.metadata.annotations[env.LEADER_ANNOTATION]//"")"')

      [ ! -z "$RESOURCE_VERSION" ] || {
          log ERR "$MEMBER: $LEADER_HOLDER not exists"
          continue
      }

      NOW="$(date +%s)" && (( LEADER_EXPIRES > NOW )) || {
          log INFO "$MEMBER: new election"
          leader_renew || continue
      }

      local WAIT_SECONDS="$(( LEADER_EXPIRES - NOW ))"
      if [ "$LEADER_MEMBER" == "$MEMBER" ]; then
          (( LEADER_EXPIRES - LEADER_LIFETIME + LEADER_RENEW <= NOW )) && {
              log DEBUG "$MEMBER: leader renew"
              leader_renew || continue
          }
          trap "log INFO '$MEMBER: leaving'; ${LEADER_EXEC_PID:+kill -TERM $LEADER_EXEC_PID 2>/dev/null;}kubectl annotate '$LEADER_HOLDER' '$LEADER_EXPIRES_ANNOTATION=0' --resource-version='$RESOURCE_VERSION' --overwrite" EXIT          
          (( WAIT_SECONDS =  LEADER_EXPIRES - LEADER_LIFETIME + LEADER_RENEW - NOW ))

          [ "$ROLE_ACTIVE" == "leader" ] || {
            log INFO "$MEMBER: entering leader"
            ROLE_ACTIVE='leader'
          }
          [ ! -z "$LEADER_EXEC_PID" ] && kill -0 "$LEADER_EXEC_PID" 2>/dev/null || [ -z "$LEADER_EXEC_ARGS" ] || {
            if [ -z "$LEADER_EXEC_PID" ]; then
              log INFO "$MEMBER: starting - ${LEADER_EXEC_ARGS[*]}"
            else
              log INFO "$MEMBER: restarting - ${LEADER_EXEC_ARGS[*]}"
            fi
            "${LEADER_EXEC_ARGS[@]}" & LEADER_EXEC_PID="$!"
          }
      else
        log DEBUG "$MEMBER: leader is $LEADER_MEMBER"

        [ "$ROLE_ACTIVE" == "leader" ] && {
          log INFO "$MEMBER: cleaning up" && trap - EXIT
          [ ! -z "$LEADER_EXEC_PID" ] && {
            kill -TERM $LEADER_EXEC_PID 2>/dev/null
            LEADER_EXEC_PID=''
          }
        }
        [ "$ROLE_ACTIVE" == "follower" ] || {
          log INFO "$MEMBER: entering follower, leader=$LEADER_MEMBER"
          ROLE_ACTIVE='follower'
        }
      fi
      read -r -t "$WAIT_SECONDS" _ && while read -r -t .1 _; do :; done
  done < <(while true; do kubectl get "$LEADER_HOLDER" -o name --no-headers --watch-only; done)
}

leader_elect "$@"
