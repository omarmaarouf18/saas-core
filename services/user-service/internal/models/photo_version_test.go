package models

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestPhotoVersionOf(t *testing.T) {
	if v := PhotoVersionOf(""); v != "" {
		t.Errorf("no photo: %q, want empty", v)
	}
	a, b := PhotoVersionOf("services/s1/photo_aa.jpg"), PhotoVersionOf("services/s1/photo_bb.jpg")
	if len(a) != 16 || a == b || a != PhotoVersionOf("services/s1/photo_aa.jpg") {
		t.Errorf("versions %q %q: want 16 hex chars, stable per key, different per key", a, b)
	}
}

// jsonKeys lists the JSON names of a struct's fields, flattening embedded
// structs the way encoding/json does.
func jsonKeys(t reflect.Type) []string {
	var keys []string
	for i := 0; i < t.NumField(); i++ {
		f := t.Field(i)
		if f.Anonymous && f.Type.Kind() == reflect.Struct {
			keys = append(keys, jsonKeys(f.Type)...)
			continue
		}
		name, _, _ := strings.Cut(f.Tag.Get("json"), ",")
		if name == "-" {
			continue
		}
		if name == "" {
			name = f.Name
		}
		keys = append(keys, name)
	}
	return keys
}

// Service and ServiceWithPrice have hand-written MarshalJSON methods (for
// photo_version); every struct field must still reach the JSON.
func TestServiceWithPrice_JSONHasEveryField(t *testing.T) {
	reopens := time.Now()
	full := Service{
		ID: "s1", TenantID: "t1", Name: "n", Category: "delivery", BasePrice: 1, TenantBasePrice: 2,
		TenantPricePerKM: 3, Latitude: 4, Longitude: 5, Location: NewGeoJSONPoint(4, 5),
		PhotoURL: "services/s1/photo_aa.jpg", Address: "a", WorkingHours: "w", CoverageRadiusKM: 6,
		ScheduleMode: ScheduleModeSameDaily, OpenTime: "08:00", CloseTime: "20:00",
		PerDaySchedule: []DaySchedule{{Day: "mon"}}, Timezone: DefaultServiceTimezone,
	}
	for name, v := range map[string]any{
		"Service":            full,
		"*Service":           &full,
		"ServiceWithPrice":   ServiceWithPrice{Service: full, DistanceKM: 7, FinalPrice: 8, IsOpenNow: true, ReopensAt: &reopens},
		"[]ServiceWithPrice": []ServiceWithPrice{{Service: full}},
	} {
		raw, err := json.Marshal(v)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		var obj map[string]any
		if strings.HasPrefix(string(raw), "[") {
			var arr []map[string]any
			_ = json.Unmarshal(raw, &arr)
			obj = arr[0]
		} else {
			_ = json.Unmarshal(raw, &obj)
		}
		want := jsonKeys(reflect.TypeOf(Service{}))
		if strings.Contains(name, "WithPrice") {
			want = jsonKeys(reflect.TypeOf(ServiceWithPrice{}))
		}
		for _, k := range append(want, "photo_version") {
			if _, ok := obj[k]; !ok {
				t.Errorf("%s JSON lacks %q: %s", name, k, raw)
			}
		}
		if obj["photo_version"] != PhotoVersionOf(full.PhotoURL) {
			t.Errorf("%s photo_version = %v", name, obj["photo_version"])
		}
	}

	// No photo: no photo_version (omitempty, like photo_url).
	raw, _ := json.Marshal(ServiceWithPrice{Service: Service{ID: "s2"}})
	if strings.Contains(string(raw), "photo_version") {
		t.Errorf("service without photo has photo_version: %s", raw)
	}
}
