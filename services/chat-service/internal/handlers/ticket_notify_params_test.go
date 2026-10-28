package handlers

// PUSH-L10N item 2: ticket notifications keep their English text and add
// the parameters of notification-service's AR/EN push templates.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/project/chat-service/internal/store"
)

func TestTicketNotifications_AddTemplateParams(t *testing.T) {
	var got []map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var p map[string]any
		_ = json.NewDecoder(r.Body).Decode(&p)
		got = append(got, p)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	c := &Chat{notificationServiceURL: srv.URL}
	ticket := &store.ComplaintTicket{ID: "tkt-42", CustomerID: "cust-1"}
	ctx := context.Background()

	if ok, msg := c.dispatchTicketResolvedNotification(ctx, ticket, "refunded"); !ok {
		t.Fatalf("resolved: %s", msg)
	}
	if ok, msg := c.dispatchTicketAcceptedNotification(ctx, ticket, "Mona"); !ok {
		t.Fatalf("accepted named: %s", msg)
	}
	if ok, msg := c.dispatchTicketAcceptedNotification(ctx, ticket, ""); !ok {
		t.Fatalf("accepted anonymous: %s", msg)
	}
	if len(got) != 3 {
		t.Fatalf("got %d notifications, want 3", len(got))
	}

	want := []struct {
		typ, body string
		params    map[string]any
	}{
		{"ticket_resolved", "Your ticket (tkt-42) has been resolved: refunded",
			map[string]any{"ticket_id": "tkt-42", "note": "refunded"}},
		{"ticket_assigned", "Mona has joined your ticket (tkt-42)",
			map[string]any{"ticket_id": "tkt-42", "agent_name": "Mona"}},
		{"ticket_assigned", "A support agent has joined your ticket (tkt-42)",
			map[string]any{"ticket_id": "tkt-42", "variant": "anonymous"}},
	}
	for i, w := range want {
		n := got[i]
		if n["type"] != w.typ || n["body"] != w.body {
			t.Errorf("%d: type/body = %v / %v, want %v / %v", i, n["type"], n["body"], w.typ, w.body)
		}
		params, _ := n["params"].(map[string]any)
		if len(params) != len(w.params) {
			t.Errorf("%d: params = %v, want %v", i, params, w.params)
			continue
		}
		for k, v := range w.params {
			if params[k] != v {
				t.Errorf("%d: params[%s] = %v, want %v", i, k, params[k], v)
			}
		}
	}
}
