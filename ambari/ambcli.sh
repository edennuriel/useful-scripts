#!/bin/bash
#set -x
#Script to setup kerberos in one click! :)
#Author - Kuldeep Kulkarni (http://crazyadmins.com)
#############

LOC=`pwd`
PROP=ambari.props
source $LOC/$PROP
CURLOPTS='-s'
sleep="sleep "
#############

declare -A states 
for l in $(awk -F, '! /^#/ { if ($1~"s" ) { printf "states[%s]=%s\n",$1,$2;}}' states.csv); do eval "$l" ; echo "evaluating $l" ; done

ambcli() {
  METHOD=${1:-GET}
  API="${2:-clusters/$CLUSTER_NAME}"
  PAYLOAD="${3:+ -d '"$3"'}"
  AMBCLI='curl -k -H  "X-Requested-By:ambari" "${CURLOPTS}" -u $AMBARI_ADMIN_USER:$AMBARI_ADMIN_PASSWORD '
  echo "${AMBCLI} -X ${METHOD} "${AMBARI_BASE_URL}/api/v1/$API" "${PAYLOAD}"" >> rest.log
  eval "${AMBCLI} -X ${METHOD} "${AMBARI_BASE_URL}/api/v1/$API" "${PAYLOAD}""
}

ambpost() {
  CURLOPTS='-s'
  ambcli POST "$1" "$2"
}

ambput() {
  CURLOPTS='-s'
  ambcli PUT "$1" "$2"
}

ambdel() {
  CURLOPTS='-s'
  ambcli DELETE "$1" 
}

ambget() {
  CURLOPTS='-s'
  ambcli GET "$1" 
}

ambgets() {
  CURLOPTS="-s"
  ambcli GET "$1"
}

ambservices() {
  amb srv ls|jq -r '.items[].ServiceInfo.service_name' > /tmp/amb.svc
}
 
progress() {
    ambget clusters/$CLUSTER_NAME/requests/$request_id | grep progress_percent | awk '{print $3}' | cut -d . -f 1
}

waitFor() {
    export request_id=${1}
    progressPercent=$(progress)
    echo " Progress: $progressPercent"
    while [[ $(progress | grep -v 100) ]]; do
      progressPercent=$(progress)
      tput cuu1
      echo "$(tput setaf 2)[ Progress: $progressPercent % ]$(tput sgr 0)"
      sleep 2
    done
}

ambsrvact() {
     op=${1}
     service="${2/all/}"
     state=${states[$op]}
     [[ ! -z $service ]] && [[ -f /tmp/amb.svc ]] && service=$(grep -i $service /tmp/amb.svc)
     echo $(ambput clusters/$CLUSTER_NAME/services${service:+/$service} '{"RequestInfo": {"context" :"'"Putting $service Services in $state state"'"}, "ServiceInfo": {"state" : "'"$state"'"}}' | awk '/id/{print $3}'|cut -d',' -f1)
}

amb() {
  ambsubcmd=$1;
  shift
  case $ambsubcmd in

  srv )
    case "$1" in
    ls )
      ambget clusters/$CLUSTER_NAME/services #jq -r '.items[].ServiceInfo.service_name'
    ;; 
    start|stop )
     request_id=$(ambsrvact "$1" "$2")
     echo waitFor "$request_id"
     waitFor $request_id

    esac
  ;;

  cmp )
    echo component ops
  ;;

  cfg )
   case "$1" in
   ls )
     fltr=${2:-site}
     ambget clusters/enseclab/configurations | jq --arg cfg "$fltr" -r '.items[]|select(.type |contains($cfg))|"\(.type), \(.version), \(.tag)"' | awk -F, '{printf "%-40s%3d%-25s\n",$1,$2,$3}'
     ;;
   esac
  ;;
  * )
    echo Usage
 ;;
 esac

}

ambsrv() {
  OP=${1:-status}
  shift
  case "$OP" in
  add )
    ambpost clusters/$CLUSTER_NAME/services/$1 
  ;;
  * )
    echo Usage: ambsrv add/remove/start/stop/status service_name 
  ;;
  esac
}

ts()
{
	echo "`date +%Y-%m-%d,%H:%M:%S`"
}

