#!/usr/bin/env bash
#
# athena-remediation-report.sh — remediation status report for Athena submissions.
#
#   ./athena-remediation-report.sh [UPLOAD_ID|FILENAME] [--stdout]
#
# For each submission (chainctl "upload"), maps every analyzed finding:
#   submission file -> Finding ID -> CGP ID(s) -> canonical package -> fixed version
# and rolls findings up per package@version, marking each group fully_remediated
# when every finding in it has fixes for all of its CGPs.
#
# With no argument, processes every visible submission that has CGP IDs,
# regardless of upload status. Only STATUS_ANALYZED submission files with at
# least one CGP ID are included; unanalyzed/failed files only appear in the
# per-submission counts.
#
# Package identity (name, purl, version) comes from the OSV record — the
# advisory is authoritative. The submission filename contributes the Finding ID
# (the trailing UUID) and an informational submitted_as/version_mismatch.
# Binding patched_versions are cross-checked against the OSV fixed events; any
# divergence is recorded as a "discrepancy" on that CGP entry.
#
# The report is written to athena-remediation-report-YYYY-MM-DD.json in the
# current directory (a same-day rerun overwrites it); pass --stdout to print
# the report to stdout instead. Progress and warnings go to stderr.
# Requires: chainctl, jq. See CONTEXT.md for terminology.

set -euo pipefail

log() { echo "$*" >&2; }

STDOUT=false
ARG=""
for a in "$@"; do
  case "$a" in
    --stdout) STDOUT=true ;;
    -h|--help)
      log "Usage: $0 [UPLOAD_ID|FILENAME] [--stdout]"
      exit 0 ;;
    -*)
      log "Error: unknown flag: $a"
      exit 1 ;;
    *) ARG="$a" ;;
  esac
done

for dep in chainctl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    log "Error: $dep is required but not installed."
    exit 1
  fi
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FILENAME_RE='^[a-z]+-(?<mid>.+)-(?<uuid>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.md$'
FILENAME_RE_NOID='^[a-z]+-(?<mid>.+)\.md$'

# --- 1. Collect submission documents -----------------------------------------

log "Collecting submission document(s)..."

if [ -n "$ARG" ]; then
  chainctl uploads describe "$ARG" -o json | jq '[.]' > "$TMP/docs.json"
