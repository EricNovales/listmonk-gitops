#!/bin/bash

set -e

echo "?? Instalaci�n de K3s cluster"
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar si ya est� instalado
if command -v k3s &> /dev/null; then
    echo -e "??  K3s ya est� instalado"
    k3s --version
    echo ""
    read -p "�Deseas reinstalarlo? (s/n): " -n 1 -r
    echo ""
    if [[ !  =~ ^[Ss]$ ]]; then
        echo "Instalaci�n cancelada"
        exit 0
    fi
    echo ""
    echo "???  Desinstalando K3s existente..."
    /usr/local/bin/k3s-uninstall.sh || true
    sleep 2
fi

# Verificar requisitos
echo "?? Verificando requisitos..."

if ! command -v curl &> /dev/null; then
    echo -e "? curl no est� instalado"
    exit 1
fi

# Verificar sistema operativo
OS=Linux
if [[ "" != "Linux" && "" != "Darwin" ]]; then
    echo -e "? Sistema operativo no soportado: "
    echo "K3s solo funciona en Linux"
    exit 1
fi

echo -e "? Sistema compatible"
echo ""

# Instalar K3s
echo "?? Descargando e instalando K3s..."
echo ""

# Instalar K3s

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh - -s - --write-kubeconfig-mode 644

echo ""
echo "? Esperando a que K3s est� listo..."
sleep 10

# Configurar kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verificar instalaci�n
if kubectl get nodes &> /dev/null; then
    echo -e "? K3s instalado correctamente"
    echo ""
    kubectl get nodes
    echo ""
    echo "?? Configuraci�n de kubectl:"
    echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    echo ""
    echo "O copia el kubeconfig a tu ubicaci�n por defecto:"
    echo "  mkdir -p ~/.kube"
    echo "  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
    echo "  sudo chown $USER ~/.kube/config"
    echo ""
else
    echo -e "? Error al instalar K3s"
    echo "Revisa los logs: sudo journalctl -u k3s"
    exit 1
fi

echo "? Instalaci�n completada"
echo ""
echo "Ahora puedes ejecutar: ./scripts/k3s_install_config.sh"
echo ""
