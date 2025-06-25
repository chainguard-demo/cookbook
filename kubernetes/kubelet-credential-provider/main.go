package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"

	"chainguard.dev/sdk/sts"
	"github.com/google/go-containerregistry/pkg/name"
	v1 "k8s.io/kubelet/pkg/apis/credentialprovider/v1"
)

func main() {
	if err := run(context.Background(), os.Stdin, os.Stdout); err != nil {
		log.Fatalf("ERROR: %s", err)
	}
}

func run(ctx context.Context, r io.Reader, w io.Writer) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading input: %w", err)
	}

	var req v1.CredentialProviderRequest
	err = json.Unmarshal(data, &req)
	if err != nil {
		return fmt.Errorf("error unmarshaling auth credential request: %w", err)
	}

	resp, err := getCredentials(ctx, &req)
	if err != nil {
		return fmt.Errorf("getting credentials: %w", err)
	}

	return json.NewEncoder(w).Encode(resp)
}

func getCredentials(ctx context.Context, req *v1.CredentialProviderRequest) (*v1.CredentialProviderResponse, error) {
	ref, err := name.ParseReference(req.Image)
	if err != nil {
		return nil, fmt.Errorf("parsing image: %w", err)
	}
	host := ref.Context().RegistryStr()

	// TODO: is an error the right thing to do when we get unsupported
	// input? Or just no credentials?
	if host != "cgr.dev" {
		return nil, fmt.Errorf("host must be cgr.dev: %s", host)
	}
	if req.ServiceAccountToken == "" {
		return nil, fmt.Errorf("must provide service account token in request")
	}

	// You may want to use the same identity across all/some/most of the
	// service accounts in the cluster. In which case, it could make sense
	// to provide the identity centrally to the provider with an environment
	// variable.
	//
	// Otherwise, you could assign identities to specific service accounts
	// and provide it via an annotations on the service account.
	identity := os.Getenv("CHAINGUARD_IDENTITY")
	if annotation := req.ServiceAccountAnnotations["credentials.chainguard.dev/identity"]; annotation != "" {
		identity = annotation
	}
	if identity == "" {
		return nil, fmt.Errorf("service account must be annotated with chainguard.dev/identity")
	}

	// Exchange the service token for a token for Chainguard
	exch := sts.New("https://issuer.enforce.dev", host, sts.WithIdentity(identity))
	tok, err := exch.Exchange(ctx, req.ServiceAccountToken)
	if err != nil {
		return nil, fmt.Errorf("exchanging token: %w", err)
	}

	resp := &v1.CredentialProviderResponse{
		CacheKeyType: v1.RegistryPluginCacheKeyType,
		Auth: map[string]v1.AuthConfig{
			host: v1.AuthConfig{
				Username: "_token",
				Password: tok.AccessToken,
			},
		},
	}
	resp.TypeMeta.Kind = "CredentialProviderResponse"
	resp.TypeMeta.APIVersion = "credentialprovider.kubelet.k8s.io/v1"

	return resp, nil
}
