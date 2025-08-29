#/bin/bash
# set -x
# скрипт создает домен на Interactsh Server для тестирования к нему запросов
# https://github.com/projectdiscovery/interactsh

SERVER_LIST=("oast.pro" "oast.live" "oast.site" "oast.online" "oast.fun" "oast.me")

# Генерация приватного RSA-ключа (в памяти)
PRIVATE_KEY=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:1024 2>/dev/null)
# Извлечение публичного ключа из приватного
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | openssl pkey -pubout)
# base64-кодировка ключей
ENCODED_PRIVATE_KEY=$(echo "${PRIVATE_KEY}" | base64 -w 0)
ENCODED_PUBLIC_KEY=$(echo "${PUBLIC_KEY}" | base64 -w 0)
# Генерация UUID и дополнение до 33 символов
UUID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-32)
UUID="${UUID}a"
# Создание "guid" с модификацией символов
GUID=""
for ((i = 0; i < ${#UUID}; i++)); do
    c="${UUID:$i:1}"
    if [[ "$c" =~ [0-9] ]]; then
        GUID+="$c"
    else
        offset=$((RANDOM % 21))
        ascii=$(printf "%d" "'$c")
        new_char=$(printf \\$(printf '%03o' $((ascii + offset))))
        GUID+="${new_char}"
    fi
done
# correlation_id — первые 20 символов guid
CORRELATION_ID=$(echo "${GUID}" | cut -c1-20)
# Секрет — ещё один UUID
SECRET=$(cat /proc/sys/kernel/random/uuid)


SERVER=""

export PRIVATE_KEY
export ENCODED_PUBLIC_KEY
export ENCODED_PRIVATE_KEY

register() {
    local DATA="{\"public-key\": \""${ENCODED_PUBLIC_KEY}"\", \"secret-key\": \""${SECRET}"\", \"correlation-id\": "\"${CORRELATION_ID}\""}"
    local RESPONSE=""
    until [[ "${RESPONSE}" == "registration successful" ]]; do
        SERVER="${SERVER_LIST[$RANDOM % ${#SERVER_LIST[@]}]}"
        RESPONSE=$(\curl --header "Content-Type: application/json" -sk "https://${SERVER}/register" --data "$DATA" | jq -r ".message")
	#TODO break loop если нет ответа n-раз
        return 0
    done
}

deregister() {
    local DATA="{\"secret-key\": \""${SECRET}"\", \"correlation-id\": "\"${CORRELATION_ID}\""}"
    local RESPONSE=""
    RESPONSE=$(\curl --header "Content-Type: application/json" -sk "https://${SERVER}/deregister" --data "$DATA" | jq -r ".message")
    if [[ "${RESPONSE}" == "deregistration successful" ]]; then
        return 0
    else
        return 1
    fi
}

decrypt() {
    local AES_KEY="$1"
    local ENCODED_PRIVATE_KEY="$2"
    local DATA="$3"

    PRIVATE_KEY_PEM=$(echo -n "$ENCODED_PRIVATE_KEY" | base64 -d)
    AES_KEY_PLAIN=$(openssl pkeyutl -decrypt \
        -inkey <(echo -n "$ENCODED_PRIVATE_KEY" | base64 -d) \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -pkeyopt rsa_mgf1_md:sha256 \
        -in <(echo -n "$AES_KEY" | base64 -d))
    AES_KEY_BIN=$(echo -n "$AES_KEY_PLAIN" | xxd -p | tr -d "\n")
    # Проверка на успех дешифровки AES-ключа
    if [[ $? -ne 0 ]]; then
        echo "[!] Ошибка расшифровки AES ключа (возможно, неверный ключ или формат)"
        exit 2
    fi
    # Расшифровка AES-зашифрованных данных
    IV=$(head -c 16 < <(base64 -d <<<"$DATA") | xxd -p)
    PLAINTEXT=$(base64 -d -i <<<"$DATA" 2>/dev/null | openssl enc -d -aes-256-cfb -K "$AES_KEY_BIN" -iv "$IV" 2>/dev/null)
    # Удаляем первые 16 байт
    FINALE_JSON=$(echo -n "${PLAINTEXT}" | tail -c +17)
    # нулевой бит может удалять первый символ json, если его нет - добавляем в результат
    # if [[ "${FINALE_JSON::1}" == "{" ]]; then :; else echo "{${FINALE_JSON}"; fi
    echo "${FINALE_JSON}"
}

my_ip() {
    # if has second NIC (vpn, wg) data m.b. incorrect
    \curl -s -L "ifconfig.co/json" | jq -r ".ip"
}

if register; then
    echo -e "register success!"
    echo -e "SERVER: https://${GUID}.${SERVER}"
    GET_DATA="https://${SERVER}/poll?id=${CORRELATION_ID}&secret=${SECRET}"
    echo -e "Check intearction..."

    # make_request to interact server "${GUID}.${SERVER}" for testing
    \curl -sk "${GUID}.${SERVER}" -o /dev/null
    sleep 2
    # make_request end
    
    RESPONSE=$(\curl -sk "${GET_DATA}")
    if [[ -n $RESPONSE ]]; then
        readarray -t DATA < <(jq -r ".data[]" <<<"${RESPONSE}")
        AES_KEY=$(jq -r ".aes_key" <<<"${RESPONSE}")
        echo "${RESPONSE}" >"/tmp/${GUID}.response.txt"
        echo -e "AES_KEY=\"${AES_KEY}\"" >>"/tmp/${GUID}.log.txt"
        echo -e "DATA=\"${DATA}\"" >>"/tmp/${GUID}.encrypt_data.txt"
        export AES_KEY

        remote_adress=$(
            for LINE in "${DATA[@]}"; do
                decrypt "$AES_KEY" "$ENCODED_PRIVATE_KEY" "$LINE" | tee -a "/tmp/${GUID}.decrypt_data.txt" | tr "'" '"' | jq -r ".\"remote-address\"" 2>/dev/null
            done | sort -u | head -n1
        )
    else
        echo "No Response from https://${SERVER}"
        exit 1
    fi
    echo "MY_IP: $(my_ip)"
    echo "REMOTE_ADRESS: ${remote_adress}"
    while read L; do jq -r ". | [.timestamp, .protocol, .\"remote-address\"] | join(\" \")" 2>/dev/null; done <"/tmp/${GUID}.decrypt_data.txt"

    if deregister; then
        echo "deregister success!"
	rm /tmp/"${GUID}".* #for debug comment this
    fi
fi
