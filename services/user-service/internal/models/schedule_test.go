package models

// Table-driven tests for the ADR-0025 pure schedule evaluator and validator.
// No I/O: all cases pass explicit service fields, timezones, and "now".

import (
	"testing"
	"time"
)

func mustCairo(t *testing.T) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation(DefaultServiceTimezone)
	if err != nil {
		t.Fatalf("test env missing tzdata for %s: %v", DefaultServiceTimezone, err)
	}
	return loc
}

func TestEvaluateServiceSchedule(t *testing.T) {
	cairo := mustCairo(t)
	utc := func(y int, mo time.Month, d, h, mi int) time.Time {
		return time.Date(y, mo, d, h, mi, 0, 0, time.UTC)
	}
	inLoc := func(y int, mo time.Month, d, h, mi int) time.Time {
		return time.Date(y, mo, d, h, mi, 0, 0, cairo)
	}

	openWeek := func(off string) []DaySchedule {
		var out []DaySchedule
		for _, d := range scheduleWeekdays {
			out = append(out, DaySchedule{Day: d, OpenTime: "09:00", CloseTime: "17:00", IsOff: d == off})
		}
		return out
	}

	cases := []struct {
		name        string
		svc         Service
		now         time.Time
		wantOpen    bool
		wantReopens *time.Time
	}{
		{
			name:     "unknown schedule is always open",
			svc:      Service{},
			now:      utc(2026, 9, 23, 3, 0),
			wantOpen: true,
		},
		{
			name:     "incomplete same_daily is open, not closed",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00"},
			now:      utc(2026, 9, 23, 3, 0),
			wantOpen: true,
		},
		{
			name:     "same_daily open during window",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00", CloseTime: "17:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 7, 0), // 10:00 Cairo
			wantOpen: true,
		},
		{
			name:     "same_daily closed morning reopens today",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00", CloseTime: "17:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 5, 0), // 08:00 Cairo
			wantOpen: false,
			wantReopens: func() *time.Time {
				tm := inLoc(2026, 9, 23, 9, 0)
				return &tm
			}(),
		},
		{
			name:     "same_daily closed evening reopens tomorrow",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00", CloseTime: "17:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 16, 0), // 19:00 Cairo
			wantOpen: false,
			wantReopens: func() *time.Time {
				tm := inLoc(2026, 9, 24, 9, 0)
				return &tm
			}(),
		},
		{
			name:     "same_daily overnight open before midnight",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "22:00", CloseTime: "04:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 20, 0), // 23:00 Cairo
			wantOpen: true,
		},
		{
			name:     "same_daily overnight open after midnight",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "22:00", CloseTime: "04:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 22, 23, 30), // 02:30 Cairo (Wed)
			wantOpen: true,
		},
		{
			name:     "same_daily overnight closed midday reopens today",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "22:00", CloseTime: "04:00", Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 9, 0), // 12:00 Cairo
			wantOpen: false,
			wantReopens: func() *time.Time {
				tm := inLoc(2026, 9, 23, 22, 0)
				return &tm
			}(),
		},
		{
			name:     "per_day off day is closed and reopens next open day",
			svc:      Service{ScheduleMode: ScheduleModePerDay, PerDaySchedule: openWeek("wed"), Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 23, 12, 0), // Wednesday 15:00 Cairo, off
			wantOpen: false,
			wantReopens: func() *time.Time {
				tm := inLoc(2026, 9, 24, 9, 0) // Thursday
				return &tm
			}(),
		},
		{
			name:     "per_day open day during window",
			svc:      Service{ScheduleMode: ScheduleModePerDay, PerDaySchedule: openWeek("wed"), Timezone: "Africa/Cairo"},
			now:      utc(2026, 9, 24, 7, 0), // Thursday 10:00 Cairo
			wantOpen: true,
		},
		{
			name:     "bad timezone falls back to Cairo instead of erroring",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00", CloseTime: "17:00", Timezone: "Bogus/Zone"},
			now:      utc(2026, 9, 23, 7, 30), // 10:30 Cairo (+3) or 09:30 (+2): open either way; 07:30 UTC would be closed
			wantOpen: true,
		},
		{
			name:     "empty timezone defaults to Cairo",
			svc:      Service{ScheduleMode: ScheduleModeSameDaily, OpenTime: "09:00", CloseTime: "17:00"},
			now:      utc(2026, 9, 23, 7, 0), // 10:00 Cairo
			wantOpen: true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			isOpen, reopens := EvaluateServiceSchedule(tc.svc, tc.now)
			if isOpen != tc.wantOpen {
				t.Fatalf("isOpen = %v, want %v", isOpen, tc.wantOpen)
			}
			if tc.wantReopens == nil {
				if reopens != nil {
					t.Fatalf("reopensAt = %v, want nil", reopens)
				}
				return
			}
			if reopens == nil {
				t.Fatalf("reopensAt = nil, want %v", tc.wantReopens)
			}
			if !reopens.Equal(*tc.wantReopens) {
				t.Fatalf("reopensAt = %v, want %v", reopens, tc.wantReopens)
			}
		})
	}
}

func TestValidateServiceSchedule(t *testing.T) {
	fullWeek := func() []DaySchedule {
		var out []DaySchedule
		for _, d := range scheduleWeekdays {
			out = append(out, DaySchedule{Day: d, OpenTime: "09:00", CloseTime: "17:00"})
		}
		return out
	}

	cases := []struct {
		name              string
		mode, open, close string
		perDay            []DaySchedule
		wantErr           bool
	}{
		{"empty schedule is valid (unknown)", "", "", "", nil, false},
		{"same_daily valid", ScheduleModeSameDaily, "09:00", "17:00", nil, false},
		{"same_daily overnight valid", ScheduleModeSameDaily, "22:00", "04:00", nil, false},
		{"per_day valid", ScheduleModePerDay, "", "", fullWeek(), false},
		{"per_day with off day and no times valid", ScheduleModePerDay, "", "", append(fullWeek()[:6], DaySchedule{Day: "sun", IsOff: true}), false},
		{"bad mode rejected", "weekly", "09:00", "17:00", nil, true},
		{"stray times without mode rejected", "", "09:00", "17:00", nil, true},
		{"same_daily missing close rejected", ScheduleModeSameDaily, "09:00", "", nil, true},
		{"bad time format rejected", ScheduleModeSameDaily, "9am", "17:00", nil, true},
		{"hour out of range rejected", ScheduleModeSameDaily, "25:00", "17:00", nil, true},
		{"equal open close rejected", ScheduleModeSameDaily, "09:00", "09:00", nil, true},
		{"per_day six entries rejected", ScheduleModePerDay, "", "", fullWeek()[:6], true},
		{"per_day missing table rejected", ScheduleModePerDay, "", "", nil, true},
		{"per_day duplicate day rejected", ScheduleModePerDay, "", "", append(fullWeek(), DaySchedule{Day: "mon", OpenTime: "09:00", CloseTime: "17:00"}), true},
		{"per_day bad day name rejected", ScheduleModePerDay, "", "", append(fullWeek()[:6], DaySchedule{Day: "funday", OpenTime: "09:00", CloseTime: "17:00"}), true},
		{"per_day bad time rejected", ScheduleModePerDay, "", "", append(fullWeek()[:6], DaySchedule{Day: "sun", OpenTime: "99:99", CloseTime: "17:00"}), true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := ValidateServiceSchedule(tc.mode, tc.open, tc.close, tc.perDay)
			if tc.wantErr && err == nil {
				t.Fatalf("expected validation error, got nil")
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("expected no error, got: %v", err)
			}
		})
	}
}
