package handlers

import (
	"testing"

	"github.com/project/user-service/internal/models"
)

func TestMaskPhone(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{name: "empty", in: "", want: ""},
		{name: "blank", in: "   ", want: ""},
		{name: "egyptian mobile", in: "+201011112222", want: "+20•••••••222"},
		{name: "egyptian mobile 13 characters", in: "+201001122334", want: "+20•••••••334"},
		{name: "local trunk form", in: "0112233444", want: "011••••444"},
		{name: "too short to keep a head and a tail", in: "12345", want: "•••••"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := maskPhone(tc.in); got != tc.want {
				t.Errorf("maskPhone(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestMaskedRecipient_KeepsTheStoredRecipientUntouched(t *testing.T) {
	recipient := &models.JobRecipient{Name: "R", Phone: "+201055554444", Notes: "call on arrival"}

	masked := maskedRecipient(recipient)
	if masked == nil {
		t.Fatal("expected a masked recipient")
	}
	if masked == recipient {
		t.Fatal("expected a copy, not the stored recipient")
	}
	if masked.Phone != "+20•••••••444" {
		t.Errorf("expected the masked phone %q, got %q", "+20•••••••444", masked.Phone)
	}
	if masked.Name != recipient.Name || masked.Notes != recipient.Notes {
		t.Errorf("expected the other recipient fields to be kept, got %+v", masked)
	}
	if recipient.Phone != "+201055554444" {
		t.Errorf("the stored recipient was modified: %q", recipient.Phone)
	}
}

func TestMaskedRecipient_HandlesTheEmptyCases(t *testing.T) {
	if got := maskedRecipient(nil); got != nil {
		t.Errorf("expected nil for a missing recipient, got %+v", got)
	}

	withoutPhone := &models.JobRecipient{Name: "R"}
	if got := maskedRecipient(withoutPhone); got == nil || got.Phone != "" {
		t.Errorf("expected the recipient without a phone to be kept, got %+v", got)
	}
}
