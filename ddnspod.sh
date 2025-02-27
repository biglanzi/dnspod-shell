#!/bin/sh
#

#############################################################
# AnripDdns v6.2.0
#
# Dynamic DNS using DNSPod API
#
# Author: Rehiy, https://github.com/rehiy
#                https://www.anrip.com/?s=dnspod
# Collaborators: ProfFan, https://github.com/ProfFan
#
# Usage: please refer to `ddnspod.sh`
#
#############################################################

# TokenID,Token

export arToken=""

# Get WAN IPv4

arWanIp4() {

    local hostIp

    local lanIps="^$"

    lanIps="$lanIps|(^10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    lanIps="$lanIps|(^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$)"
    lanIps="$lanIps|(^169\.254\.[0-9]{1,3}\.[0-9]{1,3}$)"
    lanIps="$lanIps|(^172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}$)"
    lanIps="$lanIps|(^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$)"
    
    local vEthernets="\s(lo|veth|docker)"

    case $(uname) in
        'Linux')
            hostIp=$(ip -o -4 addr list | grep -Ev "$vEthernets" | awk '{print $4}' | cut -d/ -f1 | grep -Ev "$lanIps")
        ;;
        'Darwin')
            hostIp=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | grep -Ev "$lanIps")
        ;;
    esac

    if [ -z "$hostIp" ]; then
        if type wget >/dev/null 2>&1; then
            hostIp=$(wget -q -O - -t 2 http://members.3322.org/dyndns/getip)    # avoid getting fq ip when using shadow socket
        else
            hostIp=$(curl -s http://members.3322.org/dyndns/getip)
        fi
    fi

    if [ -z "$hostIp" ]; then
        echo "arWanIp4 - Can't get ip address"
        return 1
    fi

    if [ -z "$(echo $hostIp | grep -E '^[0-9\.]+$')" ]; then
        echo "arWanIp4 - Invalid ip address $hostIp"
        return 1
    fi

    echo $hostIp

}

# Get WAN IPv6

arWanIp6() {

    local hostIp

    local lanIps="(^$)|(^::1$)|(^fe[8-9,A-F])"

    case $(uname) in
        'Linux')
            hostIp=$(ip -o -6 addr list | grep -Ev '\s(docker|lo)' | awk '{print $4}' | cut -d/ -f1 | grep -Ev "$lanIps" | tail -n 1)
        ;;
        'Darwin')
            hostIp=$(ifconfig | grep "inet6 " | awk '{print $2}' | grep -Ev "$lanIps" | tail -n 1)
        ;;
    esac

    if [ -z "$hostIp" ]; then
        if type wget >/dev/null 2>&1; then
            hostIp=$(wget -q -O - -t 2 https://v6.myip.la)
        else
            hostIp=$(curl -s https://v6.myip.la)
        fi
    fi

    if [ -z "$hostIp" ]; then
        echo "arWanIp6 - Can't get ip address"
        return 1
    fi

    if [ -z "$(echo $hostIp | grep -E '^[0-9a-fA-F:]+$')" ]; then
        echo "arWanIp6 - Invalid ip address"
        return 1
    fi

    echo $hostIp

}

# Dnspod Bridge
# Args: type data

arDdnsApi() {

    local agent="AnripDdns/6.1.0(wang@rehiy.com)"

    local apiurl="https://dnsapi.cn/${1:?'Info.Version'}"
    local params="login_token=$arToken&format=json&$2"

    if type wget >/dev/null 2>&1; then
        wget -q -O - -t 2 --no-check-certificate -U "$agent" --post-data "$params" "$apiurl"
    else
        curl -s -A "$agent" -d "$params" "$apiurl"
    fi

}

# Fetch Ids of Domain and Record
# Args: recordType domain subdomain

arDdnsIds() {

    local errMsg
    local recordId

    # Get Record Id
    recordId=$(arDdnsApi "Record.List" "domain=$2&sub_domain=$3&record_type=$1")
    recordId=$(echo $recordId | sed 's/.*"id":"\([0-9]*\)".*/\1/')

    if ! [ "$recordId" -gt 0 ] 2>/dev/null ;then
        errMsg=$(echo $recordId | sed 's/.*"message":"\([^\"]*\)".*/\1/')
        echo "arDdnsIds - $errMsg"
        return 1
    fi

    echo $recordId
}

# Fetch Record Ip
# Args: domain recordId

arDdnsRecordIp() {

    local errMsg
    local recordIp

    # Get Record Ip
    recordIp=$(arDdnsApi "Record.Info" "domain=$1&record_id=$2")
    recordIp=$(echo $recordIp | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')

    # Output Record Ip
    case "$recordIp" in
        [0-9a-fA-F]*)
            echo $recordIp
            return 0
        ;;
        *)
            errMsg=$(echo $recordIp | sed 's/.*"message":"\([^\"]*\)".*/\1/')
            echo "arDdnsRecordIp - $errMsg"
            return 1
        ;;
    esac

}

