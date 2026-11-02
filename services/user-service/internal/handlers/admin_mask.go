package handlers

import (
	"strings"

	"github.com/project/user-service/internal/models"
)

// maskPhone masks a phone number for the admin list views: the country code
// (the first three characters, e.g. "+20") and the last three digits stay
// readable so a reviewer can still recognise the number, everything in
// between becomes a bullet.
//
// The helper lives in the user-service on purpose: the shared redaction
// package is used for secrets and tokens, and a phone number must never be
// logged or copied around in full.
func maskPhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return ""
	}

	runes := []rune(phone)
	if len(runes) <= 6 {
		// Too short to keep a country code and a tail apart — mask it all.
		return strings.Repeat("•", len(runes))
	}

	return string(runes[:3]) + strings.Repeat("•", len(runes)-6) + string(runes[len(runes)-3:])
}

// maskedRecipient returns a copy of the recipient whose phone is masked. The
// stored job must not be modified, so the copy is what leaves the handler.
func maskedRecipient(recipient *models.JobRecipient) *models.JobRecipient {
	if recipient == nil {
		return nil
	}
	if recipient.Phone == "" {
		return recipient
	}

	masked := *recipient
	masked.Phone = maskPhone(recipient.Phone)
	return &masked
}
