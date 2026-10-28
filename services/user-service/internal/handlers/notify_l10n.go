package handlers

import (
	"strconv"
	"strings"
)

// notifVariantParam picks a variant of a notification type's AR/EN push
// text in notification-service (internal/templates.VariantParam, PUSH-L10N).
const notifVariantParam = "variant"

// moneyParam is an amount as a notification template parameter: a plain
// decimal that notification-service formats per language (EGP / ج.م).
func moneyParam(amount float64) string {
	return strconv.FormatFloat(amount, 'f', 2, 64)
}

// formatEGP is an amount in the English notification text, formatted like
// the app (QdMoney): "EGP 1,250", "EGP 45.50". Never "$".
func formatEGP(amount float64) string {
	cents := int64(amount*100 + 0.5)
	if amount < 0 {
		cents = int64(amount*100 - 0.5)
	}
	sign := ""
	if cents < 0 {
		sign, cents = "-", -cents
	}
	digits := strconv.FormatInt(cents/100, 10)
	var b strings.Builder
	for i, d := range digits {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(d)
	}
	number := b.String()
	if frac := cents % 100; frac != 0 {
		number += "." + strconv.FormatInt(100+frac, 10)[1:]
	}
	return "EGP " + sign + number
}
