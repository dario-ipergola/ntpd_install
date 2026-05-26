local uci = require("luci.model.uci").cursor()

print("=== Configurazione Automatica NTP (INRiM) ===")

-- 1. Legge lo stato della LAN usando il comando standard ifstatus
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

-- 2. Calcolo della Subnet Network IP (AND bit a bit manuale)
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
        -- Simulazione bit.band senza dipendere da librerie esterne
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

-- 3. Identifica la sezione NTP corretta in UCI
local ntp_section = nil
uci:foreach("system", "timeserver", function(s) ntp_section = s[".name"] end)
if not ntp_section then
    uci:foreach("system", "ntp", function(s) ntp_section = s[".name"] end)
end

if not ntp_section then
    print("Errore: Impossibile trovare la sezione NTP in /etc/config/system.")
    os.exit(1)
end

-- Pulizia vecchi dati
uci:delete("system", ntp_section, "server")
uci:delete("system", ntp_section, "restrict")

-- 4. Inserimento Server dell'Istituto Galileo Ferraris (INRiM)
uci:set_list("system", ntp_section, "server", {"ntp1.inrim.it", "ntp2.inrim.it"})
print("-> Configurati server: ntp1.inrim.it, ntp2.inrim.it")

-- 5. Inserimento regole restrict permanenti
local restrict_rules = {
    "127.0.0.1",
    "::1",
    string.format("%s mask %s nomodify notrap", network_ip, mask_str)
}
uci:set_list("system", ntp_section, "restrict", restrict_rules)
print("-> Configurate regole di restrizione per localhost e subnet LAN")

-- 6. Salvataggio e applicazione
uci:commit("system")
print("-> Modifiche salvate in UCI.")

print("-> Riavvio del servizio ntpd...")
os.execute("/etc/init.d/ntpd restart")
print("=== Configurazione completata con successo! ===")
EOF
