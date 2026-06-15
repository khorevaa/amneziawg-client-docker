#!/bin/bash

# Переключаем iptables в режим legacy, чтобы избежать ошибки nf_tables на Synology
if command -v update-alternatives &> /dev/null; then
  update-alternatives --set iptables /usr/sbin/iptables-legacy || true
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true
elif [ -f /sbin/iptables-legacy ]; then
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
    
    # Запуск интерфейса
    awg-quick up ${name}
    
    # Базовые правила форвардинга для контейнера
    iptables -A FORWARD -i ${name} -j ACCEPT
    iptables -A FORWARD -o ${name} -j ACCEPT
    iptables -A FORWARD -i ${name} -o ${name} -j ACCEPT
    
    # --- СВЯЗКА СО ВСТРОЕННЫМ OpenVPN SYNOLOGY ---
    # Разрешаем трафик из интерфейса встроенного OpenVPN (tun0) в AmneziaWG
    iptables -A FORWARD -i tun0 -o ${name} -j ACCEPT
    iptables -A FORWARD -i ${name} -o tun0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    
    # Включаем NAT (маскарадинг), чтобы пакеты из встроенного OpenVPN (подсеть 10.8.0.0/24) уходили через AmneziaWG
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${name} -j MASQUERADE
  fi
done

if [[ $COUNTER -lt 1 ]]
then
  echo "There are no config files in the /config folder"
fi