else
  # The list endpoint omits per-binding patched_versions, which the
  # discrepancy cross-check needs — so use list only to discover submissions,
  # then describe each one for its complete bindings.
  chainctl uploads list -o json --limit 200 > "$TMP/list.json"

  if [ "$(jq 'length' "$TMP/list.json" 2>/dev/null || echo 0)" = "200" ]; then
    log "Warning: uploads list hit the 200-result limit; results may be truncated."
  fi

  mkdir -p "$TMP/docs.d"
  i=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    log "  describing submission $id..."
    chainctl uploads describe "$id" -o json > "$TMP/docs.d/$i.json"
    i=$((i + 1))
  done < <(jq -r 'if type == "array" then . else (.items // .uploads
                    // error("unexpected uploads list output shape")) end
                  | .[] | select(((.cgp_ids // []) | length) > 0) | .id' "$TMP/list.json")

  if [ "$i" -gt 0 ]; then
    jq -s '.' "$TMP/docs.d/"*.json > "$TMP/docs.json"
  else
    echo '[]' > "$TMP/docs.json"
  fi
fi

if [ "$(jq 'length' "$TMP/docs.json")" = "0" ]; then
  log "Error: no submissions with CGP IDs found."
  exit 1
fi

# --- 2. Extract analyzed findings from the bindings --------------------------

jq --arg re "$FILENAME_RE" --arg re2 "$FILENAME_RE_NOID" '
  [ .[] as $d
    | ($d.bindings // [])[]
    | select(.status == "STATUS_ANALYZED" and ((.cgp_ids // []) | length) > 0)
    | .filename as $fn
    | (if ($fn | test($re)) then ($fn | capture($re))
       elif ($fn | test($re2)) then (($fn | capture($re2)) + {uuid: null})
       else null end) as $m
    | (if $m == null then {pkg: null, ver: null}
       else (($m.mid | split("-")) as $toks
             # version starts at the first digit-leading token after the package
             | ([ $toks | keys[] | select(. > 0 and ($toks[.] | test("^[0-9]"))) ] | first) as $vi
             | if $vi == null then {pkg: $m.mid, ver: null}
               else {pkg: ($toks[0:$vi] | join("-")), ver: ($toks[$vi:] | join("-"))} end)
       end) as $pv
    | { submission: $d.filename,
        submission_id: $d.id,
        submission_file: $fn,
        finding_id: ($m.uuid // null),
        submitted_package: $pv.pkg,
        submitted_version: $pv.ver,
        cgp_ids: (.cgp_ids | sort),
        patched_versions: (.patched_versions // {}) }
  ]' "$TMP/docs.json" > "$TMP/findings.json"

FINDING_COUNT=$(jq 'length' "$TMP/findings.json")
log "Found $FINDING_COUNT analyzed finding(s) with CGP IDs across $(jq 'length' "$TMP/docs.json") submission(s)."

# --- 3. Fetch the OSV record for each unique CGP -----------------------------

jq -r '[ .[].cgp_ids[] ] | unique | .[]' "$TMP/findings.json" > "$TMP/cgps.txt"
CGP_COUNT=$(grep -c . "$TMP/cgps.txt" || true)
mkdir -p "$TMP/cgp"

if [ "$CGP_COUNT" -gt 0 ]; then
  log "Fetching $CGP_COUNT OSV record(s), 4 at a time (this can take a few minutes)..."
  xargs -P 4 -I {} sh -c \
    'chainctl uploads osv get "$2" -o json > "$1/$2.json" 2>/dev/null || rm -f "$1/$2.json"' \
    _ "$TMP/cgp" {} < "$TMP/cgps.txt"

  # Drop empty or invalid record files so one bad fetch cannot poison the join.
  for f in "$TMP/cgp/"*.json; do
    [ -e "$f" ] || continue
    if [ ! -s "$f" ] || ! jq empty "$f" 2>/dev/null; then
      rm -f "$f"
    fi
  done
fi

FETCHED=$(find "$TMP/cgp" -name '*.json' | grep -c . || true)
log "Fetched $FETCHED/$CGP_COUNT OSV record(s)."
if [ "$FETCHED" -ne "$CGP_COUNT" ]; then
  while IFS= read -r cgp; do
    [ -s "$TMP/cgp/$cgp.json" ] || log "Warning: could not fetch OSV record for $cgp"
  done < "$TMP/cgps.txt"
fi

if [ "$FETCHED" -gt 0 ]; then
  cat "$TMP/cgp/"*.json | jq -n 'reduce inputs as $r ({}; .[$r.id] = $r)' > "$TMP/cgpmap.json"
else
  echo '{}' > "$TMP/cgpmap.json"
fi

# --- 4. Per-submission metadata ----------------------------------------------

jq '
  [ .[] | { id, filename, status,
      files_total: ((.bindings // []) | length),
      files_analyzed: ([ (.bindings // [])[] | select(.status == "STATUS_ANALYZED") ] | length),
      findings_included: ([ (.bindings // [])[]
                            | select(.status == "STATUS_ANALYZED" and ((.cgp_ids // []) | length) > 0)
                          ] | length) } ]
  | sort_by(.filename)' "$TMP/docs.json" > "$TMP/subs.json"

# --- 5. Join everything into the report ---------------------------------------

log "Building report..."

jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile findings "$TMP/findings.json" \
  --slurpfile cgpmap "$TMP/cgpmap.json" \
  --slurpfile subs "$TMP/subs.json" '

  # CVSS v3.1 base score (per the FIRST v3.1 specification) and the standard
  # severity label, computed from the advisory severity vector.
  def roundup31: (. * 100000 | round) as $i
    | if ($i % 10000) == 0 then $i / 100000
      else ((($i / 10000) | floor) + 1) / 10 end;

  def cvss31($vec):
    ($vec | split("/") | map(select(contains(":"))) | map(split(":") | {key: .[0], value: .[1]}) | from_entries) as $m
    # a vector missing any base metric is not scoreable (and a null lookup
    # key would be a jq error), so check presence before indexing
    | if ([$m.AV, $m.AC, $m.PR, $m.UI, $m.S, $m.C, $m.I, $m.A] | any(. == null)) then null
      else
        ({N: 0.85, A: 0.62, L: 0.55, P: 0.2}[$m.AV]) as $av
        | ({L: 0.77, H: 0.44}[$m.AC]) as $ac
        | ({N: 0.85, R: 0.62}[$m.UI]) as $ui
        | (if $m.S == "C" then {N: 0.85, L: 0.68, H: 0.5}[$m.PR]
           else {N: 0.85, L: 0.62, H: 0.27}[$m.PR] end) as $pr
        | ({H: 0.56, L: 0.22, N: 0}) as $cia
        | $cia[$m.C] as $c | $cia[$m.I] as $i | $cia[$m.A] as $a
        | if ($av == null or $ac == null or $ui == null or $pr == null
              or $c == null or $i == null or $a == null) then null
          else (1 - ((1 - $c) * (1 - $i) * (1 - $a))) as $iss
            | (if $m.S == "C" then (7.52 * ($iss - 0.029)) - (3.25 * pow($iss - 0.02; 15))
               else 6.42 * $iss end) as $impact
            | (8.22 * $av * $ac * $pr * $ui) as $expl
            | if $impact <= 0 then 0
              else (if $m.S == "C" then ([1.08 * ($impact + $expl), 10] | min)
                    else ([($impact + $expl), 10] | min) end) | roundup31 end
          end
      end;

  def criticality($s):
    if $s == null then null elif $s == 0 then "NONE" elif $s < 4 then "LOW"
    elif $s < 7 then "MEDIUM" elif $s < 9 then "HIGH" else "CRITICAL" end;

  $findings[0] as $F
  | $cgpmap[0] as $C
  # Every fixed version an advisory publishes, across all its affected blocks.
  | ($C | to_entries
        | map({key: .key,
               value: ([.value.affected[]?.ranges[]?.events[]? | select(has("fixed")) | .fixed]
                       | sort | unique)})
        | from_entries) as $ALLFIXED

  # Severity per CGP: advisories ship a CVSS v3.1 vector; score and label are
  # derived from it (null when a record carries no scoreable vector).
  | ($C | to_entries
        | map(.value as $rec | {key: .key,
               value: ((($rec.severity // []) | first) as $s
                 | (if $s == null then null else $s.score end) as $vec
                 | (if $s != null and $s.type == "CVSS_V3" and (($vec // "") | startswith("CVSS:3"))
                    then (try cvss31($vec) catch null) else null end) as $score
                 | {cvss: $vec, cvss_score: $score, criticality: criticality($score)})})
        | from_entries) as $SEV

  # One row per (finding, CGP, affected block): the canonical package@version
  # group that block assigns the finding to.
  | ([ $F[] as $f
       | $f.cgp_ids[] as $cid
       | ($C[$cid] // null) as $rec
       | select($rec != null and (($rec.affected // []) | length) > 0)
       | $rec.affected[] as $blk
       | ([$blk.ranges[]?.events[]? | select(has("fixed")) | .fixed]) as $bf
       | ($blk.versions // []) as $vers
       | (if ($f.submitted_version != null and (($vers | index($f.submitted_version)) != null))
            then $f.submitted_version
          elif ($vers | length) > 0 then $vers[0]
          else "unknown" end) as $ver
       | { key: ($blk.package.name + "@" + $ver),
           ecosystem: ($blk.package.ecosystem // null),
           name: $blk.package.name,
           purl: ($blk.package.purl // null),
           version: $ver,
           submission: $f.submission,
           submission_id: $f.submission_id,
           submission_file: $f.submission_file,
           finding_id: $f.finding_id,
           submitted_package: $f.submitted_package,
           submitted_version: $f.submitted_version,
           cgp: $cid,
           fixed: (($bf | length) > 0),
           fixed_version: ($bf | last),
           binding_reported: ($f.patched_versions[$cid] // null) }
     ]) as $ROWS

  # Findings that cannot be grouped: advisory fetch failed, or the record has
  # no affected packages. Surfaced so nothing silently disappears.
  | ([ $F[] as $f
       | $f.cgp_ids[] as $cid
       | ($C[$cid] // null) as $rec
       | select($rec == null or ((($rec.affected // []) | length) == 0))
       | { submission: $f.submission,
           submission_file: $f.submission_file,
           finding_id: $f.finding_id,
           cgp: $cid,
           reason: (if $rec == null then "advisory_not_fetched" else "no_affected_packages" end) }
     ] | sort_by([.submission_file, .cgp])) as $UNRESOLVED

  | { generated_at: $generated_at,
      submissions: $subs[0],
      packages:
        ($ROWS
         | group_by(.key)
         | map(. as $g
           | ($g
              | group_by(.submission_id + "|" + .submission_file)
              | map(. as $fg
                | ($fg | unique_by(.cgp) | sort_by(.cgp)) as $fcgps
                # A finding is remediated within this group iff every CGP
                # listed here is fixed on this package@version line — a fix
                # on a different version line does not count.
                | { finding_id: $fg[0].finding_id,
                    submission: $fg[0].submission,
                    submission_file: $fg[0].submission_file,
                    version_mismatch: ($fg[0].submitted_version != null
                                       and $fg[0].submitted_version != $fg[0].version),
                    remediated: ($fcgps | all(.fixed)),
                    cgps: ($fcgps
                           | map({ id: .cgp, fixed: .fixed, fixed_version: .fixed_version,
                                   fixed_purl: (if .fixed and .purl != null and .fixed_version != null
                                                then .purl + "@" + .fixed_version else null end) }
                                 + ($SEV[.cgp] // {cvss: null, cvss_score: null, criticality: null})
                                 + (if ((.binding_reported // []) | sort | unique) != ($ALLFIXED[.cgp] // [])
                                    then { discrepancy: { binding_reported: (.binding_reported // []) } }
                                    else {} end))) })
              | sort_by([.finding_id // "", .submission_file])) as $finds
           # Patches accumulate per version line, so the highest fix version
           # carries every fix published so far; remediation_purl points at
           # it, and fixed_versions preserves the full set for audit.
           | ([$g[] | select(.fixed) | .fixed_version] | unique
              | sort_by([scan("[0-9]+")] | map(tonumber))) as $fixed_versions
           | { key: $g[0].key,
               value: {
                 ecosystem: $g[0].ecosystem,
                 name: $g[0].name,
                 purl: $g[0].purl,
                 version: $g[0].version,
                 submitted_as: ([$g[].submitted_package] | map(select(. != null)) | unique | join(",")),
                 fixed_versions: $fixed_versions,
                 remediation_purl: (if ($fixed_versions | length) > 0 and $g[0].purl != null
                                    then $g[0].purl + "@" + ($fixed_versions | last) else null end),
                 fully_remediated: (($finds | length) > 0 and ($finds | all(.remediated))),
                 findings_total: ($finds | length),
                 findings_remediated: ([$finds[] | select(.remediated)] | length),
                 findings: $finds } })
         | sort_by(.key)
         | from_entries),
      unresolved_findings: $UNRESOLVED }
' > "$TMP/report.json"

if [ "$STDOUT" = true ]; then
  cat "$TMP/report.json"
else
  OUT="athena-remediation-report-$(date +%Y-%m-%d).json"
  cp "$TMP/report.json" "$OUT"
  log "Report written to $OUT"
fi
