// Package templates holds the Arabic and English push texts per
// notification type (PUSH-L10N). The senders (user, auth, chat services)
// keep building their own English title and body: that text is stored,
// streamed over SSE and is what a device registered without a locale (old
// 1.x/2.0.0 apps) receives. A device that registered "ar" or "en" gets the
// text rendered here from the type and the sender's named parameters.
package templates

import (
	"strconv"
	"strings"
)

// Locales a device token may carry.
const (
	LocaleAR = "ar"
	LocaleEN = "en"
)

// VariantParam picks a variant of a type's text (key "<type>:<variant>"),
// e.g. job_accepted:negotiable. It is never shown.
const VariantParam = "variant"

// Text is one rendered title and body.
type Text struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

// template is one table row: the text per language with {name}
// placeholders, and the parameters that are money amounts (sent as a plain
// decimal, e.g. "45.5", and formatted here as EGP / ج.م).
type template struct {
	en, ar Text
	money  []string
}

// table is every notification type the services send today, keyed by type
// or "<type>:<variant>". Wording follows the app's own notification copy
// (frontend/lib/l10n app_en.arb / app_ar.arb, "ntf…" keys). Ids that the
// app reads from a body (the ticket id in "(…)") keep that shape.
var table = map[string]template{
	// user-service, customer
	"job_accepted": {
		en:    Text{"A courier accepted your order", "Final fare: {fare}."},
		ar:    Text{"مندوب قبل طلبك", "الأجرة النهائية: {fare}."},
		money: []string{"fare"},
	},
	"job_accepted:negotiable": {
		en:    Text{"A courier accepted your order", "Suggested fare: {fare}. You can answer the offer now."},
		ar:    Text{"مندوب قبل طلبك", "الأجرة المقترحة: {fare}. تقدر ترد على العرض دلوقتي."},
		money: []string{"fare"},
	},
	"job_unavailable": {
		en: Text{"No courier is free right now", "All couriers near you are busy. You can order again anytime."},
		ar: Text{"مفيش مندوب فاضي دلوقتي", "كل المناديب اللي جنبك مشغولين. تقدر تطلب تاني في أي وقت."},
	},
	"job_picked_up": {
		en: Text{"Your order was picked up", "The courier has it and is on the way to the drop-off."},
		ar: Text{"طلبك اتستلم", "المندوب استلمه وفي الطريق لمكان التسليم."},
	},
	"job_delivered": {
		en: Text{"Your order was delivered", "The courier delivered your order."},
		ar: Text{"طلبك وصل", "المندوب سلّم طلبك."},
	},
	"job_cancelled": {
		en: Text{"Your order was cancelled", "Open My orders for the details."},
		ar: Text{"طلبك اتلغى", "افتح طلباتي عشان تشوف التفاصيل."},
	},
	"job_cancelled:escrow_failed": {
		en: Text{"Your order was cancelled", "The service owner couldn't hold the payment for it."},
		ar: Text{"طلبك اتلغى", "صاحب الخدمة ماقدرش يحجز المبلغ بتاعه."},
	},
	"dispute_resolved:customer_release": {
		en: Text{"The review of your order is done", "The amount was released to the service provider."},
		ar: Text{"مراجعة طلبك خلصت", "المبلغ اتحوّل لمقدم الخدمة."},
	},
	"dispute_resolved:customer_refund": {
		en: Text{"The review of your order is done", "The amount was refunded to your wallet."},
		ar: Text{"مراجعة طلبك خلصت", "المبلغ رجع لمحفظتك."},
	},
	"dispute_resolved:provider_release": {
		en: Text{"The review of your order is done", "The amount was released to your wallet."},
		ar: Text{"مراجعة طلبك خلصت", "المبلغ اتحوّل لمحفظتك."},
	},
	"dispute_resolved:provider_refund": {
		en: Text{"The review of your order is done", "The amount was refunded to the customer."},
		ar: Text{"مراجعة طلبك خلصت", "المبلغ رجع للعميل."},
	},

	// user-service, owner
	"job_booked": {
		en: Text{"New booking", "A customer booked one of your services. Open Orders for the details."},
		ar: Text{"حجز جديد", "عميل حجز خدمة من خدماتك. افتح الطلبات عشان تشوف التفاصيل."},
	},
	"cancellation_requested": {
		en: Text{"A courier asked to cancel a job", "Reason: {reason}. Answer within 15 minutes."},
		ar: Text{"مندوب طالب يلغي مهمة", "السبب: {reason}. رد خلال 15 دقيقة."},
	},
	"cancellation_request_expired": {
		en: Text{"A cancellation request ran out", "No one answered in time: the courier was taken off the job and it went back to dispatch."},
		ar: Text{"وقت طلب الإلغاء خلص", "محدش رد في الوقت: المندوب اتشال من المهمة ورجعت للتوزيع."},
	},

	// user-service, courier
	"job_offer": {
		en: Text{"New job offer", "Answer it from the Task tab within 60 seconds."},
		ar: Text{"عرض مهمة جديد", "رد عليه من المهمة خلال 60 ثانية."},
	},
	// The English "approved" is what the app's fallback link reads.
	"cancellation_resolved:accept": {
		en: Text{"Your cancellation request was answered", "The business owner approved it. The job was cancelled."},
		ar: Text{"اترد على طلب الإلغاء بتاعك", "صاحب الشغل وافق. المهمة اتلغت."},
	},
	"cancellation_resolved:decline": {
		en: Text{"Your cancellation request was answered", "The business owner declined it. You're still on the job."},
		ar: Text{"اترد على طلب الإلغاء بتاعك", "صاحب الشغل رفض. المهمة لسه معاك."},
	},

	// notification-service, courier (POST /notifications/broadcast/job-alert)
	"job_alert": {
		en: Text{"New job", "New job for {service_name}."},
		ar: Text{"مهمة جديدة", "مهمة جديدة لخدمة {service_name}."},
	},

	// auth-service
	"kyc_approved": {
		en: Text{"Your verification was approved", "Your documents were reviewed and accepted."},
		ar: Text{"التوثيق بتاعك اتقبل", "ورقك اتراجع واتقبل."},
	},
	"kyc_rejected": {
		en: Text{"Your verification wasn't accepted", "Reason: {reason}"},
		ar: Text{"التوثيق بتاعك ما اتقبلش", "السبب: {reason}"},
	},
	"account_suspended": {
		en: Text{"Account suspended", "Your account was suspended. Reason: {reason}"},
		ar: Text{"حسابك اتوقف", "حسابك اتوقف. السبب: {reason}"},
	},
	"account_reactivated": {
		en: Text{"Account reactivated", "Your account is active again."},
		ar: Text{"حسابك رجع يشتغل", "تقدر تستخدم حسابك تاني."},
	},

	// chat-service (the app reads the ticket id from "(…)")
	"ticket_resolved": {
		en: Text{"Your complaint was resolved", "Your ticket ({ticket_id}) has been resolved: {note}"},
		ar: Text{"شكوتك اتحلت", "شكوتك ({ticket_id}) اتحلت: {note}"},
	},
	"ticket_assigned": {
		en: Text{"Support joined your complaint", "{agent_name} joined your ticket ({ticket_id})."},
		ar: Text{"الدعم دخل على شكوتك", "{agent_name} دخل على شكوتك ({ticket_id})."},
	},
	"ticket_assigned:anonymous": {
		en: Text{"Support joined your complaint", "A support agent joined your ticket ({ticket_id})."},
		ar: Text{"الدعم دخل على شكوتك", "واحد من الدعم دخل على شكوتك ({ticket_id})."},
	},
}

