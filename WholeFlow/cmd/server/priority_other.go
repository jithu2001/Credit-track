//go:build !windows

package main

// yieldToTally: TallyPrime runs only on Windows; nothing to do elsewhere.
func yieldToTally() error { return nil }
