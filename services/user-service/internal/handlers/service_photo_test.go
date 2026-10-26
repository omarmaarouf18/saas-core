package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/project/shared/infra/jwtutil"
	"github.com/project/shared/infra/storage"
	"github.com/project/user-service/internal/config"
	"github.com/project/user-service/internal/models"
	"github.com/project/user-service/internal/store"
	"github.com/redis/go-redis/v9"
)

func createTestImage(format string) []byte {
	img := image.NewRGBA(image.Rect(0, 0, 10, 10))
	for x := 0; x < 10; x++ {
		for y := 0; y < 10; y++ {
			img.Set(x, y, color.RGBA{R: uint8(x * 25), G: uint8(y * 25), B: 100, A: 255})
		}
	}
	var buf bytes.Buffer
	if format == "png" {
		_ = png.Encode(&buf, img)
	} else {
		_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80})
	}
	return buf.Bytes()
}

func setupPhotoTestService(t *testing.T) (*UserService, *store.MongoDB, string, string, string) {
	t.Helper()
	os.Setenv("JWT_SECRET", "z8J/B2K7D3N5Q6S8V9X0A1C2E3F4G5H6J7K8M9N0P1Q2R3S4T5U6V7W8X9Y0Z1A2")
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	dbName := fmt.Sprintf("saas_user_photo_test_%d", time.Now().UnixNano())
	s, err := store.NewMongoDB(ctx, mongoURI, dbName)
	if err != nil {
		t.Skipf("Skipping: MongoDB not available (%v)", err)
	}
	t.Cleanup(func() {
		_ = s.DropDatabase(context.Background())
		_ = s.Close(context.Background())
	})

	ownerID := "photo-owner-1"
	customerID := "photo-customer-1"
	if err := s.UpsertSubscription(ctx, &models.Subscription{
		TenantID:  ownerID,
		Tier:      models.PlanPaid,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed subscription: %v", err)
	}

	auth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":         ownerID,
			"role":       "owner",
			"kyc_status": "approved",
			"is_active":  true,
			"tenant_id":  ownerID,
		})
	}))
	t.Cleanup(auth.Close)

	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })

	storageDir := t.TempDir()
	stor, err := storage.NewLocalStorageWithPath(storageDir, "/api/v1", "/users/services/photo", os.Getenv("JWT_SECRET"), "", "test")
	if err != nil {
		t.Fatalf("create test storage: %v", err)
	}

	cfg := &config.Config{
		AuthServiceURL:       auth.URL,
		InternalServiceToken: "mock-internal-token",
		AppEnv:               "test",
		StorageBaseDir:       storageDir,
		StorageBaseURL:       "/api/v1",
		JWTSecret:            os.Getenv("JWT_SECRET"),
	}
	u := NewUserService(s, cfg, rdb, stor)

	ownerToken, _ := jwtutil.GenerateToken(ownerID, "owner", ownerID, "owner@example.com")
	customerToken, _ := jwtutil.GenerateToken(customerID, "customer", "", "customer@example.com")

	return u, s, ownerID, ownerToken, customerToken
}

