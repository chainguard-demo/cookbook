package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	host := os.Getenv("HOST")
	if host == "" {
		host = "0.0.0.0"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Chainguard Go image!\n")
	})

	addr := fmt.Sprintf("%s:%s", host, port)
	log.Printf("Server running at http://%s/", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
