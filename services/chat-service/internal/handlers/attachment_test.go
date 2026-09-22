package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/chat-service/internal/chat"
	"github.com/project/chat-service/internal/config"
	"github.com/project/chat-service/internal/store"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/storage"
	"github.com/redis/go-redis/v9"
)

func setupAttachmentTestServer(t *testing.T) (*Chat, *store.MongoDB, func()) {
	t.Helper()
	ctx := context.Background()
	dbName := fmt.Sprintf("chat_attach_test_%d", time.Now().UnixNano())
	mongoStore, err := connectTestMongoDB(ctx, dbName)
	if err != nil {
		t.Skipf("Skipping attachment test: MongoDB not available (%v)", err)
	}

	mr, err := miniredis.Run()
	if err != nil {
		t.Fatalf("failed to start miniredis: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})

	hub := chat.NewHub()
	go hub.Run()

	tempDir, err := os.MkdirTemp("", "chat_attach_storage_*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}

	jwtSecret := "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2"
	encKey := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	os.Setenv("JWT_SECRET", jwtSecret)

	stor, err := storage.NewLocalStorageWithPath(
		tempDir,
		"http://localhost:3001/api/v1",
		"/chat/attachments/view",
		jwtSecret,
		encKey,
		"test",
	)
	if err != nil {
		t.Fatalf("failed to create storage: %v", err)
	}

	cfg := &config.Config{
		JWTSecret:               jwtSecret,
		InternalServiceToken:    "internal-secret",
		AllowedOrigin:           "http://localhost:3000",
		StorageBaseDir:          tempDir,
		StorageBaseURL:          "http://localhost:3001/api/v1",
		AttachmentEncryptionKey: encKey,
		AttachmentSigningSecret: jwtSecret,
		AppEnv:                  "test",
	}

	c := NewChat(hub, mongoStore, cfg, rdb, stor)

	cleanup := func() {
		_ = mongoStore.Close(ctx)
		mr.Close()
		_ = os.RemoveAll(tempDir)
	}

	return c, mongoStore, cleanup
}

func createMultipartRequest(url, fieldName, filename string, fileContent []byte, extraFields map[string]string) (*http.Request, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile(fieldName, filename)
	if err != nil {
		return nil, err
	}
	if _, err := part.Write(fileContent); err != nil {
		return nil, err
	}

	for k, v := range extraFields {
		if err := writer.WriteField(k, v); err != nil {
			return nil, err
		}
	}

	if err := writer.Close(); err != nil {
		return nil, err
	}

	req := httptest.NewRequest(http.MethodPost, url, body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	return req, nil
}

func TestUploadAndDownloadAttachment_Success(t *testing.T) {
	c, mongoStore, cleanup := setupAttachmentTestServer(t)
	defer cleanup()

	ctx := context.Background()
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-1", "job-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	// Accept ticket by reviewer
	_, err = mongoStore.AdminAcceptTicket(ctx, ticket.ID, "reviewer-1")
	if err != nil {
		t.Fatalf("failed to accept ticket: %v", err)
	}

	custToken, _ := jwtutil.GenerateToken("cust-1", "user", "tenant-1", "cust1@example.com")
	revToken, _ := jwtutil.GenerateToken("reviewer-1", "reviewer", "tenant-1", "rev1@example.com")

	// 1. Upload valid PNG image as customer
	pngHeader := []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4")
	req, err := createMultipartRequest(fmt.Sprintf("/chat/tickets/%s/attachment", ticket.ID), "file", "photo.png", pngHeader, map[string]string{"content": "Look at this screenshot"})
	if err != nil {
		t.Fatalf("failed to create multipart request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+custToken)

	rec := httptest.NewRecorder()
	c.UploadTicketAttachment(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK, got %d: %s", rec.Code, rec.Body.String())
	}

	var msg chat.Message
	if err := json.NewDecoder(rec.Body).Decode(&msg); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if msg.AttachmentKey == "" {
		t.Fatalf("expected non-empty attachment key")
	}
	if msg.AttachmentURL == "" {
		t.Fatalf("expected non-empty attachment URL")
	}
	if msg.AttachmentType != "image/png" {
		t.Fatalf("expected attachment type image/png, got %s", msg.AttachmentType)
	}
	if msg.AttachmentName != "photo.png" {
		t.Fatalf("expected filename photo.png, got %s", msg.AttachmentName)
	}

	// 2. Download / view attachment using returned signed URL token as assigned reviewer
	parts := strings.Split(msg.AttachmentURL, "token=")
	if len(parts) < 2 {
		t.Fatalf("invalid attachment URL format: %s", msg.AttachmentURL)
	}
	token := parts[1]

	viewReq := httptest.NewRequest(http.MethodGet, "/chat/attachments/view?token="+token, nil)
	viewReq.Header.Set("Authorization", "Bearer "+revToken)
	viewRec := httptest.NewRecorder()

	c.ViewAttachment(viewRec, viewReq)

	if viewRec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for viewing attachment, got %d: %s", viewRec.Code, viewRec.Body.String())
	}

	if viewRec.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("expected Content-Type image/png, got %s", viewRec.Header().Get("Content-Type"))
	}
	if !bytes.Equal(viewRec.Body.Bytes(), pngHeader) {
		t.Fatalf("decrypted body does not match uploaded body")
	}

	// 3. Upload valid PDF as assigned reviewer
	pdfHeader := []byte("%PDF-1.4\n%...\ntrailer\n<<>>\n%%EOF")
	pdfReq, err := createMultipartRequest(fmt.Sprintf("/chat/tickets/%s/attachment", ticket.ID), "file", "document.pdf", pdfHeader, nil)
	if err != nil {
		t.Fatalf("failed to create pdf request: %v", err)
	}
	pdfReq.Header.Set("Authorization", "Bearer "+revToken)

	pdfRec := httptest.NewRecorder()
	c.UploadTicketAttachment(pdfRec, pdfReq)

	if pdfRec.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for PDF upload, got %d: %s", pdfRec.Code, pdfRec.Body.String())
	}

	var pdfMsg chat.Message
	if err := json.NewDecoder(pdfRec.Body).Decode(&pdfMsg); err != nil {
		t.Fatalf("failed to decode PDF response: %v", err)
	}
	if pdfMsg.AttachmentType != "application/pdf" {
		t.Fatalf("expected attachment type application/pdf, got %s", pdfMsg.AttachmentType)
	}
}

func TestUploadAttachment_IDORAndMIMEProtection(t *testing.T) {
	c, mongoStore, cleanup := setupAttachmentTestServer(t)
	defer cleanup()

	ctx := context.Background()
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-1", "job-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	charlieToken, _ := jwtutil.GenerateToken("cust-charlie", "user", "tenant-1", "charlie@example.com")
	custToken, _ := jwtutil.GenerateToken("cust-1", "user", "tenant-1", "cust1@example.com")

	pngHeader := []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4")

	// 1. Unauthorized user Charlie attempts upload -> 403 Forbidden
	reqCharlie, _ := createMultipartRequest(fmt.Sprintf("/chat/tickets/%s/attachment", ticket.ID), "file", "photo.png", pngHeader, nil)
	reqCharlie.Header.Set("Authorization", "Bearer "+charlieToken)
	recCharlie := httptest.NewRecorder()
	c.UploadTicketAttachment(recCharlie, reqCharlie)

	if recCharlie.Code != http.StatusForbidden {
		t.Fatalf("expected 403 Forbidden for unauthorized user, got %d: %s", recCharlie.Code, recCharlie.Body.String())
	}

	// 2. Disallowed MIME type (executable / bash script / text) -> 400 Bad Request
	scriptContent := []byte("#!/bin/bash\necho 'hello world'\n")
	reqDisallowed, _ := createMultipartRequest(fmt.Sprintf("/chat/tickets/%s/attachment", ticket.ID), "file", "script.sh", scriptContent, nil)
	reqDisallowed.Header.Set("Authorization", "Bearer "+custToken)
	recDisallowed := httptest.NewRecorder()
	c.UploadTicketAttachment(recDisallowed, reqDisallowed)

	if recDisallowed.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 Bad Request for disallowed file type, got %d: %s", recDisallowed.Code, recDisallowed.Body.String())
	}

	// 3. Non-existent ticket -> 404 Not Found
	reqNonExistent, _ := createMultipartRequest("/chat/tickets/fake-ticket-999/attachment", "file", "photo.png", pngHeader, nil)
	reqNonExistent.Header.Set("Authorization", "Bearer "+custToken)
	recNonExistent := httptest.NewRecorder()
	c.UploadTicketAttachment(recNonExistent, reqNonExistent)

	if recNonExistent.Code != http.StatusNotFound {
		t.Fatalf("expected 404 Not Found for non-existent ticket, got %d: %s", recNonExistent.Code, recNonExistent.Body.String())
	}
}

func TestViewAttachment_AccessControlAndTokenValidation(t *testing.T) {
	c, mongoStore, cleanup := setupAttachmentTestServer(t)
	defer cleanup()

	ctx := context.Background()
	ticket, err := mongoStore.CreateTicketAndAssign(ctx, "cust-1", "job-1")
	if err != nil {
		t.Fatalf("failed to create ticket: %v", err)
	}

	custToken, _ := jwtutil.GenerateToken("cust-1", "user", "tenant-1", "cust1@example.com")
	charlieToken, _ := jwtutil.GenerateToken("cust-charlie", "user", "tenant-1", "charlie@example.com")

	pngHeader := []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4")
	req, _ := createMultipartRequest(fmt.Sprintf("/chat/tickets/%s/attachment", ticket.ID), "file", "photo.png", pngHeader, nil)
	req.Header.Set("Authorization", "Bearer "+custToken)
	rec := httptest.NewRecorder()
	c.UploadTicketAttachment(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("upload failed: %d %s", rec.Code, rec.Body.String())
	}

	var msg chat.Message
	_ = json.NewDecoder(rec.Body).Decode(&msg)
	token := strings.Split(msg.AttachmentURL, "token=")[1]

	// 1. Missing token -> 401 Unauthorized
	reqMissing := httptest.NewRequest(http.MethodGet, "/chat/attachments/view", nil)
	recMissing := httptest.NewRecorder()
	c.ViewAttachment(recMissing, reqMissing)
	if recMissing.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for missing token, got %d", recMissing.Code)
	}

	// 2. Tampered / invalid token -> 403 Forbidden
	reqTampered := httptest.NewRequest(http.MethodGet, "/chat/attachments/view?token=invalid.jwt.token", nil)
	recTampered := httptest.NewRecorder()
	c.ViewAttachment(recTampered, reqTampered)
	if recTampered.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for tampered token, got %d", recTampered.Code)
	}

	// 3. Unauthorized caller Charlie with valid token -> 403 Forbidden
	reqCharlie := httptest.NewRequest(http.MethodGet, "/chat/attachments/view?token="+token, nil)
	reqCharlie.Header.Set("Authorization", "Bearer "+charlieToken)
	recCharlie := httptest.NewRecorder()
	c.ViewAttachment(recCharlie, reqCharlie)
	if recCharlie.Code != http.StatusForbidden {
		t.Fatalf("expected 403 for unauthorized caller, got %d", recCharlie.Code)
	}

	// 4. Authorized customer Alice with valid token -> 200 OK
	reqCust := httptest.NewRequest(http.MethodGet, "/chat/attachments/view?token="+token, nil)
	reqCust.Header.Set("Authorization", "Bearer "+custToken)
	recCust := httptest.NewRecorder()
	c.ViewAttachment(recCust, reqCust)
	if recCust.Code != http.StatusOK {
		t.Fatalf("expected 200 OK for authorized customer, got %d: %s", recCust.Code, recCust.Body.String())
	}
}
