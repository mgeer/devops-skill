package main

import (
	"database/sql"
	"log"
	"net/http"

	_ "github.com/go-sql-driver/mysql"
	"github.com/segmentio/kafka-go"
)

var writer *kafka.Writer

func main() {
	db, err := sql.Open("mysql", "user:pass@tcp(localhost:3306)/orderdb")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	writer = &kafka.Writer{
		Addr:  kafka.TCP("localhost:9092"),
		Topic: "order-events",
	}
	defer writer.Close()

	http.HandleFunc("/healthz", healthHandler)
	http.HandleFunc("/api/orders", ordersHandler)

	log.Println("Starting server on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("ok"))
}

func ordersHandler(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
}
