Feramre sysntpd
/etc/init.d/sysntpd stop
/etc/init.d/sysntpd disable

Installare i pachetti

opkg update
opkg install ntpd ntp-utils

Eseguire lua /tmp/setup_ntp.lua

Fare test con 

ntpq -p
 
