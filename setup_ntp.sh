#!/bin/sh

echo "=== Configurazione ntpd (Completo) integrata con LuCI ==="

# 1. DISABILITAZIONE COMPLETA DEL CLIENT LEGGERO (sysntpd)
# Questo libera la porta 123 per il demone completo ntpd
/etc/init.d/sysntpd stop >/dev/null 2>&1
/etc/init.d/sysntpd disable >/dev/null 2>&1
killall -9 sysntpd 2>/dev/null

# 2. Recupera IP e Netmask di br-lan tramite ifstatus
LAN_JSON=$(ifstatus lan 2>/dev/null)
if [ -z "$LAN_JSON" ]; then
    echo "Errore: Impossibile ottenere lo stato dell'interfaccia LAN."
    exit 1
fi

IPADDR=$(echo "$LAN_JSON" | grep -o '"address": "[^"]*' | cut -d'"' -f4)
NETMASK=$(echo "$LAN_JSON" | grep -o '"mask": [0-8]*' | cut -d' ' -f2)

if [ -z "$IPADDR" ] || [ -z "$NETMASK" ]; then
    NETMASK=$(echo "$LAN_JSON" | grep -o '"mask": "[^"]*' | cut -d'"' -f4)
fi

if [ -z "$IPADDR" ] || [ -z "$NETMASK" ]; then
    echo "Errore: Impossibile decodificare IP o Maschera di rete."
    exit 1
fi

if [ "$NETMASK" -eq "$NETMASK" ] 2>/dev/null; then
    case $NETMASK in
        24) MASK_STR="255.255.255.0" ;;
        16) MASK_STR="255.255.0.0" ;;
        8)  MASK_STR="255.0.0.0" ;;
        *)  MASK_STR="255.255.255.0" ;;
    esac
else
    MASK_STR=$NETMASK
fi

NET_BASE=$(echo "$IPADDR" | cut -d'.' -f1-3)
NETWORK_IP="${NET_BASE}.0"

echo "Rilevato IP Router: $IPADDR (Maschera: $MASK_STR)"
echo "Subnet LAN calcolata: $NETWORK_IP mask $MASK_STR"

# 3. CONFIGURAZIONE UCI PER LUCI & NTPD
# Trova la sezione corretta nel file system (timeserver o ntp)
NTP_SEC=$(uci show system | grep -E "=timeserver|=ntp" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)

if [ -z "$NTP_SEC" ]; then
    NTP_SEC="ntp"
fi

# Pulisce i vecchi record per evitare duplicati
while uci -q delete system.$NTP_SEC.server; do :; done
while uci -q delete system.$NTP_SEC.restrict; do :; done

# Imposta i server dell'Istituto Galileo Ferraris (INRiM)
uci add_list system.$NTP_SEC.server='ntp1.inrim.it'
uci add_list system.$NTP_SEC.server='ntp2.inrim.it'

# Imposta i parametri restrict che ntpd userà per generare il file conf
uci add_list system.$NTP_SEC.restrict='127.0.0.1'
uci add_list system.$NTP_SEC.restrict='::1'
uci add_list system.$NTP_SEC.restrict="${NETWORK_IP} mask ${MASK_STR} nomodify notrap"

# Abilita il server per la rete locale e spegne l'override del DHCP
uci set system.$NTP_SEC.enable_server='1'
uci set system.$NTP_SEC.use_dhcp='0'

# Salva le modifiche nel database di LuCI
uci commit system
echo "-> Modifiche salvate in UCI in modo permanente."

# 4. AVVIO DEL SERVIZIO NTPD COMPLETO
echo "-> Abilitazione e avvio del servizio ntpd ufficiale..."
/etc/init.d/ntpd enable >/dev/null 2>&1
/etc/init.d/ntpd restart >/dev/null 2>&1

echo "=== Configurazione completata con successo! ==="
