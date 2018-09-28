#!/bin/bash

set -o pipefail

export LOG_DEBUG="$LOG_DEBUG" EXIT_PROC=''

log(){
  local LEVEL="${1^^}" && shift
  [ "$LEVEL" != "DEBUG" ] || [ ! -z "$LOG_DEBUG" ] || return 0 
  echo "[ $(date -R) ] $LEVEL - $*" >&2
}

#kubectl(){
#  log DEBUG "kubectl $*"
#  "$(which kubectl)" "$@"
#}

export RESOURCE_VERSION='' LEADER_EXPIRES='' LEADER_MEMBER='' LEADER_EXEC_PID='' ROLE_ACTIVE='' TIME_NOW=''

leader_renew(){
  local EXPIRES="$((TIME_NOW + LEADER_LIFETIME))"
  VERSION="$(kubectl annotate "$LEADER_HOLDER" "$LEADER_ANNOTATION"="$MEMBER" "$LEADER_EXPIRES_ANNOTATION"="$EXPIRES" --resource-version="$RESOURCE_VERSION" --overwrite -o jsonpath="{.metadata.resourceVersion}")"
  [ ! -z "$VERSION" ] && export RESOURCE_VERSION="$VERSION" LEADER_MEMBER="$MEMBER" LEADER_EXPIRES="$EXPIRES"
}

leader_enter(){
  log INFO "$MEMBER: entering leader"
  [ -z "$LEADER_ENTER" ] || eval "$LEADER_ENTER" || return 1
}

leader_leave(){
  leader_cleanup
  log INFO "$MEMBER: leaving"
  kubectl annotate "$LEADER_HOLDER" "$LEADER_EXPIRES_ANNOTATION=0" --resource-version="$RESOURCE_VERSION" --overwrite
}

leader_ping(){
  [ ! -z "$LEADER_EXEC_PID" ] && kill -0 "$LEADER_EXEC_PID" 2>/dev/null || [ -z "$LEADER_EXEC_ARGS" ] || {
    if [ -z "$LEADER_EXEC_PID" ]; then
      log INFO "$MEMBER: starting - ${LEADER_EXEC_ARGS[*]}"
      "${LEADER_EXEC_ARGS[@]}" & export LEADER_EXEC_PID="$!"
    elif [[ "${LEADER_EXEC_RESTART,,}" =~ ^(yes|y|true|t|on|1)$ ]]; then
      log INFO "$MEMBER: restarting - ${LEADER_EXEC_ARGS[*]}"
      "${LEADER_EXEC_ARGS[@]}" & export LEADER_EXEC_PID="$!"
    fi
  }  
}

leader_cleanup(){
  log INFO "$MEMBER: cleaning up"
  [ ! -z "$LEADER_EXEC_PID" ] && {
    kill -TERM "$LEADER_EXEC_PID" 2>/dev/null
    export LEADER_EXEC_PID=''
  }
  [ -z "$LEADER_LEAVE" ] || eval "$LEADER_LEAVE" || {
    log ERR "$MEMBER: failed to execute - $LEADER_LEAVE"
  }
}


leader_elect(){
  export LEADER_LIFETIME=${LEADER_LIFETIME:-60} \
    LEADER_RENEW="${LEADER_RENEW:-20}" \
    LEADER_HOLDER="${LEADER_HOLDER:-configmap/leader-election}" \
    MEMBER="${MEMBER:-$HOSTNAME}" \
    LEADER_ANNOTATION="${LEADER_ANNOTATION:-leader}" \
    LEADER_EXPIRES_ANNOTATION="$LEADER_EXPIRES_ANNOTATION" \
    LEADER_EXEC_RESTART="${LEADER_EXEC_RESTART:-Y}" \
    LEADER_ENTER="$LEADER_ENTER" \
    LEADER_LEAVE="$LEADER_LEAVE"

  local LEADER_EXEC_ARGS=()
  while ARG="$1" && shift; do
    case "$ARG" in
    "--holder")
      export LEADER_HOLDER="$1" && shift || return 1
      ;;
    "--member")
      export MEMBER="$1" && shift || return 1
      ;;
    "--lifetime")
      export LEADER_LIFETIME="$1" && shift || return 1
      ;;
    "--renew")
      export LEADER_RENEW="$1" && shift || return 1
      ;;
    "--annotation")
      export LEADER_ANNOTATION="$1" && shift || return 1
      ;;
    "--expires-annotation")
      export LEADER_EXPIRES_ANNOTATION="$1" && shift || return 1
      ;;
    "--enter")
      export LEADER_ENTER="$1" && shift || return 1
      ;;
    "--leave")
      export LEADER_LEAVE="$1" && shift || return 1
      ;;
    "--debug")
      export LOG_DEBUG='Y'
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

  export LEADER_EXPIRES_ANNOTATION="${LEADER_EXPIRES_ANNOTATION:-${LEADER_ANNOTATION:-leader}.expires}"

  while true; do
      read -r RESOURCE_VERSION LEADER_EXPIRES LEADER_MEMBER < <(export LEADER_ANNOTATION LEADER_EXPIRES_ANNOTATION; kubectl get "$LEADER_HOLDER" -o json --ignore-not-found | \
          jq -r '"\(.metadata.resourceVersion) \(.metadata.annotations[env.LEADER_EXPIRES_ANNOTATION]//0) \(.metadata.annotations[env.LEADER_ANNOTATION]//"")"')

      [ ! -z "$RESOURCE_VERSION" ] || {
          log ERR "$MEMBER: $LEADER_HOLDER not exists"
          continue
      }

      export RESOURCE_VERSION LEADER_EXPIRES LEADER_MEMBER TIME_NOW="$(date +%s)" && (( LEADER_EXPIRES > TIME_NOW )) || {
          log INFO "$MEMBER: new election"
          leader_renew || continue
      }

      local WAIT_SECONDS="$(( LEADER_EXPIRES - TIME_NOW ))"
      if [ "$LEADER_MEMBER" == "$MEMBER" ]; then
          (( LEADER_EXPIRES - LEADER_LIFETIME + LEADER_RENEW <= TIME_NOW )) && {
              log DEBUG "$MEMBER: leader renew"
              leader_renew || continue
          }
          trap "RESOURCE_VERSION='$RESOURCE_VERSION' leader_leave" EXIT
          (( WAIT_SECONDS =  LEADER_EXPIRES - LEADER_LIFETIME + LEADER_RENEW - TIME_NOW ))
          [ "$ROLE_ACTIVE" == "leader" ] || {
            leader_enter || { leader_leave && trap - EXIT; continue; }
            export ROLE_ACTIVE='leader'
          }
          leader_ping
      else
        log DEBUG "$MEMBER: leader is $LEADER_MEMBER"

        [ "$ROLE_ACTIVE" == "leader" ] && leader_cleanup && trap - EXIT
        [ "$ROLE_ACTIVE" == "follower" ] || {
          log INFO "$MEMBER: entering follower, leader=$LEADER_MEMBER"
          export ROLE_ACTIVE='follower'
        }
      fi
      read -r -t "$WAIT_SECONDS" _ && while read -r -t .1 _; do :; done
  done < <(while true; do kubectl get "$LEADER_HOLDER" -o name --no-headers --watch-only; done)
}

[ -z "$LEADER_ELECT_INIT" ] || eval "$LEADER_ELECT_INIT" || exit 1 
leader_elect "$@"
