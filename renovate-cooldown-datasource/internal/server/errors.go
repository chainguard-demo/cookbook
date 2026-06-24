package server

import (
	"encoding/json"
	"net/http"
)

// apiError is the JSON shape returned for every non-OK response from the
// /v1/* and /repo/* endpoints. /healthz remains plain text "ok".
type apiError struct {
	Error string `json:"error"`
}

// writeAPIError serialises a structured JSON error onto w. Used in place of
// http.Error everywhere except /healthz so clients (and the diff page JS)
// can surface the message verbatim.
func writeAPIError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(apiError{Error: msg})
}
