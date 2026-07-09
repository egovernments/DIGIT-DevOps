package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

func main() {
	// The cloud provider is derived from the directory the command is run in.
	// Intended usage (run from within a provider directory):
	//     cd aws   && go run ../scripts/init.go
	//     cd azure && go run ../scripts/init.go
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatalf("Failed to determine current directory: %v", err)
	}
	provider := filepath.Base(cwd)

	// Read the input.yaml located in the current directory
	yamlFile, err := ioutil.ReadFile("input.yaml")
	if err != nil {
		log.Fatalf("Failed to read input.yaml in %s: %v", cwd, err)
	}

	// Parse the YAML content
	data, err := parseYAML(string(yamlFile))
	if err != nil {
		log.Fatalf("Failed to parse YAML: %v", err)
	}

	switch provider {
	case "aws":
		// AWS: inputs are validated here in Go before substitution.
		validateInputs(data)

		replaceInFile("variables.tf", data, false, true)
		fmt.Println("variables.tf file updated successfully!")

		replaceInFile("remote-state/variables.tf", data, false, true)
		fmt.Println("remote-state/variables.tf file updated successfully!")

		replaceInFile("main.tf", data, false, true)
		fmt.Println("main.tf file updated successfully!")

		replaceInFile("../../../deploy-as-code/helm/environments/egov-demo.yaml", data, true, true)
		fmt.Println("env yaml file updated successfully!")

		replaceInFile("../../../deploy-as-code/helm/environments/egov-demo-secrets.yaml", data, true, true)
		fmt.Println("env secrets yaml file updated successfully!")

	case "azure":
		// Azure: validation is handled by the native `validation {}` blocks in
		// variables.tf, so we skip the Go-side validation and only substitute
		// the <placeholder> markers with the values from input.yaml.
		replaceInFile("variables.tf", data, true, false)
		fmt.Println("variables.tf file updated successfully!")

		replaceInFile("remote-state/variables.tf", data, true, false)
		fmt.Println("remote-state/variables.tf file updated successfully!")

		// In main.tf the placeholders are already wrapped in quotes (e.g.
		// "<subscription_id>", "<cluster_name>-rg"), so strip the quotes from
		// the substituted value to avoid doubling them.
		replaceInFile("main.tf", data, true, false)
		fmt.Println("main.tf file updated successfully!")

	case "gcp":
		// GCP: no Go-side validation. All placeholders in the GCP .tf files are
		// wrapped in quotes (e.g. default = "<GCP_PROJECT_ID>"), so strip the
		// quotes from the substituted value to avoid doubling them.
		replaceInFile("variables.tf", data, false, false)
		fmt.Println("variables.tf file updated successfully!")

		replaceInFile("remote-state/variables.tf", data, false, false)
		fmt.Println("remote-state/variables.tf file updated successfully!")

		replaceInFile("main.tf", data, false, false)
		fmt.Println("main.tf file updated successfully!")

	default:
		log.Fatalf("Unsupported provider directory %q. Run this command from within the aws, azure or gcp directory (e.g. `cd gcp && go run ../scripts/init.go`).", provider)
	}
}

func validateInputs(data map[string]interface{}) {

	for key, value := range data {
		placeholder := fmt.Sprintf("<%s>", key) // Include angle brackets in the placeholder
		replacement := fmt.Sprintf("%v", value)

		if placeholder == "<db_name>" || placeholder == "<db_username>" {
			isValidDBName(replacement)
		}

		if placeholder == "<cluster_name>" {
			isValidClusterName(replacement)
		}

	}

}

func replaceInFile(filepath string, data map[string]interface{}, stripQuotes bool, validate bool) {
	// Read the file
	content, err := ioutil.ReadFile(filepath)
	if err != nil {
		log.Fatalf("Failed to read file %s: %v", filepath, err)
	}

	// Replace the values in the file
	newContent := replaceVariableValues(string(content), data, stripQuotes, validate)

	// Write the modified content to the file
	err = ioutil.WriteFile(filepath, []byte(newContent), 0644)
	if err != nil {
		log.Fatalf("Failed to write file %s: %v", filepath, err)
	}

}

// Function to parse the YAML content
func parseYAML(content string) (map[string]interface{}, error) {
	data := make(map[string]interface{})
	lines := strings.Split(content, "\n")

	for _, line := range lines {
		line = strings.TrimSpace(line)

		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("Invalid YAML format")
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Check if the value is enclosed in double quotes
		if !strings.HasPrefix(value, "\"") || !strings.HasSuffix(value, "\"") {
			return nil, fmt.Errorf("Values in YAML must be enclosed in double quotes")
		}

		data[key] = value
	}

	return data, nil
}

// Function to replace the values in the variables.tf file
func replaceVariableValues(content string, data map[string]interface{}, stripQuotes bool, validate bool) string {
	for key, value := range data {
		placeholder := fmt.Sprintf("<%s>", key) // Include angle brackets in the placeholder
		replacement := fmt.Sprintf("%v", value)

		if validate && (placeholder == "<db_name>" || placeholder == "<db_username>") {
			isValidDBName(replacement)
		}

		replacement = strings.TrimSpace(replacement)
		if stripQuotes {
			replacement = replacement[1 : len(replacement)-1]
		}
		content = strings.ReplaceAll(content, placeholder, replacement)
	}
	return content
}

func isValidDBName(dbName string) error {

	dbName = strings.TrimSpace(dbName)
	dbName = dbName[1 : len(dbName)-1]

	//fmt.Println("Validating DB name")
	// Check if the DB name starts with a letter
	matched, _ := regexp.MatchString("^[a-zA-Z]", dbName)
	if !matched {
		log.Fatalf("DB name must start with a letter")
	}

	// Check if the DB name contains only alphanumeric characters
	matched, _ = regexp.MatchString("^[a-zA-Z0-9]+$", dbName)
	if !matched {
		log.Fatalf("DB name and DB user name must contain only alphanumeric characters")
	}

	return nil
}

func isValidClusterName(input string) error {
	// Regular expression pattern for lowercase alphanumeric characters and hyphens
	pattern := "^[a-z0-9-]+$"
	input = input[1 : len(input)-1]
	matched, _ := regexp.MatchString(pattern, input)
	if !matched {
		log.Fatalf(" Cluster name can have only lowercase alphanumeric characters and hyphens")
	}
	return nil
}
