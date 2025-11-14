#!/bin/bash

########################################
# 1) LINK DA PÁGINA (INDEX_URL)
########################################
# Pode usar:
#   INDEX_URL="https://meu-site.com/index.html" ./setup_apache.sh
#   ./setup_apache.sh https://meu-site.com/index.html
INDEX_URL="${INDEX_URL:-${1:-}}"

if [[ -z "${INDEX_URL}" ]]; then
  echo "Uso:"
  echo "  INDEX_URL='https://link/para/pagina.html' $0"
  echo "    ou"
  echo "  $0 https://link/para/pagina.html"
  exit 1
fi

########################################
# 2) CHECA SE É ROOT
########################################

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Este script precisa ser executado como root (use sudo)." >&2
  exit 1
fi

########################################
# 3) DETECTA GERENCIADOR DE PACOTES E APACHE
########################################

APACHE_PKG=""
APACHE_SVC=""
DOCROOT="/var/www/html"

if command -v apt-get >/dev/null 2>&1; then
  # Debian/Ubuntu e derivados
  APACHE_PKG="apache2"
  APACHE_SVC="apache2"
  # OBS: os repositórios que o apt-get usa são definidos em:
  #      /etc/apt/sources.list e /etc/apt/sources.list.d/*.list
  # Se houver erro de repositório, é ali que você ajusta as entradas.
  PKG_INSTALL="apt-get update -y && apt-get install -y"

else
  echo "Não foi possível detectar apt-get/dnf/yum. Ajuste o script para sua distro." >&2
  exit 1
fi

########################################
# 4) INSTALA APACHE + WGET
########################################

echo "[*] Instalando Apache (${APACHE_PKG}) e wget..."
bash -c "${PKG_INSTALL} ${APACHE_PKG} wget"

########################################
# 5) HABILITA E INICIA O SERVIÇO HTTP
########################################

echo "[*] Habilitando e iniciando o serviço ${APACHE_SVC}..."
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now "${APACHE_SVC}"
else
  service "${APACHE_SVC}" start || true
fi

########################################
# 6) BAIXA O INDEX VIA WGET -O index.html
########################################

mkdir -p "${DOCROOT}"

echo "[*] Baixando ${INDEX_URL} para ${DOCROOT}/index.html ..."
# -q  = quiet
# -O  = define o nome do arquivo de saída (O maiúsculo!)
wget -q -O "${DOCROOT}/index.html" "${INDEX_URL}"

chmod 0644 "${DOCROOT}/index.html"

if command -v systemctl >/dev/null 2>&1; then
  systemctl reload "${APACHE_SVC}" || systemctl restart "${APACHE_SVC}"
else
  service "${APACHE_SVC}" restart || true
fi

echo
echo "======================================================="
echo " Apache instalado e página inicial configurada."
echo " Acesse: http://$(hostname -I | awk '{print $1}')/"
echo "======================================================="
echo

########################################
# 7) COLETA DADOS PARA IP ESTÁTICO
#    E APLICA EM /etc/network/interfaces
########################################

echo "Deseja ALTERAR o endereçamento de DHCP para ESTÁTICO agora? (s/n)"
read -r RESP_DHCP

if [[ "${RESP_DHCP}" =~ ^[sSyY]$ ]]; then
  echo

  # Tenta detectar a interface usada pela rota default (tipo ens33, eth0...)
  IFACE_DEFAULT="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
  echo "Interface de rede detectada (rota padrão): ${IFACE_DEFAULT:-desconhecida}"

  read -rp "Informe a interface de rede (ex: eth0, ens33) [${IFACE_DEFAULT}]: " IFACE
  IFACE="${IFACE:-${IFACE_DEFAULT}}"

  if [[ -z "${IFACE}" ]]; then
    echo "Interface não informada. Abortando configuração estática."
    exit 0
  fi

  echo
  echo "Informe os dados para o endereçamento estático (interface: ${IFACE}):"

  read -rp "Endereço IP (ex: 192.168.0.10): " IP_ADDR
  read -rp "Máscara de rede (ex: 255.255.255.0): " NETMASK
  read -rp "Gateway padrão (ex: 192.168.0.1): " GATEWAY
  read -rp "DNS (ex: 8.8.8.8 1.1.1.1): " DNS

  if [[ -z "${IP_ADDR}" || -z "${NETMASK}" || -z "${GATEWAY}" ]]; then
    echo "IP, máscara e gateway são obrigatórios. Não aplicando configuração estática."
    exit 0
  fi

  echo
  echo "======================================================="
  echo " APLICANDO CONFIGURAÇÃO ESTÁTICA EM /etc/network/interfaces"
  echo "  Interface......: ${IFACE}"
  echo "  IP.............: ${IP_ADDR}"
  echo "  Máscara........: ${NETMASK}"
  echo "  Gateway........: ${GATEWAY}"
  echo "  DNS............: ${DNS}"
  echo "======================================================="

  INTERFACES_FILE="/etc/network/interfaces"
  if [[ -f "${INTERFACES_FILE}" ]]; then
    BACKUP="/etc/network/interfaces.$(date +%Y%m%d%H%M%S).bak"
    echo "[*] Fazendo backup de ${INTERFACES_FILE} em ${BACKUP}"
    cp -f "${INTERFACES_FILE}" "${BACKUP}"
  fi

  cat > "${INTERFACES_FILE}" <<EOF
# /etc/network/interfaces gerado pelo script setup_apache.sh
# Backup anterior (se existia) foi salvo em ${BACKUP:-"(sem backup)"}

# Interface de loopback
auto lo
iface lo inet loopback

# Interface de rede principal (estática)
auto ${IFACE}
iface ${IFACE} inet static
    address ${IP_ADDR}
    netmask ${NETMASK}
    gateway ${GATEWAY}
    dns-nameservers ${DNS}
EOF

  echo "[*] Novo conteúdo de ${INTERFACES_FILE}:"
  echo "-------------------------------------------------------"
  cat "${INTERFACES_FILE}"
  echo
  echo "-------------------------------------------------------"
  echo "[*] Reiniciando serviço de rede (isso pode derrubar a conexão atual)..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart networking || true
  else
    service networking restart || true
  fi

  echo
  echo "Configuração estática aplicada. Verifique com:"
  echo "  ip addr show ${IFACE}"
  echo "  ip route"
else
  echo "Ok, mantendo a configuração atual de DHCP. Nada foi alterado em /etc/network/interfaces."
fi

echo
echo "Script concluído."




