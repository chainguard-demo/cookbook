chainctl img ls --parent=acme.com --show-dates=true -o json | jq -r '
  [ 
    .[] | 
    {
      repo_name: .repo.name,
      tags: (
        if (.tags | type == "array" and length > 0) 
        then 
          [.tags | sort_by(.lastUpdated) | .[-1] | {tag: .name, lastUpdated: .lastUpdated}]
        else 
          [{tag: null, lastUpdated: null}]
        end
      )
    }
    | {
        repo_name, 
        tag: .tags[0].tag, 
        lastUpdated: (
          if .tags[0].lastUpdated != null 
          then 
            (.tags[0].lastUpdated | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) as $lastUpdated |
            (now - $lastUpdated) / 60 | floor
          else 
            null
          end
        )
      }
  ] 
  | map(select(.tag != null)) 
  | sort_by(.lastUpdated)
  | .[0:5]  # Select only the top 5 entries
  | .[] | {repo_name, tag: .tag, lastUpdated: (.lastUpdated | tostring + " minutes ago")}
'
