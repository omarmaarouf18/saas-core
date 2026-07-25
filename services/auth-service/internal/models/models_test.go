package models

import "testing"

func TestValidRole(t *testing.T) {
	if !ValidRole(RoleOwner) {
		t.Errorf("Expected RoleOwner to be valid")
	}
	if !ValidRole(RoleUser) {
		t.Errorf("Expected RoleUser to be valid")
	}
	if !ValidRole(RoleEmployee) {
		t.Errorf("Expected RoleEmployee to be valid")
	}
	if ValidRole(Role("invalid_role")) {
		t.Errorf("Expected 'invalid_role' to be invalid")
	}
}
