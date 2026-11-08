//go:build windows

package main

import "golang.org/x/sys/windows"

// yieldToTally runs this process below normal CPU priority, so on a slow PC
// parsing a big Tally export never competes with TallyPrime (or with the
// person typing in it) for the processor.
func yieldToTally() error {
	return windows.SetPriorityClass(windows.CurrentProcess(), windows.BELOW_NORMAL_PRIORITY_CLASS)
}
