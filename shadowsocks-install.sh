#!/bin/bash

echo "===== Shadowsocks Install And Configure Script ====="

# Check user
if ! [ $UID -eq 0 ] ;then
    echo "This script need to be run by root!"
    echo "===== Failed ====="
    exit 1
fi

function install_shadowsocks() {
    echo "1) Install Shadowsocks"
    echo "This step takes several seconds, please wait..."

    sudo apt update >> /dev/null
    sudo apt -y install python3-pip >> /dev/null
    pip3 install https://github.com/shadowsocks/shadowsocks/archive/master.zip >> /dev/null

    echo "Done"
}

function configure_others() {
    echo "2) Configure and optimize"

    configure_systemd
    configure_bbr
    optimize_handling

    echo "Done"
}

function configure_systemd() {
    cat > /etc/systemd/system/shadowsocks-server.service << EOF
    [Unit]
    Description=Shadowsocks Server
    After=network.target

    [Service]
    ExecStartPre=/bin/sh -c 'ulimit -n 51200'
    ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks/config.json
    Restart=on-abort

    [Install]
    WantedBy=multi-user.target
EOF

    sudo systemctl enable shadowsocks-server >> /dev/null
}

function configure_bbr() {
    bbr_result=$(lsmod | grep bbr)

    if ! [[ $bbr_result =~ "tcp_bbr" ]]; then
        modprobe tcp_bbr >> /dev/null
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    fi

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -p >> /dev/null
}

function optimize_handling() {
    cat > /etc/sysctl.conf << EOF
    fs.file-max = 51200
    net.core.rmem_max = 67108864
    net.core.wmem_max = 67108864
    net.core.rmem_default = 65536
    net.core.wmem_default = 65536
    net.core.netdev_max_backlog = 4096
    net.core.somaxconn = 4096

    net.ipv4.tcp_syncookies = 1
    net.ipv4.tcp_tw_reuse = 1
    net.ipv4.tcp_tw_recycle = 0
    net.ipv4.tcp_fin_timeout = 30
    net.ipv4.tcp_keepalive_time = 1200
    net.ipv4.ip_local_port_range = 10000 65000
    net.ipv4.tcp_max_syn_backlog = 4096
    net.ipv4.tcp_max_tw_buckets = 5000
    net.ipv4.tcp_fastopen = 3
    net.ipv4.tcp_rmem = 4096 87380 67108864
    net.ipv4.tcp_wmem = 4096 65536 67108864
    net.ipv4.tcp_mtu_probing = 1

    net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system >> /dev/null
}

function configure_shadowsocks() {
    port_index=0
    port_numbers=()
    port_passwords=()

    echo "3) Configure Shadowsocks"

    sudo mkdir -p /etc/shadowsocks >> /dev/null

    echo -e -n '{\n\t"server": "::",\n\t"local_address": "127.0.0.1",\n\t"local_port": 1080,\n\t"port_password":\n\t{' > /etc/shadowsocks/config.json

    while true
    do
        read -p "Input a port number (input 0 to finish): " port

        if [ $port -eq 0 ]; then
            if [ $port_index -eq 0 ]; then
                echo "Error: please input at least 1 port number!"
            else
                let port_index--
                break
            fi
        elif [ $port -ge 1 ] && [ $port -le 65535 ]; then
            read -p "Input password of port ${port}: " password

            port_numbers+=($port)
            port_passwords+=($password)

            let port_index++
        else
            echo "Error: port number must be in 1 ~ 65535"
            continue
        fi
    done

    for ((i=0; i<=port_index; i++))
    do
        echo -e -n "\n\t\t\"${port_numbers[$i]}\": \"${port_passwords[$i]}\"" >> /etc/shadowsocks/config.json

        if [ $i -ne $port_index ]; then
            echo -n "," >> /etc/shadowsocks/config.json
        fi
    done

    echo -e '\n\t},\n\t"timeout": 300,\n\t"method": "aes-256-gcm",\n\t"fast_open": true' >> /etc/shadowsocks/config.json
    echo "}" >> /etc/shadowsocks/config.json

    echo "Done"
}

function start_shadowsocks() {
    echo "4) Start Shadowsocks"

    sudo systemctl daemon-reload >> /dev/null
    sudo systemctl restart shadowsocks-server >> /dev/null

    echo "Done"
}

function info_display() {
    echo "===== Well Done ====="

    echo -e "\nPorts and passwords:"
    echo " Port  * Password"
    echo "*************************"

    for ((i=0; i<=port_index; i++))
    do
        printf " %-6d* %s\n" ${port_numbers[$i]} ${port_passwords[$i]}
    done

    echo -e "\nEncryption Method: aes-256-gcm"

    echo -e "\n===== Just Fly ====="
}

function start_install() {
    echo ""

    install_shadowsocks
    configure_others
    configure_shadowsocks
    start_shadowsocks

    echo ""

    info_display
}

# Installation begin
start_install