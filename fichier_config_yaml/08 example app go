package main

// Application Go exemple qui expose des métriques Prometheus
// 
// Build:
//   go build -o metrics-app main.go
// 
// Run:
//   ./metrics-app
// 
// Test:
//   curl http://localhost:8080/metrics

import (
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// Counter : nombre total de requêtes HTTP
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Nombre total de requêtes HTTP reçues",
		},
		[]string{"method", "endpoint", "status"},
	)

	// Histogram : durée des requêtes HTTP
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Durée des requêtes HTTP en secondes",
			Buckets: []float64{0.001, 0.01, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0},
		},
		[]string{"method", "endpoint"},
	)

	// Gauge : nombre de requêtes en cours
	httpRequestsInFlight = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Nombre de requêtes HTTP en cours de traitement",
		},
	)

	// Gauge : utilisation mémoire simulée
	memoryUsageBytes = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "app_memory_usage_bytes",
			Help: "Utilisation mémoire de l'application en bytes",
		},
	)

	// Counter : nombre total d'erreurs
	errorsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "app_errors_total",
			Help: "Nombre total d'erreurs applicatives",
		},
		[]string{"type"},
	)
)

// Middleware pour instrumenter les requêtes HTTP
func instrumentHandler(endpoint string, handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Incrémenter le gauge des requêtes en cours
		httpRequestsInFlight.Inc()
		defer httpRequestsInFlight.Dec()

		// Mesurer le temps d'exécution
		start := time.Now()
		
		// Exécuter le handler
		handler(w, r)
		
		duration := time.Since(start).Seconds()

		// Enregistrer les métriques
		status := "200" // Simplification
		httpRequestsTotal.WithLabelValues(r.Method, endpoint, status).Inc()
		httpRequestDuration.WithLabelValues(r.Method, endpoint).Observe(duration)
	}
}

// Handler de test simple
func helloHandler(w http.ResponseWriter, r *http.Request) {
	// Simuler un temps de traitement variable
	time.Sleep(time.Duration(rand.Intn(100)) * time.Millisecond)
	
	fmt.Fprintf(w, "Hello from metrics-app!\n")
}

// Handler avec erreur simulée (pour tester les alertes)
func errorHandler(w http.ResponseWriter, r *http.Request) {
	// 20% de chance d'erreur
	if rand.Float32() < 0.2 {
		errorsTotal.WithLabelValues("simulated_error").Inc()
		http.Error(w, "Simulated error", http.StatusInternalServerError)
		httpRequestsTotal.WithLabelValues(r.Method, "/error", "500").Inc()
		return
	}
	
	time.Sleep(time.Duration(rand.Intn(50)) * time.Millisecond)
	fmt.Fprintf(w, "No error this time!\n")
	httpRequestsTotal.WithLabelValues(r.Method, "/error", "200").Inc()
}

// Handler avec latence élevée
func slowHandler(w http.ResponseWriter, r *http.Request) {
	// Latence aléatoire entre 0.5s et 3s
	latency := 500 + rand.Intn(2500)
	time.Sleep(time.Duration(latency) * time.Millisecond)
	
	fmt.Fprintf(w, "Slow response completed in %dms\n", latency)
}

// Goroutine pour simuler l'utilisation mémoire
func simulateMemoryUsage() {
	for {
		// Simuler une utilisation mémoire variable entre 100MB et 500MB
		usage := 100*1024*1024 + rand.Intn(400*1024*1024)
		memoryUsageBytes.Set(float64(usage))
		
		time.Sleep(10 * time.Second)
	}
}

func main() {
	// Initialiser le seed pour les nombres aléatoires
	rand.Seed(time.Now().UnixNano())

	// Démarrer la simulation d'utilisation mémoire
	go simulateMemoryUsage()

	// Endpoints de l'application
	http.HandleFunc("/", instrumentHandler("/", helloHandler))
	http.HandleFunc("/error", instrumentHandler("/error", errorHandler))
	http.HandleFunc("/slow", instrumentHandler("/slow", slowHandler))
	
	// Endpoint des métriques Prometheus
	http.Handle("/metrics", promhttp.Handler())
	
	// Health check
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "OK")
	})

	// Démarrer le serveur
	port := ":8080"
	log.Printf("Starting server on port %s", port)
	log.Printf("Metrics available at http://localhost%s/metrics", port)
	
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatal(err)
	}
}
