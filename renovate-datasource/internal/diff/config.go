package diff

import (
	"sort"
	"strings"

	v1 "github.com/google/go-containerregistry/pkg/v1"
)

// diffConfig compares the two ImageConfigs across the fields the diff
// response surfaces. Labels are emitted per-key; everything else is a
// scalar or a slice rendered as a comma-joined value.
func diffConfig(from, to *v1.ConfigFile) []ConfigDelta {
	fc, tc := from.Config, to.Config
	var out []ConfigDelta
	out = append(out, scalarDelta("User", fc.User, tc.User)...)
	out = append(out, sliceDelta("Env", fc.Env, tc.Env)...)
	out = append(out, sliceDelta("Entrypoint", fc.Entrypoint, tc.Entrypoint)...)
	out = append(out, sliceDelta("Cmd", fc.Cmd, tc.Cmd)...)
	out = append(out, scalarDelta("WorkingDir", fc.WorkingDir, tc.WorkingDir)...)
	out = append(out, scalarDelta("StopSignal", fc.StopSignal, tc.StopSignal)...)
	out = append(out, labelsDelta(fc.Labels, tc.Labels)...)
	return out
}

func scalarDelta(field, from, to string) []ConfigDelta {
	if from == to {
		return nil
	}
	switch {
	case from == "":
		return []ConfigDelta{{Field: field, To: to, Type: "added"}}
	case to == "":
		return []ConfigDelta{{Field: field, From: from, Type: "removed"}}
	default:
		return []ConfigDelta{{Field: field, From: from, To: to, Type: "changed"}}
	}
}

func sliceDelta(field string, from, to []string) []ConfigDelta {
	fromS := strings.Join(from, ",")
	toS := strings.Join(to, ",")
	return scalarDelta(field, fromS, toS)
}

func labelsDelta(from, to map[string]string) []ConfigDelta {
	keys := map[string]struct{}{}
	for k := range from {
		keys[k] = struct{}{}
	}
	for k := range to {
		keys[k] = struct{}{}
	}
	sorted := make([]string, 0, len(keys))
	for k := range keys {
		sorted = append(sorted, k)
	}
	sort.Strings(sorted)

	var out []ConfigDelta
	for _, k := range sorted {
		fv, fok := from[k]
		tv, tok := to[k]
		switch {
		case fok && tok && fv != tv:
			out = append(out, ConfigDelta{Field: "Labels[" + k + "]", From: fv, To: tv, Type: "changed"})
		case !fok && tok:
			out = append(out, ConfigDelta{Field: "Labels[" + k + "]", To: tv, Type: "added"})
		case fok && !tok:
			out = append(out, ConfigDelta{Field: "Labels[" + k + "]", From: fv, Type: "removed"})
		}
	}
	return out
}
