package models

// Structured weekly schedule evaluation (ADR-0025).
//
// All functions here are pure (no I/O, no logging): evaluation takes the
// service's stored schedule fields, a timezone, and a "now" instant, and
// returns whether the service is open plus the next opening time when
// computable. Unknown or incomplete schedules always evaluate as open with
// no reopen time, preserving pre-feature behavior for legacy services.

import (
	"fmt"
	"strings"
	"time"
)

// parseHHMM validates a 24-hour "HH:mm" string and returns minutes since
// midnight. Anything else (empty, wrong shape, out-of-range values) errors.
func parseHHMM(s string) (int, error) {
	if len(s) != 5 || s[2] != ':' {
		return 0, fmt.Errorf("time %q must be HH:mm", s)
	}
	for _, c := range []byte{s[0], s[1], s[3], s[4]} {
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("time %q must be HH:mm", s)
		}
	}
	h := int(s[0]-'0')*10 + int(s[1]-'0')
	m := int(s[3]-'0')*10 + int(s[4]-'0')
	if h > 23 || m > 59 {
		return 0, fmt.Errorf("time %q out of range (00:00-23:59)", s)
	}
	return h*60 + m, nil
}

// ValidateServiceSchedule checks schedule inputs for Create/UpdateService.
// An entirely empty schedule (mode + all fields unset) is the "unknown"
// schedule and is valid. Anything partially or malformed provided is a 400:
// the API never silently coerces or drops schedule data.
func ValidateServiceSchedule(mode, openTime, closeTime string, perDay []DaySchedule) error {
	if mode == "" {
		if openTime != "" || closeTime != "" || len(perDay) != 0 {
			return fmt.Errorf("schedule_mode is required when providing schedule times")
		}
		return nil
	}
	if mode != ScheduleModeSameDaily && mode != ScheduleModePerDay {
		return fmt.Errorf("schedule_mode must be %q or %q", ScheduleModeSameDaily, ScheduleModePerDay)
	}
	// Any provided per-day table must be well-formed regardless of mode, so
	// malformed data is never stored silently under an inactive mode.
	if len(perDay) != 0 {
		if err := validatePerDay(perDay); err != nil {
			return err
		}
	}
	switch mode {
	case ScheduleModeSameDaily:
		if openTime == "" || closeTime == "" {
			return fmt.Errorf("open_time and close_time are required when schedule_mode is %q", ScheduleModeSameDaily)
		}
		openMin, err := parseHHMM(openTime)
		if err != nil {
			return fmt.Errorf("invalid open_time: %w", err)
		}
		closeMin, err := parseHHMM(closeTime)
		if err != nil {
			return fmt.Errorf("invalid close_time: %w", err)
		}
		if openMin == closeMin {
			return fmt.Errorf("open_time and close_time must differ")
		}
	case ScheduleModePerDay:
		if len(perDay) == 0 {
			return fmt.Errorf("per_day_schedule with 7 entries (mon..sun) is required when schedule_mode is %q", ScheduleModePerDay)
		}
		// Well-formedness already checked above; presence checked here.
	}
	return nil
}

// validatePerDay requires exactly the 7 canonical weekdays (case-insensitive,
// any order), each with valid differing open/close times unless is_off.
func validatePerDay(perDay []DaySchedule) error {
	if len(perDay) != 7 {
		return fmt.Errorf("per_day_schedule must contain exactly 7 entries (mon..sun), got %d", len(perDay))
	}
	seen := make(map[string]bool, 7)
	for _, d := range perDay {
		day := strings.ToLower(strings.TrimSpace(d.Day))
		valid := false
		for _, w := range scheduleWeekdays {
			if day == w {
				valid = true
				break
			}
		}
		if !valid {
			return fmt.Errorf("per_day_schedule day must be one of mon..sun, got %q", d.Day)
		}
		if seen[day] {
			return fmt.Errorf("per_day_schedule has a duplicate entry for %q", day)
		}
		seen[day] = true
		if d.IsOff {
			continue
		}
		openMin, err := parseHHMM(d.OpenTime)
		if err != nil {
			return fmt.Errorf("invalid open_time for %s: %w", day, err)
		}
		closeMin, err := parseHHMM(d.CloseTime)
		if err != nil {
			return fmt.Errorf("invalid close_time for %s: %w", day, err)
		}
		if openMin == closeMin {
			return fmt.Errorf("open_time and close_time must differ for %s", day)
		}
	}
	return nil
}

// loadScheduleLocation resolves the tenant timezone, falling back to
// DefaultServiceTimezone on empty or unloadable values (ADR-0025: never fail
// closed on timezone data). Final fallback is UTC, which cannot fail.
func loadScheduleLocation(timezone string) *time.Location {
	tz := strings.TrimSpace(timezone)
	if tz == "" {
		tz = DefaultServiceTimezone
	}
	if loc, err := time.LoadLocation(tz); err == nil {
		return loc
	}
	if loc, err := time.LoadLocation(DefaultServiceTimezone); err == nil {
		return loc
	}
	return time.UTC
}

