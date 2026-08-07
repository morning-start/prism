package prism

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFileToDataURI(t *testing.T) {
	dir := t.TempDir()
	pdf := filepath.Join(dir, "report.pdf")
	if err := os.WriteFile(pdf, []byte("%PDF-1.4 test"), 0o644); err != nil {
		t.Fatal(err)
	}
	uri, err := FileToDataURI("file://" + filepath.ToSlash(pdf))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(uri, "data:application/pdf;base64,") {
		t.Errorf("expected pdf data uri, got %s", uri)
	}
	payload := strings.TrimPrefix(uri, "data:application/pdf;base64,")
	if payload == "" {
		t.Error("empty base64 payload")
	}
}

func TestFileToDataURI_Errors(t *testing.T) {
	if _, err := FileToDataURI("https://x.com/a.pdf"); err == nil {
		t.Error("expected error for non-file scheme")
	}
	if _, err := FileToDataURI("file:///no/such/file.pdf"); err == nil {
		t.Error("expected error for missing file")
	}
}
