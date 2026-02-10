#!/bin/bash
# Script d'exercices Grafana-Prometheus - VERSION COMPLÈTE
# Formation Kubernetes - Chapitre 6

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==============================================================================
# EXERCICE 1 : Installation
# ==============================================================================

exercice1_install() {
    echo_info "=== EXERCICE 1 : Installation de kube-prometheus-stack ==="
    
    echo_info "Ajout du repository Helm..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    
    echo_info "Mise à jour du cache Helm..."
    helm repo update
    
    echo_info "Création du namespace monitoring..."
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    echo_info "Installation de kube-prometheus-stack..."
    helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --set prometheus.prometheusSpec.retention=15d \
      --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi \
      --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=nfs-client \
      --wait \
      --timeout 10m
    
    echo_info "Installation terminée !"
}

exercice1_verify() {
    echo_info "=== Vérification de l'installation ==="
    
    echo_info "Pods dans le namespace monitoring :"
    kubectl get pods -n monitoring
    
    echo ""
    echo_info "Services dans le namespace monitoring :"
    kubectl get svc -n monitoring
    
    echo ""
    echo_info "Attente que tous les pods soient Running..."
    kubectl wait --for=condition=Ready pods --all -n monitoring --timeout=300s
    
    echo_info "Installation vérifiée avec succès !"
}

exercice1_access_grafana() {
    echo_info "=== Accès à Grafana ==="
    
    GRAFANA_PASSWORD=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
      -o jsonpath="{.data.admin-password}" | base64 --decode 2>/dev/null)
    
    if [ -z "$GRAFANA_PASSWORD" ]; then
        echo_warn "Impossible de récupérer le mot de passe, utilisation du défaut"
        GRAFANA_PASSWORD="prom-operator"
    fi
    
    echo_info "Mot de passe admin Grafana : ${GRAFANA_PASSWORD}"
    echo_info "Login : admin"
    echo ""
    echo_info "Démarrage du port-forward sur le port 3000..."
    echo_info "Accédez à Grafana : http://localhost:3000"
    echo_warn "Appuyez sur Ctrl+C pour arrêter"
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
}

exercice1_access_prometheus() {
    echo_info "=== Accès à Prometheus ==="
    echo_info "Démarrage du port-forward sur le port 9090..."
    echo_info "Accédez à Prometheus : http://localhost:9090"
    echo_warn "Appuyez sur Ctrl+C pour arrêter"
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
}

exercice1_access_alertmanager() {
    echo_info "=== Accès à Alertmanager ==="
    echo_info "Démarrage du port-forward sur le port 9093..."
    echo_info "Accédez à Alertmanager : http://localhost:9093"
    echo_warn "Appuyez sur Ctrl+C pour arrêter"
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
}

# ==============================================================================
# EXERCICE 2 : Application avec métriques
# ==============================================================================

exercice2_deploy_app() {
    echo_info "=== EXERCICE 2 : Déploiement de l'application de démonstration ==="
    
    if [ -f "01-namespaces.yaml" ]; then
        echo_info "Création du namespace production..."
        kubectl apply -f 01-namespaces.yaml
        
        echo_info "Déploiement de l'application demo-metrics..."
        kubectl apply -f 02-demo-app-deployment.yaml
    else
        echo_warn "Fichiers manifests non trouvés, création inline..."
        
        cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    name: production
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-metrics-app
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-metrics
  template:
    metadata:
      labels:
        app: demo-metrics
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: metrics-app
        image: quay.io/brancz/prometheus-example-app:v0.3.0
        ports:
        - name: metrics
          containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: demo-metrics-service
  namespace: production
  labels:
    app: demo-metrics
spec:
  type: ClusterIP
  selector:
    app: demo-metrics
  ports:
  - name: metrics
    port: 8080
    targetPort: metrics
EOF
    fi
    
    echo_info "Attente que les pods soient Running..."
    kubectl wait --for=condition=Ready pods -l app=demo-metrics -n production --timeout=120s
    
    echo_info "Pods déployés :"
    kubectl get pods -n production
    
    echo_info "Application déployée avec succès !"
}