// perDayMap indexes a validated per-day table by lowercase weekday key.
func perDayMap(perDay []DaySchedule) (map[string]DaySchedule, bool) {
	if len(perDay) != 7 {
		return nil, false
	}
	m := make(map[string]DaySchedule, 7)
	for _, d := range perDay {
		day := strings.ToLower(strings.TrimSpace(d.Day))
		if _, dup := m[day]; dup {
			return nil, false
		}
		m[day] = d
	}
	for _, w := range scheduleWeekdays {
		if _, ok := m[w]; !ok {
			return nil, false
		}
	}
	return m, true
}

// weekdayKey maps a time to its lowercase "mon".."sun" key.
func weekdayKey(t time.Time) string {
	return strings.ToLower(t.Weekday().String()[:3])
}

// EvaluateServiceSchedule reports whether a service is open at `now` and,
// when closed but a future opening is computable, when it reopens.
//
// Contract (ADR-0025): unknown schedules (mode empty) and defensively
// incomplete ones (mode set but failing validation, e.g. legacy partial
// rows) evaluate as open with a nil reopen time — evaluation never closes a
// business the owner did not completely schedule.
func EvaluateServiceSchedule(svc Service, now time.Time) (bool, *time.Time) {
	if svc.ScheduleMode == "" {
		return true, nil
	}
	loc := loadScheduleLocation(svc.Timezone)
	local := now.In(loc)
	curMin := local.Hour()*60 + local.Minute()

	switch svc.ScheduleMode {
	case ScheduleModeSameDaily:
		openMin, err1 := parseHHMM(svc.OpenTime)
		closeMin, err2 := parseHHMM(svc.CloseTime)
		if err1 != nil || err2 != nil || openMin == closeMin {
			return true, nil
		}
		if windowOpen(openMin, closeMin, curMin) {
			return true, nil
		}
		return false, reopenTodayOrTomorrow(local, openMin, curMin)
	case ScheduleModePerDay:
		table, ok := perDayMap(svc.PerDaySchedule)
		if !ok {
			return true, nil
		}
		today := table[weekdayKey(local)]
		if !today.IsOff {
			openMin, err1 := parseHHMM(today.OpenTime)
			closeMin, err2 := parseHHMM(today.CloseTime)
			if err1 == nil && err2 == nil && openMin != closeMin {
				if windowOpen(openMin, closeMin, curMin) {
					return true, nil
				}
				// Closed but opens later today.
				if !overnight(openMin, closeMin) && curMin < openMin {
					return false, timePtr(dayAt(local, openMin))
				}
				if overnight(openMin, closeMin) && curMin >= closeMin && curMin < openMin {
					return false, timePtr(dayAt(local, openMin))
				}
			}
		}
		// Today is off, done for today, or today's row is unusable: find the
		// next weekday with service. All-off yields a nil reopen time.
		for i := 1; i <= 7; i++ {
			next := local.AddDate(0, 0, i)
			entry := table[weekdayKey(next)]
			if entry.IsOff {
				continue
			}
			openMin, err := parseHHMM(entry.OpenTime)
			if err != nil {
				continue
			}
			return false, timePtr(dayAt(next, openMin))
		}
		return false, nil
	default:
		return true, nil
	}
}

// overnight reports whether a window spans midnight (open > close).
func overnight(openMin, closeMin int) bool {
	return openMin > closeMin
}

// windowOpen reports whether curMin falls inside [open, close), correctly
// spanning midnight for overnight ranges.
func windowOpen(openMin, closeMin, curMin int) bool {
	if overnight(openMin, closeMin) {
		return curMin >= openMin || curMin < closeMin
	}
	return curMin >= openMin && curMin < closeMin
}

// dayAt returns the given day at openMin in the day's own location.
func dayAt(day time.Time, openMin int) time.Time {
	return time.Date(day.Year(), day.Month(), day.Day(), openMin/60, openMin%60, 0, 0, day.Location())
}

// reopenTodayOrTomorrow returns today's opening time if it is still ahead,
// otherwise tomorrow's (used by same_daily; overnight ranges always reopen
// later today since close <= cur < open implies open is still ahead).
func reopenTodayOrTomorrow(local time.Time, openMin, curMin int) *time.Time {
	if curMin < openMin {
		return timePtr(dayAt(local, openMin))
	}
	return timePtr(dayAt(local.AddDate(0, 0, 1), openMin))
}

func timePtr(t time.Time) *time.Time {
	return &t
}