// Keys lists every table key (tests, docs).
func Keys() []string {
	keys := make([]string, 0, len(table))
	for k := range table {
		keys = append(keys, k)
	}
	return keys
}

// NormalizeLocale returns "ar" or "en" for raw ("ar", "ar_EG", "EN-us"…),
// else "".
func NormalizeLocale(raw string) string {
	l := strings.ToLower(strings.TrimSpace(raw))
	if i := strings.IndexAny(l, "-_"); i > 0 {
		l = l[:i]
	}
	if l == LocaleAR || l == LocaleEN {
		return l
	}
	return ""
}

// Render returns the text of notifType in locale with params. ok is false,
// and the caller keeps the sender's text, when the locale is empty or
// unknown (a legacy device), the type has no template, a placeholder has no
// parameter, or a money parameter is not a number.
func Render(notifType, locale string, params map[string]string) (Text, bool) {
	locale = NormalizeLocale(locale)
	if locale == "" {
		return Text{}, false
	}
	tpl, ok := lookup(notifType, params[VariantParam])
	if !ok {
		return Text{}, false
	}
	values := make(map[string]string, len(params))
	for k, v := range params {
		values[k] = strings.TrimSpace(v)
	}
	for _, m := range tpl.money {
		amount, err := strconv.ParseFloat(values[m], 64)
		if err != nil {
			return Text{}, false
		}
		values[m] = FormatMoney(locale, amount)
	}
	src := tpl.en
	if locale == LocaleAR {
		src = tpl.ar
	}
	title, ok1 := fill(src.Title, values)
	body, ok2 := fill(src.Body, values)
	if !ok1 || !ok2 {
		return Text{}, false
	}
	return Text{Title: title, Body: body}, true
}