exercice2_test_metrics() {
    echo_info "=== Test de l'endpoint /metrics ==="
    
    POD=$(kubectl get pods -n production -l app=demo-metrics -o jsonpath='{.items[0].metadata.name}')
    
    echo_info "Port-forward vers le pod ${POD}..."
    kubectl port-forward -n production ${POD} 8080:8080 &
    PF_PID=$!
    
    sleep 3
    
    echo_info "Test de l'endpoint /metrics :"
    curl -s http://localhost:8080/metrics | head -20
    
    kill $PF_PID 2>/dev/null
    
    echo_info "Métriques accessibles !"
}

exercice2_create_servicemonitor() {
    echo_info "=== Création du ServiceMonitor ==="
    
    if [ -f "03-servicemonitor.yaml" ]; then
        echo_info "Application du ServiceMonitor..."
        kubectl apply -f 03-servicemonitor.yaml
    else
        echo_warn "Fichier manifest non trouvé, création inline..."
        
        cat <<EOF | kubectl apply -f -
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-metrics-monitor
  namespace: monitoring
  labels:
    app: demo-metrics
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: demo-metrics
  namespaceSelector:
    matchNames:
    - production
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
EOF
    fi
    
    echo_info "ServiceMonitor créé :"
    kubectl get servicemonitor -n monitoring demo-metrics-monitor
    
    echo_info "ServiceMonitor créé avec succès !"
    echo_warn "Attendez 30 secondes que Prometheus découvre la target..."
    sleep 30
}

exercice2_verify_scraping() {
    echo_info "=== Vérification du scraping dans Prometheus ==="
    
    echo_info "Ouverture de Prometheus..."
    echo_info "1. Allez sur http://localhost:9090"
    echo_info "2. Cliquez sur Status > Targets"
    echo_info "3. Cherchez 'production/demo-metrics'"
    echo_info "4. Vérifiez que le statut est UP"
    echo ""
    echo_info "Requête PromQL de test :"
    echo "  rate(http_requests_total[5m])"
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
}

# ==============================================================================
# EXERCICE 3 : Alertes
# ==============================================================================

