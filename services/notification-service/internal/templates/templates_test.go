package templates

import (
	"sort"
	"strings"
	"testing"
)

type p = map[string]string

// Every template key, with the parameters its sender sends, renders in both
// languages; no key is left untested.
func TestRender_EveryTypeBothLanguages(t *testing.T) {
	cases := []struct {
		key    string
		typ    string
		params p
		en, ar Text
	}{
		{"job_accepted", "job_accepted", p{"fare": "1250"},
			Text{"A courier accepted your order", "Final fare: EGP 1,250."},
			Text{"مندوب قبل طلبك", "الأجرة النهائية: 1,250 ج.م."}},
		{"job_accepted:negotiable", "job_accepted", p{"fare": "45.5", "variant": "negotiable"},
			Text{"A courier accepted your order", "Suggested fare: EGP 45.50. You can answer the offer now."},
			Text{"مندوب قبل طلبك", "الأجرة المقترحة: 45.50 ج.م. تقدر ترد على العرض دلوقتي."}},
		{"job_unavailable", "job_unavailable", nil,
			Text{"No courier is free right now", "All couriers near you are busy. You can order again anytime."},
			Text{"مفيش مندوب فاضي دلوقتي", "كل المناديب اللي جنبك مشغولين. تقدر تطلب تاني في أي وقت."}},
		{"job_picked_up", "job_picked_up", nil,
			Text{"Your order was picked up", "The courier has it and is on the way to the drop-off."},
			Text{"طلبك اتستلم", "المندوب استلمه وفي الطريق لمكان التسليم."}},
		{"job_delivered", "job_delivered", nil,
			Text{"Your order was delivered", "The courier delivered your order."},
			Text{"طلبك وصل", "المندوب سلّم طلبك."}},
		{"job_cancelled", "job_cancelled", nil,
			Text{"Your order was cancelled", "Open My orders for the details."},
			Text{"طلبك اتلغى", "افتح طلباتي عشان تشوف التفاصيل."}},
		{"job_cancelled:escrow_failed", "job_cancelled", p{"variant": "escrow_failed"},
			Text{"Your order was cancelled", "The service owner couldn't hold the payment for it."},
			Text{"طلبك اتلغى", "صاحب الخدمة ماقدرش يحجز المبلغ بتاعه."}},
		{"dispute_resolved:customer_release", "dispute_resolved", p{"variant": "customer_release"},
			Text{"The review of your order is done", "The amount was released to the service provider."},
			Text{"مراجعة طلبك خلصت", "المبلغ اتحوّل لمقدم الخدمة."}},
		{"dispute_resolved:customer_refund", "dispute_resolved", p{"variant": "customer_refund"},
			Text{"The review of your order is done", "The amount was refunded to your wallet."},
			Text{"مراجعة طلبك خلصت", "المبلغ رجع لمحفظتك."}},
		{"dispute_resolved:provider_release", "dispute_resolved", p{"variant": "provider_release"},
			Text{"The review of your order is done", "The amount was released to your wallet."},
			Text{"مراجعة طلبك خلصت", "المبلغ اتحوّل لمحفظتك."}},
		{"dispute_resolved:provider_refund", "dispute_resolved", p{"variant": "provider_refund"},
			Text{"The review of your order is done", "The amount was refunded to the customer."},
			Text{"مراجعة طلبك خلصت", "المبلغ رجع للعميل."}},
		{"job_booked", "job_booked", nil,
			Text{"New booking", "A customer booked one of your services. Open Orders for the details."},
			Text{"حجز جديد", "عميل حجز خدمة من خدماتك. افتح الطلبات عشان تشوف التفاصيل."}},
		{"cancellation_requested", "cancellation_requested", p{"reason": "flat tyre"},
			Text{"A courier asked to cancel a job", "Reason: flat tyre. Answer within 15 minutes."},
			Text{"مندوب طالب يلغي مهمة", "السبب: flat tyre. رد خلال 15 دقيقة."}},
		{"cancellation_request_expired", "cancellation_request_expired", nil,
			Text{"A cancellation request ran out", "No one answered in time: the courier was taken off the job and it went back to dispatch."},
			Text{"وقت طلب الإلغاء خلص", "محدش رد في الوقت: المندوب اتشال من المهمة ورجعت للتوزيع."}},
		{"job_offer", "job_offer", nil,
			Text{"New job offer", "Answer it from the Task tab within 60 seconds."},
			Text{"عرض مهمة جديد", "رد عليه من المهمة خلال 60 ثانية."}},
		{"cancellation_resolved:accept", "cancellation_resolved", p{"variant": "accept"},
			Text{"Your cancellation request was answered", "The business owner approved it. The job was cancelled."},
			Text{"اترد على طلب الإلغاء بتاعك", "صاحب الشغل وافق. المهمة اتلغت."}},
		{"cancellation_resolved:decline", "cancellation_resolved", p{"variant": "decline"},
			Text{"Your cancellation request was answered", "The business owner declined it. You're still on the job."},
			Text{"اترد على طلب الإلغاء بتاعك", "صاحب الشغل رفض. المهمة لسه معاك."}},
		{"job_alert", "job_alert", p{"service_name": "Fast Bikes"},
			Text{"New job", "New job for Fast Bikes."},
			Text{"مهمة جديدة", "مهمة جديدة لخدمة Fast Bikes."}},
		{"kyc_approved", "kyc_approved", nil,
			Text{"Your verification was approved", "Your documents were reviewed and accepted."},
			Text{"التوثيق بتاعك اتقبل", "ورقك اتراجع واتقبل."}},
		{"kyc_rejected", "kyc_rejected", p{"reason": "blurry photo"},
			Text{"Your verification wasn't accepted", "Reason: blurry photo"},
			Text{"التوثيق بتاعك ما اتقبلش", "السبب: blurry photo"}},
		{"account_suspended", "account_suspended", p{"reason": "fraud review"},
			Text{"Account suspended", "Your account was suspended. Reason: fraud review"},
			Text{"حسابك اتوقف", "حسابك اتوقف. السبب: fraud review"}},
		{"account_reactivated", "account_reactivated", nil,
			Text{"Account reactivated", "Your account is active again."},
			Text{"حسابك رجع يشتغل", "تقدر تستخدم حسابك تاني."}},
		{"ticket_resolved", "ticket_resolved", p{"ticket_id": "tkt-1", "note": "refunded"},
			Text{"Your complaint was resolved", "Your ticket (tkt-1) has been resolved: refunded"},
			Text{"شكوتك اتحلت", "شكوتك (tkt-1) اتحلت: refunded"}},
		{"ticket_assigned", "ticket_assigned", p{"ticket_id": "tkt-1", "agent_name": "Mona"},
			Text{"Support joined your complaint", "Mona joined your ticket (tkt-1)."},
			Text{"الدعم دخل على شكوتك", "Mona دخل على شكوتك (tkt-1)."}},
		{"ticket_assigned:anonymous", "ticket_assigned", p{"ticket_id": "tkt-1", "variant": "anonymous"},
			Text{"Support joined your complaint", "A support agent joined your ticket (tkt-1)."},
			Text{"الدعم دخل على شكوتك", "واحد من الدعم دخل على شكوتك (tkt-1)."}},
	}

	tested := map[string]bool{}
	for _, c := range cases {
		tested[c.key] = true
		for locale, want := range map[string]Text{"en": c.en, "ar": c.ar, "ar_EG": c.ar, "EN": c.en} {
			got, ok := Render(c.typ, locale, c.params)
			if !ok {
				t.Errorf("%s/%s: not rendered", c.key, locale)
				continue
			}
			if got != want {
				t.Errorf("%s/%s:\n got  %q\n want %q", c.key, locale, got, want)
			}
		}
	}
	keys := Keys()
	sort.Strings(keys)
	for _, k := range keys {
		if !tested[k] {
			t.Errorf("template %q has no test case", k)
		}
	}
}

