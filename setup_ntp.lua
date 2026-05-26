local uci = require("luci.model.uci").cursor()

print("=== 1. Installazione Pacchetti e Gestione Conflitti ===")

-- Aggiorna i repository e installa i pacchetti necessari
print("-> Aggiornamento della lista dei pacchetti (opkg update)...")
os.execute("opkg update > /dev/null")

print("-> Installazione di ntpd e ntp-utils...")
local install_res = os.execute("opkg install ntp-utils ntpd")
if install_res ~= 0 then
    print("Errore: Impossibile installare i pacchetti. Controlla lo spazio sulla flash o la connessione internet.")
    os.exit(1)
end

-- Disabilita il client predefinito sysntpd per evitare conflitti sulla porta 123
print("-> Disabilitazione del servizio sysntpd di default...")
os.execute("/etc/init.d/sysntpd stop > /dev/null 2>&1")
os.execute("/etc/init.d/sysntpd disable > /dev/null 2>&1")


print("\n=== 2. Analisi della Rete LAN ===")

-- Legge lo stato della LAN usando il comando standard ifstatus
local handle = io.popen("ifstatus lan 2>/dev/null")
local json_raw = handle:read("*a")
handle:close()

if not json_raw or json_raw == "" then
    print("Errore: Impossibile ottenere lo stato dell'interfaccia LAN.")
    os.exit(1)
end

-- Estrazione di IP e maschera
local ipaddr = json_raw:match('"address"%s*:%s*"([^"]+)"')
local netmask = json_raw:match('"mask"%s*:%s*(%d+)')

if not ipaddr or not netmask then
    netmask = json_raw:match('"mask"%s*:%s*"([^"]+)"')
end

if not ipaddr or not netmask then
    print("Errore: Impossibile trovare IP o Maschera di rete per la LAN.")
    os.exit(1)
end

-- Calcolo della Subnet Network IP
local function get_network(ip, mask)
    local ip_octets = {}
    for octet in string.gmatch(ip, "%d+") do table.insert(ip_octets, tonumber(octet)) end
    
    local mask_octets = {}
    if tonumber(mask) and tonumber(mask) <= 32 then
        local bits = tonumber(mask)
        for i = 1, 4 do
            if bits >= 8 then mask_octets[i] = 255; bits = bits - 8
            elseif bits > 0 then mask_octets[i] = 256 - (2 ^ (8 - bits)); bits = 0
            else mask_octets[i] = 0 end
        end
    else
        for octet in string.gmatch(mask, "%d+") do table.insert(mask_octets, tonumber(octet)) end
    end
    
    local net_octets = {}
    for i = 1, 4 do
        local ip_o = ip_octets[i]
        local m_o = mask_octets[i]
        local res = 0
        local bit_val = 1
        while ip_o > 0 or m_o > 0 do
            if (ip_o % 2 == 1) and (m_o % 2 == 1) then res = res + bit_val end
            ip_o = math.floor(ip_o / 2)
            m_o = math.floor(m_o / 2)
            bit_val = bit_val * 2
        end
        net_octets[i] = res
    end
    
    return table.concat(net_octets, "."), table.concat(mask_octets, ".")
end

local network_ip, mask_str = get_network(ipaddr, netmask)
print(string.format("Rilevato IP Router: %s (Maschera: %s)", ipaddr, mask_str))
print(string.format("Subnet LAN calcolata: %s mask %s", network_ip, mask_str))


print("\n=== 3. Configurazione Parametri NTP (INRiM) ===")

-- Identifica la sezione NTP corretta in UCI
local ntp_section = nil
uci:foreach("system", "timeserver", function(s) ntp_section = s[".name"] end)
if not ntp_section then
    uci:foreach("system", "ntp", function(s) ntp_section = s[".name"] end)
end

if not ntp_section then
    print("-> Sezione NTP non trovata, creazione di una nuova sezione...")
    ntp_section = uci:add("system", "timeserver")
end

-- Pulizia vecchi dati e applicazione nuove liste
uci:delete("system", ntp_section, "server")
uci:delete("system", ntp_section, "restrict")

uci:set_list("system", ntp_section, "server", {"ntp1.inrim.it", "ntp2.inrim.it"})
print("-> Configurati server atomici: ntp1.inrim.it, ntp2.inrim.it")

local restrict_rules = {
    "127.0.0.1",
    "::1",
    string.format("%s mask %s nomodify notrap", network_ip, mask_str)
}
uci:set_list("system", ntp_section, "restrict", restrict_rules)
print("-> Configurate regole di restrizione per localhost e subnet LAN")

-- Salvataggio in UCI
uci:commit("system")
print("-> Modifiche salvate in modo permanente in UCI.")


print("\n=== 4. Attivazione del Servizio ===")

-- Abilita al boot e avvia il demone completo ntpd
os.execute("/etc/init.d/ntpd enable > /dev/null 2>&1")
print("-> Servizio ntpd abilitato al boot.")
print("-> Avvio/Riavvio del servizio ntpd...")
os.execute("/etc/init.d/ntpd restart > /dev/null 2>&1")

print("\n=== Configurazione completata con successo! ===")
print("Attendi circa 30-60 secondi e verifica lo stato con il comando: ntpq -p")