exercice3_create_rules() {
    echo_info "=== EXERCICE 3 : Création des PrometheusRule ==="
    
    if [ -f "04-prometheus-rules.yaml" ]; then
        echo_info "Application des règles Prometheus..."
        kubectl apply -f 04-prometheus-rules.yaml
    else
        echo_warn "Fichier non trouvé, création d'une règle simple..."
        
        cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: demo-app-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: demo-app-alerting-rules
    interval: 30s
    rules:
    - alert: HighHTTPErrorRate
      expr: |
        (
          sum(rate(http_requests_total{namespace="production",status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{namespace="production"}[5m]))
        ) > 0.05
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Taux d'erreurs HTTP élevé"
        description: "Taux d'erreur: {{ \$value | humanizePercentage }}"
EOF
    fi
    
    echo_info "PrometheusRule créées :"
    kubectl get prometheusrule -n monitoring
    
    echo_info "Règles créées avec succès !"
    echo_warn "Attendez 30 secondes que Prometheus recharge la configuration..."
    sleep 30
}

exercice3_verify_rules() {
    echo_info "=== Vérification des règles dans Prometheus ==="
    
    echo_info "Ouverture de Prometheus..."
    echo_info "1. Allez sur http://localhost:9090"
    echo_info "2. Cliquez sur Status > Rules"
    echo_info "3. Vérifiez que le groupe 'demo-app-alerting-rules' est présent"
    echo ""
    echo_info "Pour voir les alertes :"
    echo_info "1. Cliquez sur Alerts"
    echo_info "2. Cherchez 'HighHTTPErrorRate'"
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
}

exercice3_simulate_errors() {
    echo_info "=== Simulation d'erreurs pour déclencher une alerte ==="
    
    POD=$(kubectl get pods -n production -l app=demo-metrics -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$POD" ]; then
        echo_error "L'application demo-metrics n'est pas déployée !"
        echo_info "Exécutez d'abord l'exercice 2 (option 6)"
        return 1
    fi
    
    echo_info "Pod trouvé : ${POD}"
    echo_info "Port-forward vers ${POD}..."
    kubectl port-forward -n production ${POD} 8080:8080 &
    PF_PID=$!
    
    sleep 3
    
    echo ""
    echo_warn "GÉNÉRATION DE TRAFIC AVEC ERREURS"
    echo_warn "Durée : 6 minutes pour garantir le déclenchement"
    echo ""
    
    echo_info "Phase 1/2 : Génération de trafic (5 minutes)..."
    
    local count=0
    local start_time=$(date +%s)
    local duration=300  # 5 minutes
    
    while [ $(($(date +%s) - start_time)) -lt $duration ]; do
        curl -s http://localhost:8080/ > /dev/null 2>&1
        curl -s http://localhost:8080/metrics > /dev/null 2>&1
        
        count=$((count + 2))
        
        if [ $((count % 100)) -eq 0 ]; then
            elapsed=$(($(date +%s) - start_time))
            remaining=$((duration - elapsed))
            echo "  → ${count} requêtes | Temps écoulé: ${elapsed}s | Restant: ${remaining}s"
        fi
        
        sleep 0.1
    done
    
    echo ""
    echo_info "Phase 2/2 : ${count} requêtes envoyées !"
    
    kill $PF_PID 2>/dev/null
    
    echo ""
    echo_info "✅ Simulation terminée !"
    echo ""
    echo_warn "┌─────────────────────────────────────────────────────────────┐"
    echo_warn "│  QUE VÉRIFIER MAINTENANT ?                                  │"
    echo_warn "└─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "📊 PROMETHEUS - Vérifier le taux d'erreurs :"
    echo ""
    echo "   1. Port-forward :"
    echo "      kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
    echo ""
    echo "   2. Ouvrir : http://localhost:9090/graph"
    echo ""
    echo "   3. Requête pour voir le taux d'erreur :"
    echo "      (sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))) * 100"
    echo ""
    echo "   4. Aller dans Alerts : http://localhost:9090/alerts"
    echo "      Chercher 'HighHTTPErrorRate'"
    echo ""
    echo "🚨 ÉTATS DE L'ALERTE :"
    echo "   • Inactive (vert)  : Taux < 5%"
    echo "   • Pending (orange) : Taux > 5%, attend 5 min"
    echo "   • Firing (rouge)   : Alerte déclenchée !"
    echo ""
    echo "⏱️  TIMELINE :"
    echo "   Maintenant : Taux d'erreur visible"
    echo "   +5 min : Si >5% → Alerte passe en PENDING"
    echo "   +10 min : Si toujours >5% → FIRING"
    echo ""
}

check_alert_status() {
    echo_info "=== Vérification de l'état des alertes ==="
    
    kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
    PF_PID=$!
    sleep 3
    
    echo ""
    echo_info "Interrogation de l'API Prometheus..."
    
    # Vérifier le taux d'erreur actuel
    ERROR_RATE=$(curl -s 'http://localhost:9090/api/v1/query?query=(sum(rate(http_requests_total{status=~"5.."}[5m]))/sum(rate(http_requests_total[5m])))*100' 2>/dev/null | \
                 jq -r '.data.result[0].value[1]' 2>/dev/null)
    
    if [ ! -z "$ERROR_RATE" ] && [ "$ERROR_RATE" != "null" ]; then
        echo_info "📊 Taux d'erreur actuel : ${ERROR_RATE}%"
        
        if (( $(echo "$ERROR_RATE > 5" | bc -l 2>/dev/null || echo 0) )); then
            echo_warn "   ⚠️  Supérieur au seuil de 5% !"
        else
            echo_info "   ✓ Inférieur au seuil de 5%"
        fi
    else
        echo_info "📊 Taux d'erreur : Pas encore de données ou pas d'erreurs"
    fi
    
    kill $PF_PID 2>/dev/null
    
    echo ""
    echo_info "Pour voir les alertes dans Prometheus :"
    echo "http://localhost:9090/alerts"
}

# ==============================================================================
# NETTOYAGE
# ==============================================================================

cleanup() {
    echo_warn "=== Nettoyage des ressources ==="
    
    read -p "Êtes-vous sûr de vouloir tout supprimer ? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo_info "Nettoyage annulé"
        return 0
    fi
    
    echo_info "Suppression de l'application demo-metrics..."
    kubectl delete namespace production --ignore-not-found
    kubectl delete servicemonitor -n monitoring demo-metrics-monitor --ignore-not-found
    kubectl delete prometheusrule -n monitoring demo-app-rules --ignore-not-found
    
    echo_info "Désinstallation de kube-prometheus-stack..."
    helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
    
    echo_info "Nettoyage des PVC..."
    kubectl get pvc -n monitoring -o name 2>/dev/null | \
      xargs -I {} kubectl patch {} -n monitoring -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
    kubectl delete pvc --all -n monitoring --ignore-not-found
    
    echo_info "Suppression du namespace monitoring..."
    kubectl patch namespace monitoring -p '{"spec":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    kubectl delete namespace monitoring --ignore-not-found
    
    echo_info "Nettoyage terminé !"
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

show_menu() {
    echo ""
    echo "======================================================================"
    echo "  Formation Kubernetes - Exercices Grafana & Prometheus"
    echo "======================================================================"
    echo ""
    echo "EXERCICE 1 : Installation"
    echo "  1) Installer kube-prometheus-stack"
    echo "  2) Vérifier l'installation"
    echo "  3) Accéder à Grafana"
    echo "  4) Accéder à Prometheus"
    echo "  5) Accéder à Alertmanager"
    echo ""
    echo "EXERCICE 2 : Application avec métriques"
    echo "  6) Déployer l'application demo"
    echo "  7) Tester l'endpoint /metrics"
    echo "  8) Créer le ServiceMonitor"
    echo "  9) Vérifier le scraping"
    echo ""
    echo "EXERCICE 3 : Alerting"
    echo "  10) Créer les PrometheusRule"
    echo "  11) Vérifier les règles"
    echo "  12) Simuler des erreurs (6 minutes)"
    echo "  13) Vérifier l'état des alertes"
    echo ""
    echo "AUTRES"
    echo "  98) Tout exécuter automatiquement"
    echo "  99) Nettoyage complet"
    echo "  0) Quitter"
    echo ""
    echo -n "Votre choix : "
}

# Boucle principale
while true; do
    show_menu
    read choice
    
    case $choice in
        1) exercice1_install ;;
        2) exercice1_verify ;;
        3) exercice1_access_grafana ;;
        4) exercice1_access_prometheus ;;
        5) exercice1_access_alertmanager ;;
        6) exercice2_deploy_app ;;
        7) exercice2_test_metrics ;;
        8) exercice2_create_servicemonitor ;;
        9) exercice2_verify_scraping ;;
        10) exercice3_create_rules ;;
        11) exercice3_verify_rules ;;
        12) exercice3_simulate_errors ;;
        13) check_alert_status ;;
        98)
            exercice1_install
            exercice1_verify
            exercice2_deploy_app
            exercice2_create_servicemonitor
            exercice3_create_rules
            echo_info "Installation automatique terminée !"
            ;;
        99) cleanup ;;
        0) echo_info "Au revoir !"; exit 0 ;;
        *) echo_error "Choix invalide" ;;
    esac
    
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
done
