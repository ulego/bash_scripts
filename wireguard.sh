#!/bin/bash
#------------------DEBUG SETTING-------------------------------------------------
# set -xue
# echo "+xtrace $BASH_SOURCE:$LINENO:$FUNCNAME"
# set -o pipefail

# for geolocation this script use ifconfig.co

# requrements:
# ip jq sudo dhclient awk grep cut xargs timeout ping nping wg-quick curl systemctl systemd-resolved dhclient
#-----------------USERS SETTINGS-------------------------------------------------
WIREGUARD_DIRECTORY="${HOME}/wireguard/configs"       # directory with configs
WIREGUARD_CONFIG="${WIREGUARD_DIRECTORY}/fi-hel.conf" # wg config
PING_TIMEOUT_WAITING=15                               # timeout for hard kill ping
PING_TIMEOUT=3                                        # timeout inside ping timeout "${PING_TIMEOUT_WAITING}" ping -c1 -W "${PING_TIMEOUT}"
PING_SERVER=google.com                                # server or ip for check connection

#----------------TERMINAL COLORS SETTINGS----------------------------------------
RED="\033[0;91m"
GREEN="\033[0;92m"
YELLOW="\033[0;93m"
BLUE="\033[0;94m"
PURPLE="\033[0;95m"
CYAN="\033[0;96m"
RESET="\033[0m"

#----------------PROGRAM SETTINGS-----------------------------------------------
WIREGUARD_NIC=$(sed 's/.conf//g' <<<"${WIREGUARD_CONFIG##*/}")
NIC=$(ls -l /sys/class/net/ | grep devices | grep -v virtual | awk -F "/" '{print $NF}')
WIREGUARD_ENDPOINT=$(grep Endpoint "${WIREGUARD_CONFIG}" | awk '{print $NF}' | cut -d ":" -f1)
WIREGUARD_ENDPOINT_PORT=$(grep Endpoint "${WIREGUARD_CONFIG}" | awk '{print $NF}' | cut -d ":" -f2)
WIREGUARD_LISTEN_PORT=$(grep ListenPort "${WIREGUARD_CONFIG}" | awk '{print $NF}')
declare -g REAL_COUNTRY

#---------------PROGRAMS------------------------------------------------------------
wireguard_down_all() {
    #"down all wireguards interface"
    ip -j link show type wireguard |
        jq -r ' .[] | .ifname' |
        xargs -rn 1 sudo ip link del
}

dynamic_host() {
    #"dhclient for default device"
    echo -e "${YELLOW}==>${RESET} Get dhcp.."
    if [[ -n $NIC ]]; then
        sudo dhclient "${NIC}" &>/dev/null && echo -e "${GREEN}==>${RESET} Got IP for ${NIC}: $(ip a s $NIC | grep inet | awk '{print $2}' | grep -v "[a-z]" | cut -d "/" -f1)"
        sleep 0.5
        echo -e "${BLUE}==> IFCONFIG:${RESET}\t$(ip -4 -h a s "${NIC}" | grep inet | xargs -l1)"
        echo -e "${YELLOW}==>${RESET} Check dhclient: ping ${PING_SERVER}.."
        unset PINGED
        PINGED="$(timeout "${PING_TIMEOUT_WAITING}" ping -c1 -W "${PING_TIMEOUT}" "${PING_SERVER}" | grep "bytes from\|packet loss")"
        if [[ -n $PINGED ]]; then
            if [[ $PINGED =~ "100% packet loss" ]]; then
                echo "$PINGED" | xargs -l | while read LINE; do
                    echo -e "${RED}==> PING ${PING_SERVER}:${RESET}\t$LINE"
                done
                return 1
            else
                echo "$PINGED" | xargs -l | while read LINE; do
                    echo -e "${BLUE}==> PING ${PING_SERVER}:${RESET}\t$LINE"
                done
                return 0
            fi
        else
            echo -e "${RED}==>${RESET} No ping!"
            echo -e "${RED}==>${RESET} Unsuccess connecting!\n${RED}==>${RESET} Check net device!"
            return 1
        fi
    else
        echo -e "${RED}==>${RESET} No NIC: ${NIC}"
        return 1
    fi

}

wireguard_ping() {
    #trick "ping wireguard before connection"
    echo -e "${YELLOW}==>${RESET} Ping wireguard.."
    sudo nping --udp --count 1 --data-length 16 --source-port "${WIREGUARD_LISTEN_PORT}" --dest-port "${WIREGUARD_ENDPOINT_PORT}" "${WIREGUARD_ENDPOINT}" &>/dev/null
}