// Legacy devices (no locale) and anything the table cannot render keep the
// sender's text.
func TestRender_FallsBackToSenderText(t *testing.T) {
	cases := []struct {
		name, typ, locale string
		params            p
	}{
		{"no locale (old app)", "job_accepted", "", p{"fare": "10"}},
		{"unknown locale", "job_accepted", "fr", p{"fare": "10"}},
		{"unknown type", "popup", "ar", nil},
		{"unknown variant", "job_cancelled", "ar", p{"variant": "nope"}},
		{"missing parameter", "kyc_rejected", "ar", nil},
		{"blank parameter", "cancellation_requested", "en", p{"reason": "  "}},
		{"money not a number", "job_accepted", "en", p{"fare": "$10"}},
		{"money missing", "job_accepted", "ar", nil},
	}
	for _, c := range cases {
		if got, ok := Render(c.typ, c.locale, c.params); ok {
			t.Errorf("%s: rendered %q, want the sender's text", c.name, got)
		}
	}
	if RenderAll("popup", nil) != nil {
		t.Errorf("RenderAll of an unknown type must be nil")
	}
	all := RenderAll("job_accepted", p{"fare": "7"})
	if all["ar"].Body != "الأجرة النهائية: 7 ج.م." || all["en"].Body != "Final fare: EGP 7." {
		t.Errorf("RenderAll: got %v", all)
	}
}

// A parameter value is inserted as text, never re-read as a placeholder.
func TestRender_ParameterIsNotReparsed(t *testing.T) {
	got, ok := Render("kyc_rejected", "en", p{"reason": "{reason} {fare}"})
	if !ok || got.Body != "Reason: {reason} {fare}" {
		t.Errorf("got %q, %v", got, ok)
	}
}

func TestFormatMoney(t *testing.T) {
	cases := []struct {
		amount float64
		en, ar string
	}{
		{0, "EGP 0", "0 ج.م"},
		{45, "EGP 45", "45 ج.م"},
		{45.5, "EGP 45.50", "45.50 ج.م"},
		{25.004, "EGP 25", "25 ج.م"},
		{999.999, "EGP 1,000", "1,000 ج.م"},
		{1250.75, "EGP 1,250.75", "1,250.75 ج.م"},
		{1234567.8, "EGP 1,234,567.80", "1,234,567.80 ج.م"},
		{-12.5, "EGP -12.50", "-12.50 ج.م"},
	}
	for _, c := range cases {
		if got := FormatMoney("en", c.amount); got != c.en {
			t.Errorf("FormatMoney(en, %v) = %q, want %q", c.amount, got, c.en)
		}
		if got := FormatMoney("ar", c.amount); got != c.ar {
			t.Errorf("FormatMoney(ar, %v) = %q, want %q", c.amount, got, c.ar)
		}
	}
}

// No template quotes dollars.
func TestTemplates_NoDollarSign(t *testing.T) {
	for k, tpl := range table {
		for _, s := range []string{tpl.en.Title, tpl.en.Body, tpl.ar.Title, tpl.ar.Body} {
			if strings.Contains(s, "$") {
				t.Errorf("template %q contains $: %q", k, s)
			}
		}
	}
}