# Update Record Ip
# Args: domain recordId subdomain hostIp recordType

arDdnsUpdate() {

    # $1    domain name
    # $2    ddnsid
    # $3    sub domain name
    # $4    hostip
    # $5    recordtype[A|AAAA]
    local errMsg

    local recordRs
    local recordIp
    local recordCd

    if [ -z "$5" ]; then
        echo "arDdnsUpdate - Args number error"
        return 1
    fi

    # Update Ip
    if [ "$5" = "A" ]; then
        recordRs=$(arDdnsApi "Record.Ddns" "domain=$1&record_id=$2&sub_domain=$3&value=$4&record_line=%e9%bb%98%e8%ae%a4")
    else
        recordRs=$(arDdnsApi "Record.Modify" "domain=$1&record_id=$2&sub_domain=$3&record_type=$5&value=$4&record_line=%e9%bb%98%e8%ae%a4")
    fi

    recordIp=$(echo $recordRs | sed 's/.*,"value":"\([0-9a-fA-F\.\:]*\)".*/\1/')
    recordCd=$(echo $recordRs | sed 's/.*{"code":"\([0-9]*\)".*/\1/')

    # Output Result
    if [ "$recordIp" = "$4" ] && [ "$recordCd" = "1" ]; then
        echo "arDdnsUpdate - success"
        return 0
    else
        errMsg=$(echo $recordRs | sed 's/.*,"message":"\([^"]*\)".*/\1/')
        echo "arDdnsUpdate - $errMsg"
        return 1
    fi

}

# DDNS Check
# Args: Main Sub
arDdnsCheck() {

    local errCode

    local recordType
    local hostIp

    local ddnsIds
    local lastIp
    local postRs

    echo "Fetching Host Ip"
    if [ "$3" = "6" ]; then
        recordType=AAAA
        hostIp=$(arWanIp6)
    else
        recordType=A
        hostIp=$(arWanIp4)
    fi

    errCode=$?
    echo "> Host Ip: $hostIp"
    echo "> Record Type: $recordType"
    if [ $errCode -ne 0 ]; then
        return 1
    fi

    echo "Fetching Ids of $2.$1"
    ddnsIds=$(arDdnsIds "$recordType" "$1" "$2")

    errCode=$?
    echo "> Domain Ids: $ddnsIds"
    if [ $errCode -ne 0 ]; then
        return 1
    fi

    echo "Checking Record for $2.$1"
    lastIp=$(arDdnsRecordIp $1 $ddnsIds)

    errCode=$?
    echo "> Last Ip: $lastIp"
    if [ $errCode -ne 0 ]; then
        return 1
    fi

    if [ "$lastIp" = "$hostIp" ]; then
        echo "> Last Ip is the same as host Ip"
        return 0
    fi

    echo "Updating Record for $2.$1"
    postRs=$(arDdnsUpdate $1 $ddnsIds "$2" "$hostIp" "$recordType")

    errCode=$?
    echo "> $postRs"
    if [ $errCode -ne 0 ]; then
        return 1
    fi
}

echo "start checking at $(date)..."

arToken="xx.yy"
arDdnsCheck "test.org"
