#!/bin/bash

set -e

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo "📊 ESTADO DEL CLUSTER - eu-devops-8-ops"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Verificar conexión al cluster
echo -e "${BLUE}🔍 Verificando conexión al cluster...${NC}"
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ No hay conexión a un cluster Kubernetes${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Conectado al cluster${NC}"
echo ""

# SECCIÓN: ACCESOS
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}🔐 ACCESOS${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Contexto actual:"
kubectl config current-context
echo ""

echo "Cluster info:"
kubectl cluster-info | head -n 1
echo ""

echo "Accesos a servicios:"
echo "  - Grafana: http://localhost:30000 (admin/admin)"
echo "  - Prometheus: http://localhost:30001"
echo "  - Loki: http://localhost:30002"
echo ""

echo "Port-forward útiles:"
echo "  kubectl port-forward -n monitoring-8 svc/grafana 3000:80"
echo "  kubectl port-forward -n monitoring-8 svc/prometheus 9090:9090"
echo "  kubectl port-forward -n la-huella-8 svc/app 8080:80"
echo ""

# SECCIÓN: HERRAMIENTAS INSTALADAS
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}🔧 HERRAMIENTAS INSTALADAS${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Verificando herramientas..."
echo ""

# Metrics Server
if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
    echo -e "${GREEN}✅ Metrics Server${NC} - Disponible"
else
    echo -e "${RED}❌ Metrics Server${NC} - No instalado"
fi

# Grafana
if kubectl get deployment grafana -n monitoring-8 &> /dev/null; then
    echo -e "${GREEN}✅ Grafana${NC} - Disponible"
else
    echo -e "${RED}❌ Grafana${NC} - No instalado"
fi

# Prometheus
if kubectl get deployment prometheus -n monitoring-8 &> /dev/null; then
    echo -e "${GREEN}✅ Prometheus${NC} - Disponible"
else
    echo -e "${RED}❌ Prometheus${NC} - No instalado"
fi

# Loki
if kubectl get deployment loki -n monitoring-8 &> /dev/null; then
    echo -e "${GREEN}✅ Loki${NC} - Disponible"
else
    echo -e "${RED}❌ Loki${NC} - No instalado"
fi

# kube-state-metrics
if kubectl get deployment kube-state-metrics -n monitoring-8 &> /dev/null; then
    echo -e "${GREEN}✅ kube-state-metrics${NC} - Disponible"
else
    echo -e "${RED}❌ kube-state-metrics${NC} - No instalado"
fi

# cert-manager
if kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
    echo -e "${GREEN}✅ cert-manager${NC} - Disponible"
else
    echo -e "${RED}❌ cert-manager${NC} - No instalado"
fi

echo ""

# SECCIÓN: ESTADO DE PODS
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}📦 ESTADO DE PODS${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Namespace: la-huella-8"
POD_COUNT=$(kubectl get pods -n la-huella-8 --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Pods: $POD_COUNT"
kubectl get pods -n la-huella-8 2>/dev/null || echo "  No hay pods"
echo ""

echo "Namespace: monitoring-8"
POD_COUNT=$(kubectl get pods -n monitoring-8 --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Pods: $POD_COUNT"
kubectl get pods -n monitoring-8 2>/dev/null || echo "  No hay pods"
echo ""

echo "Namespace: cert-manager"
POD_COUNT=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "  Pods: $POD_COUNT"
kubectl get pods -n cert-manager 2>/dev/null || echo "  No hay pods"
echo ""

# SECCIÓN: ESTADO DE BASE DE DATOS
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}🗄️  ESTADO DE BASE DE DATOS${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "PostgreSQL:"
if kubectl get deployment postgres -n la-huella-8 &> /dev/null; then
    POSTGRES_READY=$(kubectl get deployment postgres -n la-huella-8 -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    POSTGRES_DESIRED=$(kubectl get deployment postgres -n la-huella-8 -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$POSTGRES_READY" = "$POSTGRES_DESIRED" ] && [ "$POSTGRES_READY" -gt 0 ]; then
        echo -e "${GREEN}✅ PostgreSQL${NC} - Disponible ($POSTGRES_READY/$POSTGRES_DESIRED replicas)"
        
        # Verificar tablas
        USERS_COUNT=$(kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
        PRODUCTS_COUNT=$(kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -t -c "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d ' ' || echo "0")
        ORDERS_COUNT=$(kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -t -c "SELECT COUNT(*) FROM orders;" 2>/dev/null | tr -d ' ' || echo "0")
        
        if [ "$USERS_COUNT" != "0" ] || [ "$PRODUCTS_COUNT" != "0" ] || [ "$ORDERS_COUNT" != "0" ]; then
            echo "  Datos en la BD:"
            echo "    - Usuarios: $USERS_COUNT"
            echo "    - Productos: $PRODUCTS_COUNT"
            echo "    - Pedidos: $ORDERS_COUNT"
        else
            echo -e "  ${YELLOW}⚠️  Base de datos vacía - ejecuta: ./scripts/init-database.sh${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  PostgreSQL${NC} - Iniciando ($POSTGRES_READY/$POSTGRES_DESIRED replicas)"
    fi
else
    echo -e "${RED}❌ PostgreSQL${NC} - No instalado"
fi
echo ""

# SECCIÓN: COMANDOS ÚTILES
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo -e "${BLUE}🔍 COMANDOS ÚTILES${NC}"
echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "Información del cluster:"
echo "  kubectl cluster-info"
echo "  kubectl get nodes -o wide"
echo "  kubectl top nodes"
echo "  kubectl top pods -A"
echo ""

echo "Gestión de pods:"
echo "  kubectl get pods -n <namespace>"
echo "  kubectl describe pod <pod-name> -n <namespace>"
echo "  kubectl logs <pod-name> -n <namespace>"
echo "  kubectl logs -f <pod-name> -n <namespace>  # Follow logs"
echo "  kubectl exec -it <pod-name> -n <namespace> -- /bin/bash"
echo ""

echo "Port-forward:"
echo "  kubectl port-forward -n <namespace> svc/<service> <local-port>:<remote-port>"
echo "  kubectl port-forward -n <namespace> pod/<pod-name> <local-port>:<remote-port>"
echo ""

echo "Debugging:"
echo "  kubectl describe node <node-name>"
echo "  kubectl get events -n <namespace> --sort-by='.lastTimestamp'"
echo "  kubectl get pvc -n <namespace>"
echo "  kubectl get pv"
echo ""

echo "Monitorización:"
echo "  kubectl get hpa -n <namespace>  # Horizontal Pod Autoscaler"
echo "  kubectl get metrics nodes"
echo "  kubectl get metrics pods -n <namespace>"
echo ""

echo "Certificados:"
echo "  kubectl get certificate -n <namespace>"
echo "  kubectl describe certificate <cert-name> -n <namespace>"
echo "  kubectl get secret -n <namespace> | grep tls"
echo ""

echo "Limpieza:"
echo "  kubectl delete pod <pod-name> -n <namespace>"
echo "  kubectl delete all --all -n <namespace>"
echo ""

echo "Base de datos:"
echo "  # Inicializar BD con datos de prueba"
echo "  ./scripts/init-database.sh"
echo ""
echo "  # Ver usuarios"
echo "  kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -c 'SELECT * FROM users LIMIT 5;'"
echo ""
echo "  # Ver productos"
echo "  kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -c 'SELECT * FROM products LIMIT 5;'"
echo ""
echo "  # Ver pedidos"
echo "  kubectl exec -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella -c 'SELECT * FROM orders LIMIT 5;'"
echo ""
echo "  # Conectar a PostgreSQL interactivamente"
echo "  kubectl exec -it -n la-huella-8 deployment/postgres -- psql -U lahuella -d lahuella"
echo ""

echo "═══════════════════════════════════════════════════════════════════════════════════"
echo ""
