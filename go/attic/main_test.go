// =============================================================================
// main_test.go - Tests for CLI Entry Point (main.go)
// =============================================================================
//
// GO CONCEPT: Testing in Go
// -------------------------
// Go has built-in testing support — no external framework needed.
//
// Rules:
//   - Test files end in _test.go (e.g., main_test.go)
//   - Test functions start with "Test" and take *testing.T
//   - Run tests with: go test ./...
//   - Run specific tests: go test -run TestFullTitle
//   - Run with verbose output: go test -v ./...
//
// Unlike Swift's XCTest, Go has no setUp/tearDown methods. Instead:
//   - Use t.Cleanup() for teardown
//   - Use TestMain(m *testing.M) for global setup/teardown
//   - Each test function is independent
//
// Assertion style: Go does not have assert/expect functions built in.
// Instead you use if statements and call t.Error() or t.Fatal():
//   - t.Error(msg)   — log error but continue the test
//   - t.Errorf(...)  — log formatted error, continue
//   - t.Fatal(msg)   — log error and STOP this test immediately
//   - t.Fatalf(...)  — log formatted error, stop immediately
//
// Compare to Swift:
//   XCTAssertEqual(fullTitle(), "Attic v0.2.0 (Go)")
// becomes:
//   if got := fullTitle(); got != "Attic v0.2.0 (Go)" { t.Errorf(...) }
//
// Compare with Python: Python's pytest is the standard: test files are
// `test_*.py`, functions start with `test_`. Assertions use plain
// `assert`: `assert full_title() == "Attic v0.2.0 (Go)"`. For setup
// and teardown, pytest uses fixtures (`@pytest.fixture`). Python's
// `unittest` module is closer to XCTest with setUp/tearDown methods.
//
// =============================================================================

package main

import (
	"os"
	"strings"
	"testing"
)

// =============================================================================
// Version and Banner Tests
// =============================================================================

// TestFullTitle verifies the version string format.
func TestFullTitle(t *testing.T) {
	got := fullTitle()
	expected := "Attic v0.2.0 (Go)"
	if got != expected {
		t.Errorf("fullTitle() = %q, want %q", got, expected)
	}
}

// TestFullTitleContainsVersion ensures the version constant appears in the title.
func TestFullTitleContainsVersion(t *testing.T) {
	got := fullTitle()
	if !strings.Contains(got, version) {
		t.Errorf("fullTitle() = %q, does not contain version %q", got, version)
	}
	if !strings.Contains(got, "(Go)") {
		t.Errorf("fullTitle() = %q, does not contain '(Go)' suffix", got)
	}
}

// TestWelcomeBanner verifies the banner includes key elements.
func TestWelcomeBanner(t *testing.T) {
	banner := welcomeBanner()

	// GO CONCEPT: Table-Driven Tests
	// --------------------------------
	// The most common Go test pattern: define a slice of test cases
	// (a "table"), then loop over them. Each test case is a struct with
	// input and expected output.
	//
	// Benefits:
	//   - Easy to add new cases (just add a struct literal)
	//   - All cases share the same assertion logic
	//   - Clear, readable test output with t.Run()
	//
	// Compare to Swift XCTest: you'd typically write separate test methods
	// or use parameterized tests. Go's table-driven approach is more
	// concise for many cases testing the same thing.
	//
	// Compare with Python: pytest uses `@pytest.mark.parametrize`:
	//   `@pytest.mark.parametrize("name,val", [("app", APP_NAME), ...])`
	//   `def test_banner(name, val): assert val in banner`
	// This is even more concise than Go's table-driven approach.
	checks := []struct {
		name     string
		contains string
	}{
		{"app name", appName},
		{"version", version},
		{"copyright", copyright},
		{"help hint", ".help"},
		{"quit hint", ".quit"},
		{"Atari reference", "Atari 800 XL"},
	}

	for _, tc := range checks {
		// GO CONCEPT: Subtests with t.Run()
		// ----------------------------------
		// t.Run(name, func) creates a named subtest. Benefits:
		//   - Each subtest is reported separately (TestWelcomeBanner/app_name)
		//   - You can run a single subtest: go test -run TestWelcomeBanner/version
		//   - Subtests can run in parallel with t.Parallel()
		//   - If one subtest fails, others still run
		//
		// Compare with Python: pytest parametrize generates separate test items
		// automatically. With unittest, use `self.subTest(name=name):` for
		// named subtests. Both give individual test reporting like Go's t.Run().
		t.Run(tc.name, func(t *testing.T) {
			if !strings.Contains(banner, tc.contains) {
				t.Errorf("welcomeBanner() missing %q:\n%s", tc.contains, banner)
			}
		})
	}
}

// TestWelcomeBannerEndsWithNewline ensures the banner ends with a newline
// for proper terminal formatting.
func TestWelcomeBannerEndsWithNewline(t *testing.T) {
	banner := welcomeBanner()
	if !strings.HasSuffix(banner, "\n") {
		t.Error("welcomeBanner() should end with a newline")
	}
}

// =============================================================================
// Argument Parsing Tests
// =============================================================================

