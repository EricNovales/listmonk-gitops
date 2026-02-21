#!/bin/bash

set -e

echo "?? Instalación de K3s para MF8"
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Verificar si ya está instalado
if command -v k3s &> /dev/null; then
    echo -e "??  K3s ya está instalado"
    k3s --version
    echo ""
    read -p "¿Deseas reinstalarlo? (s/n): " -n 1 -r
    echo ""
    if [[ !  =~ ^[Ss]$ ]]; then
        echo "Instalación cancelada"
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
    echo -e "? curl no está instalado"
    exit 1
fi

# Verificar sistema operativo
OS=Linux
if [[ "" != "Linux" && "" != "Darwin" ]]; then
    echo -e "? Sistema operativo no soportado: "
    echo "K3s solo funciona en Linux y macOS"
    exit 1
fi

echo -e "? Sistema compatible"
echo ""

# Instalar K3s
echo "?? Descargando e instalando K3s..."
echo ""

if [[ "" == "Darwin" ]]; then
    echo -e "??  En macOS, K3s requiere Docker Desktop o Rancher Desktop"
    echo "Alternativas recomendadas para macOS:"
    echo "  - Minikube: brew install minikube && minikube start"
    echo "  - OrbStack: https://orbstack.dev/"
    echo "  - Docker Desktop: Activar Kubernetes en preferencias"
    echo ""
    read -p "¿Continuar con K3s de todos modos? (s/n): " -n 1 -r
    echo ""
    if [[ !  =~ ^[Ss]$ ]]; then
        exit 0
    fi
fi

# Instalar K3s
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644

echo ""
echo "? Esperando a que K3s esté listo..."
sleep 10

# Configurar kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Verificar instalación
if kubectl get nodes &> /dev/null; then
    echo -e "? K3s instalado correctamente"
    echo ""
    kubectl get nodes
    echo ""
    echo "?? Configuración de kubectl:"
    echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    echo ""
    echo "O copia el kubeconfig a tu ubicación por defecto:"
    echo "  mkdir -p ~/.kube"
    echo "  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config"
    echo "  sudo chown $USER ~/.kube/config"
    echo ""
else
    echo -e "? Error al instalar K3s"
    echo "Revisa los logs: sudo journalctl -u k3s"
    exit 1
fi

echo "? Instalación completada"
echo ""
echo "Ahora puedes ejecutar: ./scripts/setup-cluster.sh"
echo ""
