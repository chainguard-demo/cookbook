package diff

import (
	"github.com/spdx/tools-golang/spdx/v2/common"
	spdx "github.com/spdx/tools-golang/spdx/v2/v2_3"
)

// sbom is the trimmed view of an SPDX document the diff code consumes. We
// don't pass *spdx.Document around because its field names are awkward to
// read repeatedly (PackageSPDXIdentifier, RefA.ElementRefID) and we only
// touch four fields per package and three per relationship.
type sbom struct {
	Packages      []sbomPackage
	Relationships []sbomRelationship
}

type sbomPackage struct {
	ID      string
	Name    string
	Version string
	Purl    string
}

type sbomRelationship struct {
	From string
	Type string
	To   string
}

// sbomFromSPDX translates an SPDX 2.3 document into the internal view. nil
// entries in the slices (which spdx/tools-golang occasionally produces during
// unmarshaling) are skipped.
func sbomFromSPDX(doc *spdx.Document) *sbom {
	s := &sbom{
		Packages:      make([]sbomPackage, 0, len(doc.Packages)),
		Relationships: make([]sbomRelationship, 0, len(doc.Relationships)),
	}
	for _, p := range doc.Packages {
		if p == nil {
			continue
		}
		s.Packages = append(s.Packages, sbomPackage{
			ID:      string(p.PackageSPDXIdentifier),
			Name:    p.PackageName,
			Version: p.PackageVersion,
			Purl:    purlFromRefs(p.PackageExternalReferences),
		})
	}
	for _, r := range doc.Relationships {
		if r == nil {
			continue
		}
		s.Relationships = append(s.Relationships, sbomRelationship{
			From: string(r.RefA.ElementRefID),
			Type: r.Relationship,
			To:   string(r.RefB.ElementRefID),
		})
	}
	return s
}

func purlFromRefs(refs []*spdx.PackageExternalReference) string {
	for _, r := range refs {
		if r != nil && r.RefType == common.TypePackageManagerPURL {
			return r.Locator
		}
	}
	return ""
}