// GO CONCEPT: Manipulating os.Args in Tests
// -------------------------------------------
// os.Args is a package-level variable that we can temporarily replace
// in tests. The pattern is:
//   1. Save the original: oldArgs := os.Args
//   2. Set test values: os.Args = []string{"prog", "--flag"}
//   3. Restore in cleanup: defer func() { os.Args = oldArgs }()
//
// This is a common Go testing pattern for functions that read global state.
// It's not thread-safe (tests using os.Args can't run in parallel), but
// it's acceptable for unit tests.
//
// Compare with Python: pytest provides `monkeypatch.setattr("sys", "argv",
// [...])` for safe patching. `unittest.mock.patch` works too:
// `@patch("sys.argv", ["prog", "--flag"])`. Both automatically restore
// the original value — no manual cleanup needed.

// TestParseArgumentsDefaults verifies default argument values.
func TestParseArgumentsDefaults(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go"}
	args := parseArguments()

	if args.silent {
		t.Error("silent should default to false")
	}
	if args.socketPath != "" {
		t.Errorf("socketPath should default to empty, got %q", args.socketPath)
	}
	if !args.atascii {
		t.Error("atascii should default to true")
	}
	if args.showHelp {
		t.Error("showHelp should default to false")
	}
	if args.showVersion {
		t.Error("showVersion should default to false")
	}
}

// TestParseArgumentsSilent tests the --silent flag.
func TestParseArgumentsSilent(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--silent"}
	args := parseArguments()

	if !args.silent {
		t.Error("--silent flag not recognized")
	}
}

// TestParseArgumentsPlain tests the --plain flag.
func TestParseArgumentsPlain(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--plain"}
	args := parseArguments()

	if args.atascii {
		t.Error("--plain should set atascii to false")
	}
}

// TestParseArgumentsAtascii tests the --atascii flag.
func TestParseArgumentsAtascii(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--atascii"}
	args := parseArguments()

	if !args.atascii {
		t.Error("--atascii should set atascii to true")
	}
}

// TestParseArgumentsSocket tests the --socket flag with a path.
func TestParseArgumentsSocket(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--socket", "/tmp/test.sock"}
	args := parseArguments()

	if args.socketPath != "/tmp/test.sock" {
		t.Errorf("socketPath = %q, want %q", args.socketPath, "/tmp/test.sock")
	}
}

// TestParseArgumentsHelp tests help flags.
func TestParseArgumentsHelp(t *testing.T) {
	tests := []struct {
		name string
		flag string
	}{
		{"long form", "--help"},
		{"short form", "-h"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			oldArgs := os.Args
			defer func() { os.Args = oldArgs }()

			os.Args = []string{"attic-go", tc.flag}
			args := parseArguments()

			if !args.showHelp {
				t.Errorf("%s flag not recognized", tc.flag)
			}
		})
	}
}

// TestParseArgumentsVersion tests version flags.
func TestParseArgumentsVersion(t *testing.T) {
	tests := []struct {
		name string
		flag string
	}{
		{"long form", "--version"},
		{"short form", "-v"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			oldArgs := os.Args
			defer func() { os.Args = oldArgs }()

			os.Args = []string{"attic-go", tc.flag}
			args := parseArguments()

			if !args.showVersion {
				t.Errorf("%s flag not recognized", tc.flag)
			}
		})
	}
}

// TestParseArgumentsCombined tests multiple flags together.
func TestParseArgumentsCombined(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--silent", "--plain", "--socket", "/tmp/my.sock"}
	args := parseArguments()

	if !args.silent {
		t.Error("--silent not recognized in combined args")
	}
	if args.atascii {
		t.Error("--plain not recognized in combined args")
	}
	if args.socketPath != "/tmp/my.sock" {
		t.Errorf("socketPath = %q, want %q", args.socketPath, "/tmp/my.sock")
	}
}

// TestParseArgumentsPlainThenAtascii tests that later flags override earlier ones.
func TestParseArgumentsPlainThenAtascii(t *testing.T) {
	oldArgs := os.Args
	defer func() { os.Args = oldArgs }()

	os.Args = []string{"attic-go", "--plain", "--atascii"}
	args := parseArguments()

	if !args.atascii {
		t.Error("--atascii should override earlier --plain")
	}
}

// =============================================================================
// Constants Tests
// =============================================================================

// TestVersionFormat checks that the version follows semantic versioning.
func TestVersionFormat(t *testing.T) {
	// Simple check: version should contain two dots (MAJOR.MINOR.PATCH)
	parts := strings.Split(version, ".")
	if len(parts) != 3 {
		t.Errorf("version %q is not in MAJOR.MINOR.PATCH format", version)
	}
}

// TestAppNameNotEmpty ensures the app name constant is set.
func TestAppNameNotEmpty(t *testing.T) {
	if appName == "" {
		t.Error("appName should not be empty")
	}
}

// TestCopyrightNotEmpty ensures the copyright constant is set.
func TestCopyrightNotEmpty(t *testing.T) {
	if copyright == "" {
		t.Error("copyright should not be empty")
	}
}
