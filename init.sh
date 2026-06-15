#!/bin/bash

# 1. Принудительное переключение iptables в режим legacy внутри Alpine Linux
echo "Форсирование iptables-legacy для Alpine..."
if [ -f /sbin/iptables-legacy ]; then
  rm -f /sbin/iptables /sbin/ip6tables
  ln -sf /sbin/iptables-legacy /sbin/iptables
  ln -sf /sbin/ip6tables-legacy /sbin/ip6tables
fi

# clear existing configurations
find /etc/amnezia/amneziawg -mindepth 1 -delete

COUNTER=0
for s in $(find /config -name "*.conf")
do
  if test -f ${s}
  then
    COUNTER=$(( COUNTER + 1 ))
    basename=$(basename ${s})
    name=${basename%.conf}
    echo awg interface "${name}" will be created from config file "${basename}"
    cp ${s} /etc/amnezia/amneziawg/${name}.conf
    chmod 600 /etc/amnezia/amneziawg/${name}.conf
    
    # 2. Запуск интерфейса через awg-quick
    awg-quick up ${name}
    
    # Внутренние правила маршрутизации контейнера
    iptables -A FORWARD -i ${name} -j ACCEPT
    iptables -A FORWARD -o ${name} -j ACCEPT
    iptables -A FORWARD -i ${name} -o ${name} -j ACCEPT
    
    # --- СВЯЗКА СО ВСТРОЕННЫМ OpenVPN SYNOLOGY ---
    # Перенаправляем входящий трафик со встроенного сервера (tun0) в интерфейс AmneziaWG (${name})
    iptables -A FORWARD -i tun0 -o ${name} -j ACCEPT
    iptables -A FORWARD -i ${name} -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Маскарадинг (NAT) для подсети встроенного OpenVPN (по умолчанию 10.8.0.0/24)
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${name} -j MASQUERADE
  fi
done

if [[ $COUNTER -lt 1 ]]
then
  echo "There are no config files in the /config folder"
fi
