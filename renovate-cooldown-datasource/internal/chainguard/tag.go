package chainguard

import "time"

// Tag is the minimal view of a registry tag exposed by Client.ListTags.
//
// ID is the tag's Chainguard UIDP, used to look up its history via
// Client.ListTagHistory.
type Tag struct {
	ID          string
	Name        string
	LastUpdated time.Time
	Digest      string
}

// TagHistory is one entry in a tag's update history.
type TagHistory struct {
	UpdateTimestamp time.Time
	Digest          string
}