// RenderAll renders notifType in every locale, or nil when it cannot be
// rendered (see Render).
func RenderAll(notifType string, params map[string]string) map[string]Text {
	out := map[string]Text{}
	for _, l := range []string{LocaleAR, LocaleEN} {
		t, ok := Render(notifType, l, params)
		if !ok {
			return nil
		}
		out[l] = t
	}
	return out
}

func lookup(notifType, variant string) (template, bool) {
	if variant != "" {
		tpl, ok := table[notifType+":"+variant]
		return tpl, ok
	}
	tpl, ok := table[notifType]
	return tpl, ok
}

// fill replaces each {name} in s; false when a name has no non-empty value.
func fill(s string, values map[string]string) (string, bool) {
	var b strings.Builder
	for {
		i := strings.IndexByte(s, '{')
		if i < 0 {
			b.WriteString(s)
			return b.String(), true
		}
		j := strings.IndexByte(s[i:], '}')
		if j < 0 {
			b.WriteString(s)
			return b.String(), true
		}
		v := values[s[i+1:i+j]]
		if v == "" {
			return "", false
		}
		b.WriteString(s[:i])
		b.WriteString(v)
		s = s[i+j+1:]
	}
}

// FormatMoney formats an EGP amount like the app (QdMoney): Western digits
// with a thousands separator, no decimals for whole amounts, two otherwise;
// "EGP 1,250" in English, "1,250 ج.م" in Arabic. Never "$".
func FormatMoney(locale string, amount float64) string {
	cents := int64(amount*100 + 0.5)
	if amount < 0 {
		cents = int64(amount*100 - 0.5)
	}
	neg := cents < 0
	if neg {
		cents = -cents
	}
	number := groupThousands(strconv.FormatInt(cents/100, 10))
	if frac := cents % 100; frac != 0 {
		number += "." + strconv.FormatInt(100+frac, 10)[1:]
	}
	if neg {
		number = "-" + number
	}
	if NormalizeLocale(locale) == LocaleAR {
		return number + " ج.م"
	}
	return "EGP " + number
}

func groupThousands(digits string) string {
	if len(digits) <= 3 {
		return digits
	}
	var b strings.Builder
	head := len(digits) % 3
	if head > 0 {
		b.WriteString(digits[:head])
	}
	for i := head; i < len(digits); i += 3 {
		if b.Len() > 0 {
			b.WriteByte(',')
		}
		b.WriteString(digits[i : i+3])
	}
	return b.String()
}