func TestServicePhoto_UploadAndGet_JPEGAndPNG(t *testing.T) {
	u, _, ownerID, ownerToken, customerToken := setupPhotoTestService(t)

	// 1. Upload valid JPEG via multipart/form-data
	jpegBytes := createTestImage("jpeg")
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("photo", "shop.jpg")
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	_, _ = part.Write(jpegBytes)
	_ = writer.WriteField("owner_token", ownerToken)
	_ = writer.Close()

	req := httptest.NewRequest("POST", "/users/services/photo/upload", &body)
	req.Header.Set("Content-Type", writer.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	u.UploadServicePhoto(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("upload JPEG expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var uploadResp struct {
		Message  string `json:"message"`
		PhotoURL string `json:"photo_url"`
		Key      string `json:"key"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &uploadResp); err != nil {
		t.Fatalf("unmarshal upload response: %v", err)
	}
	if uploadResp.PhotoURL == "" || !strings.HasPrefix(uploadResp.PhotoURL, "services/"+ownerID+"/") {
		t.Fatalf("expected storage key under services/%s/, got %q", ownerID, uploadResp.PhotoURL)
	}
	if isLocalPath(uploadResp.PhotoURL) {
		t.Fatalf("photo_url should not be a local path: %q", uploadResp.PhotoURL)
	}

	// 2. Authenticated read of the JPEG photo by a customer
	getReq := httptest.NewRequest("GET", "/users/services/photo?key="+uploadResp.PhotoURL, nil)
	getReq.Header.Set("Authorization", "Bearer "+customerToken)
	getRec := httptest.NewRecorder()
	u.GetServicePhoto(getRec, getReq)

	if getRec.Code != http.StatusOK {
		t.Fatalf("get photo expected 200, got %d: %s", getRec.Code, getRec.Body.String())
	}
	if ct := getRec.Header().Get("Content-Type"); ct != "image/jpeg" {
		t.Fatalf("expected Content-Type image/jpeg, got %q", ct)
	}
	if len(getRec.Body.Bytes()) == 0 {
		t.Fatalf("get photo body is empty")
	}

	// 3. Upload valid PNG via direct body
	pngBytes := createTestImage("png")
	reqPNG := httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(pngBytes))
	reqPNG.Header.Set("Content-Type", "image/png")
	reqPNG.Header.Set("Authorization", "Bearer "+ownerToken)
	recPNG := httptest.NewRecorder()
	u.UploadServicePhoto(recPNG, reqPNG)

	if recPNG.Code != http.StatusOK {
		t.Fatalf("upload PNG expected 200, got %d: %s", recPNG.Code, recPNG.Body.String())
	}
	var pngUploadResp struct {
		PhotoURL string `json:"photo_url"`
	}
	_ = json.Unmarshal(recPNG.Body.Bytes(), &pngUploadResp)

	// Read PNG with customer token
	getPNGReq := httptest.NewRequest("GET", "/users/services/photo?key="+pngUploadResp.PhotoURL, nil)
	getPNGReq.Header.Set("Authorization", "Bearer "+customerToken)
	getPNGRec := httptest.NewRecorder()
	u.GetServicePhoto(getPNGRec, getPNGReq)

	if getPNGRec.Code != http.StatusOK {
		t.Fatalf("get PNG photo expected 200, got %d: %s", getPNGRec.Code, getPNGRec.Body.String())
	}
	if ct := getPNGRec.Header().Get("Content-Type"); ct != "image/png" {
		t.Fatalf("expected Content-Type image/png, got %q", ct)
	}
}

func TestServicePhoto_Validation_MagicBytesAndSize(t *testing.T) {
	u, _, _, ownerToken, _ := setupPhotoTestService(t)

	// 1. Text file rejected by magic bytes
	textData := []byte("plain text file masquerading as photo")
	req := httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(textData))
	req.Header.Set("Content-Type", "image/jpeg")
	req.Header.Set("Authorization", "Bearer "+ownerToken)
	rec := httptest.NewRecorder()
	u.UploadServicePhoto(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for non-image magic bytes, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "only JPEG and PNG are allowed") {
		t.Fatalf("expected error message to mention JPEG and PNG, got: %s", rec.Body.String())
	}

	// 2. File exceeding 5MB rejected
	hugeData := make([]byte, 5*1024*1024+10)
	hugeReq := httptest.NewRequest("POST", "/users/services/photo", bytes.NewReader(hugeData))
	hugeReq.Header.Set("Content-Type", "image/jpeg")
	hugeReq.Header.Set("Authorization", "Bearer "+ownerToken)
	hugeRec := httptest.NewRecorder()
	u.UploadServicePhoto(hugeRec, hugeReq)

	if hugeRec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for file > 5MB, got %d: %s", hugeRec.Code, hugeRec.Body.String())
	}
	if !strings.Contains(hugeRec.Body.String(), "5MB") {
		t.Fatalf("expected error message to mention 5MB, got: %s", hugeRec.Body.String())
	}
}

func TestServicePhoto_AuthAndLocalPathIgnored(t *testing.T) {
	u, s, ownerID, _, customerToken := setupPhotoTestService(t)

	// 1. Unauthenticated read rejected
	unauthReq := httptest.NewRequest("GET", "/users/services/photo?key=services/test.jpg", nil)
	unauthRec := httptest.NewRecorder()
	u.GetServicePhoto(unauthRec, unauthReq)
	if unauthRec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for unauthenticated photo read, got %d", unauthRec.Code)
	}

	// 2. Old local paths return 404
	localPaths := []string{
		"/var/www/uploads/shop.jpg",
		"file:///etc/passwd",
		"C:\\Windows\\system32\\photo.png",
		"../relative/photo.png",
	}
	for _, lp := range localPaths {
		req := httptest.NewRequest("GET", "/users/services/photo?key="+lp, nil)
		req.Header.Set("Authorization", "Bearer "+customerToken)
		rec := httptest.NewRecorder()
		u.GetServicePhoto(rec, req)
		if rec.Code != http.StatusNotFound {
			t.Errorf("expected 404 for local path %q, got %d", lp, rec.Code)
		}
	}

	// 3. ListServices ignores old local-path values on read
	ctx := context.Background()
	svcLocal := &models.Service{
		ID:              "svc-local-path",
		TenantID:        ownerID,
		Name:            "Legacy Local Service",
		Category:        "delivery",
		TenantBasePrice: 15.0,
		PhotoURL:        "/home/user/images/shop.jpg",
	}
	if err := s.CreateService(ctx, svcLocal); err != nil {
		t.Fatalf("create svcLocal: %v", err)
	}

	svcStorage := &models.Service{
		ID:              "svc-storage-key",
		TenantID:        ownerID,
		Name:            "Storage Key Service",
		Category:        "delivery",
		TenantBasePrice: 20.0,
		PhotoURL:        "services/owner1/photo_123.jpg",
	}
	if err := s.CreateService(ctx, svcStorage); err != nil {
		t.Fatalf("create svcStorage: %v", err)
	}

	listReq := httptest.NewRequest("GET", "/users/services", nil)
	listRec := httptest.NewRecorder()
	u.ListServices(listRec, listReq)
	if listRec.Code != http.StatusOK {
		t.Fatalf("ListServices expected 200, got %d: %s", listRec.Code, listRec.Body.String())
	}

	var listResp struct {
		Services []models.Service `json:"services"`
	}
	if err := json.Unmarshal(listRec.Body.Bytes(), &listResp); err != nil {
		t.Fatalf("unmarshal list services: %v", err)
	}

	for _, svc := range listResp.Services {
		if svc.ID == "svc-local-path" {
			if svc.PhotoURL != "" {
				t.Errorf("expected local path photo_url to be cleared, got: %q", svc.PhotoURL)
			}
		}
		if svc.ID == "svc-storage-key" {
			if svc.PhotoURL != "services/owner1/photo_123.jpg" {
				t.Errorf("expected storage key photo_url to be preserved, got: %q", svc.PhotoURL)
			}
		}
	}
}
