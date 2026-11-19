package main

import "testing"

func envFrom(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestExpandHome(t *testing.T) {
	if got, _ := expandHome("/abs/key", ""); got != "/abs/key" {
		t.Errorf("absolute path changed: %q", got)
	}
	if got, _ := expandHome("~/key", "/home/op"); got != "/home/op/key" {
		t.Errorf("got %q", got)
	}
	if _, err := expandHome("~/key", ""); err == nil {
		t.Error("expected an error when HOME is unset")
	}
}
