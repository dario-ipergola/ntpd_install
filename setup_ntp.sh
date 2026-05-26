#!/bin/sh

echo "=== Configurazione ntpd (Completo) integrata con LuCI ==="

# 1. DISABILITAZIONE COMPLETA DEL CLIENT LEGGERO (sysntpd)
/etc/init.d/sysntpd stop >/dev/null 2>&1
/etc/init.d/sysntpd disable >/dev/null 2>&1
killall -9 sysntpd 2>/dev/null

# 2. RECUPERA IP E MASCHERA DI br-lan USANDO ifstatus + jsonfilter
if ! command -v jsonfilter >/dev/null 2>&1; then
    echo "Errore: jsonfilter non disponibile. Abort."
    exit 1
fi

LAN_JSON=$(ifstatus lan 2>/dev/null)
if [ -z "$LAN_JSON" ]; then
    echo "Errore: Impossibile ottenere lo stato dell'interfaccia LAN."
    exit 1
fi

IPADDR=$(echo "$LAN_JSON" | jsonfilter -e '@["ipv4-address"][0].address')
CIDR=$(echo "$LAN_JSON" | jsonfilter -e '@["ipv4-address"][0].mask')

if [ -z "$IPADDR" ] || [ -z "$CIDR" ]; then
    echo "Errore: Impossibile estrarre IP o maschera CIDR dal JSON."
    exit 1
fi

# Calcola l'indirizzo di rete e la netmask in dotted decimal usando ipcalc.sh
# (presente su OpenWrt di default)
if ! command -v ipcalc.sh >/dev/null 2>&1; then
    echo "Errore: ipcalc.sh non trovato."
    exit 1
fi

eval "$(ipcalc.sh "$IPADDR" "$CIDR" | grep -E '^NETWORK=|^NETMASK=')"
if [ -z "$NETWORK" ] || [ -z "$NETMASK" ]; then
    echo "Errore: calcolo rete/maschera fallito."
    exit 1
fi

echo "Rilevato IP Router: $IPADDR (Maschera: $NETMASK, CIDR: $CIDR)"
echo "Subnet LAN calcolata: $NETWORK mask $NETMASK"

# 3. CONFIGURAZIONE UCI PER LUCI & NTPD
NTP_SEC=$(uci show system | grep -E "=timeserver|=ntp" | head -n1 | cut -d'.' -f2 | cut -d'=' -f1)

if [ -z "$NTP_SEC" ]; then
    NTP_SEC="ntp"
fi

# Pulisce i vecchi record
while uci -q delete system.$NTP_SEC.server; do :; done
while uci -q delete system.$NTP_SEC.restrict; do :; done

# Server NTP italiani (INRiM)
uci add_list system.$NTP_SEC.server='ntp1.inrim.it'
uci add_list system.$NTP_SEC.server='ntp2.inrim.it'

# Restrict per ntpd
uci add_list system.$NTP_SEC.restrict='127.0.0.1'
uci add_list system.$NTP_SEC.restrict='::1'
uci add_list system.$NTP_SEC.restrict="${NETWORK} mask ${NETMASK} nomodify notrap"

# Abilita server NTP per LAN, disabilita override DHCP
uci set system.$NTP_SEC.enable_server='1'
uci set system.$NTP_SEC.use_dhcp='0'

uci commit system
echo "-> Modifiche salvate in UCI."

# 4. AVVIO DEL SERVIZIO NTPD COMPLETO
echo "-> Abilitazione e avvio di ntpd..."
/etc/init.d/ntpd enable >/dev/null 2>&1
/etc/init.d/ntpd restart >/dev/null 2>&1

echo "=== Configurazione completata con successo! ==="
