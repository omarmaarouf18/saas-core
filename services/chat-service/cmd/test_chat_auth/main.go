package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"time"

	"github.com/gorilla/websocket"
)

type wsMessage struct {
	Type    string `json:"type,omitempty"`
	Action  string `json:"action,omitempty"`
	Channel string `json:"channel,omitempty"`
	Content string `json:"content,omitempty"`
	Error   string `json:"error,omitempty"`
}

func main() {
	// Job Details
	jobID := "c9e4a9560129aa98"
	channel := "job:" + jobID

	// Tokens
	tokenAuth := "756426a50a62b2dd"      // Authorized owner
	tokenUnauth := "21fff9461dd11e98"    // Unauthorized user

	// 1. Connect Unauthorized Client
	uUnauth := url.URL{Scheme: "ws", Host: "localhost:8080", Path: "/api/v1/chat/ws", RawQuery: "token=" + tokenUnauth}
	log.Printf("[TEST] Connecting unauthorized client to %s", uUnauth.String())
	connUnauth, _, err := websocket.DefaultDialer.Dial(uUnauth.String(), nil)
	if err != nil {
		log.Fatalf("Failed to connect unauthorized client: %v", err)
	}
	defer connUnauth.Close()

	// 2. Connect Authorized Client
	uAuth := url.URL{Scheme: "ws", Host: "localhost:8080", Path: "/api/v1/chat/ws", RawQuery: "token=" + tokenAuth}
	log.Printf("[TEST] Connecting authorized client to %s", uAuth.String())
	connAuth, _, err := websocket.DefaultDialer.Dial(uAuth.String(), nil)
	if err != nil {
		log.Fatalf("Failed to connect authorized client: %v", err)
	}
	defer connAuth.Close()

	// Start reading on authorized client in background
	authMsgs := make(chan wsMessage, 10)
	go func() {
		for {
			_, raw, err := connAuth.ReadMessage()
			if err != nil {
				return
			}
			var m wsMessage
			json.Unmarshal(raw, &m)
			authMsgs <- m
		}
	}()

	// 3. Unauthorized Client tries to SEND message without subscription/auth
	msgPayload := wsMessage{
		Action:  "message",
		Channel: channel,
		Content: "injected message from unauthorized user",
	}
	log.Printf("[TEST] Unauthorized client sending message to %s", channel)
	if err := connUnauth.WriteJSON(msgPayload); err != nil {
		log.Fatalf("Failed to send message: %v", err)
	}

	// 4. Verify Unauthorized Client receives an error frame
	_, rawErr, err := connUnauth.ReadMessage()
	if err != nil {
		log.Fatalf("Failed to read error from unauthorized client: %v", err)
	}
	var errResp wsMessage
	json.Unmarshal(rawErr, &errResp)
	fmt.Printf("[UNAUTH CLIENT RECEIVED] %s\n", string(rawErr))

	if errResp.Type != "error" || errResp.Error != "not authorized for this channel" {
		log.Fatalf("Expected authorization error frame, got: %+v", errResp)
	}
	log.Printf("[TEST] Success: Unauthorized client received correct error frame.")

	// Verify Authorized Client received NOTHING
	select {
	case m := <-authMsgs:
		log.Fatalf("Authorized client unexpectedly received a message: %+v", m)
	case <-time.After(2 * time.Second):
		log.Printf("[TEST] Success: Authorized client did not receive any unauthorized broadcast.")
	}

	// 5. Authorized Client subscribes
	subPayload := wsMessage{
		Action:  "subscribe",
		Channel: channel,
	}
	log.Printf("[TEST] Authorized client subscribing to %s", channel)
	if err := connAuth.WriteJSON(subPayload); err != nil {
		log.Fatalf("Failed to subscribe: %v", err)
	}

	// Verify subscribe confirmation
	select {
	case m := <-authMsgs:
		fmt.Printf("[AUTH CLIENT RECEIVED] %+v\n", m)
		if m.Type != "subscribed" || m.Channel != channel {
			log.Fatalf("Expected subscribed confirmation, got: %+v", m)
		}
	case <-time.After(2 * time.Second):
		log.Fatalf("Timeout waiting for subscription confirmation")
	}

	// 6. Authorized Client sends a message
	authMsgPayload := wsMessage{
		Action:  "message",
		Channel: channel,
		Content: "hello from authorized owner",
	}
	log.Printf("[TEST] Authorized client sending message to %s", channel)
	if err := connAuth.WriteJSON(authMsgPayload); err != nil {
		log.Fatalf("Failed to send authorized message: %v", err)
	}

	// Verify message broadcast is received by Authorized Client
	select {
	case m := <-authMsgs:
		fmt.Printf("[AUTH CLIENT RECEIVED BROADCAST] %+v\n", m)
		if m.Type != "message" || m.Content != "hello from authorized owner" {
			log.Fatalf("Expected message broadcast, got: %+v", m)
		}
	case <-time.After(2 * time.Second):
		log.Fatalf("Timeout waiting for message broadcast")
	}

	log.Printf("[TEST] All tests completed successfully!")
	os.Exit(0)
}