wireguard_service() {
    #"down or up wireguard interface"
    if ip -br -h a s | awk '{print $1}' | grep -v "^lo\|^vmnet" | grep $WIREGUARD_NIC &>/dev/null; then
        sudo wg-quick down "${WIREGUARD_CONFIG}" &>/dev/null
        [ $? == 0 ] || wireguard_down_all 2>/dev/null && echo -e "${RED}==>${RESET} All wireguard stopped"
        echo -e "${RED}==>${RESET} Wireguard stopped"
        sleep 0.5
    else
        dynamic_host
        wireguard_ping
        sudo wg-quick up "${WIREGUARD_CONFIG}" &>/dev/null
        if (($? == 0)); then
            echo -e "${GREEN}==>${RESET} Wireguard started"
            sleep $((PING_TIMEOUT_WAITING / 2))
            echo -e "${BLUE}==> IFCONFIG:${RESET}\t$(ifconfig "${WIREGUARD_NIC}" 2>&1 | head -n1)"
            if check_connect; then
                exit 0
            fi
        else
            echo -e "${RED}==>${RESET} Wireguard can't started, check error run it:  sudo wg-quick up ${WIREGUARD_CONFIG}"
        fi
    fi

}

check_connect() {
    #"ping ${PING_SERVER}"
    echo -e "${YELLOW}==>${RESET} Check connection: ping google..."
    unset PINGED
    PINGED="$(timeout "${PING_TIMEOUT_WAITING}" ping -c 2 -W "${PING_TIMEOUT}" "${PING_SERVER}" | grep "bytes from\|packet loss")"
    if [[ -n $PINGED ]]; then
        if [[ $PINGED =~ "100% packet loss" ]]; then
            echo "$PINGED" | xargs -l | while read LINE; do
                echo -e "${RED}==> PING ${PING_SERVER}:${RESET}\t$LINE"
            done
            return 1
        else
            echo "$PINGED" | xargs -l | while read LINE; do
                echo -e "${BLUE}==> PING ${PING_SERVER}:${RESET}\t$LINE"
            done
            return 0
        fi
    else
        echo -e "${RED}==>${RESET} No ping!"
        return 1
    fi
}

check_connect_country() {
    #"get geolocation wireguard config endpoint and real ip"
    echo -e "${YELLOW}==>${RESET} Geting geolocation"
    REAL_COUNTRY=$(\curl --compressed -s -k --max-time 60 --max-filesize 500000 -m 15 ifconfig.co/json | jq -r ".country")
    if [[ -n $REAL_COUNTRY ]]; then
        echo -e "${CYAN}==>${RESET} REAL_COUNTRY: ${REAL_COUNTRY}"
    else
        echo -e "${RED}==>${RESET} GET NO REAL COUNTRY!"
    fi
    if [[ $WIREGUARD_COUNTRY == $REAL_COUNTRY ]]; then
        echo -e "${GREEN}==>${RESET} WIREGUARD UP, real country: ${REAL_COUNTRY:-"No Data"}, wireguard country: ${WIREGUARD_COUNTRY:-"No Data"}"
        return 0
    else
        echo -e "${RED}==>${RESET} Wireguard down, country: ${REAL_COUNTRY:-"No Data"}, wireguard country: ${WIREGUARD_COUNTRY:-"No Data"}"
        return 1
    fi
}

iter() {
    wireguard_service
    sleep 2
    WIREGUARD_COUNTRY=$(\curl --compressed -s -k --max-time 60 --max-filesize 500000 -m 15 http://ip-api.com/json/$WIREGUARD_ENDPOINT | jq -r ".country")
    if [[ -n $WIREGUARD_COUNTRY ]]; then
        echo -e "${CYAN}==>${RESET} WIREGUARD_COUNTRY: $WIREGUARD_COUNTRY"
        #sleep 2
        wireguard_service
        sleep 3
    else
        echo -e "${RED}==>${RESET} NO WIREGUARD COUNTRY!"
    fi
}

#----------------------------MAIN-----------------------------------------------------------------------
if [[ -n $NIC ]]; then
    :
else
    echo -e "${RED}==>${RESET} No device!"
    exit 1
fi

wireguard_down_all 2>/dev/null && echo -e "${RED}==>${RESET} All wireguard stopped"

if ! systemctl is-active systemd-resolved &>/dev/null; then
    systemctl start systemd-resolved
fi

sudo dhclient "${NIC}" 2>/dev/null
sleep 1

i=1
while :; do
    sleep "${RANDOM:0:1}" # pseudoorganic 0-9 sec sleeping
    if check_connect; then
        if check_connect_country; then
            tracepath -4 "${PING_SERVER}"
            exit 0
            echo -e "${PURPLE}==>${RESET} Done!"
        else
            echo -e "${RED}==>${RESET} Equal real and WG country Unsuccess!"
            echo -e "${YELLOW}==>${RESET} Start $(($i + 1)) iteration"
            i=$(($i + 1))
            iter
        fi
    else
        echo -e "${RED}==>${RESET} Iteration ${i} is unsuccess!"
        echo -e "${YELLOW}=$(($i + 1))>${RESET} iteration started"
        ((i++))
        iter
    fi
done
