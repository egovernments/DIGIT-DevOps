package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"regexp"
	"strings"
)

func main() {
	// Read the YAML file
	yamlFile, err := ioutil.ReadFile("../sample-aws/input.yaml")
	if err != nil {
		log.Fatalf("Failed to read YAML file: %v", err)
	}

	// Parse the YAML content
	data, err := parseYAML(string(yamlFile))
	if err != nil {
		log.Fatalf("Failed to parse YAML: %v", err)
	}

	// Read the variables.tf file
	replaceInFile("../sample-aws/variables.tf", data, false)
	fmt.Println("variables.tf file updated successfully!")

	replaceInFile("../../../config-as-code/environments/egov-demo.yaml", data, true)
	fmt.Println("env yaml file updated successfully!")

	replaceInFile("../../../config-as-code/environments/egov-demo-secrets.yaml", data, true)
	fmt.Println("env secrets yaml file updated successfully!")
}

func replaceInFile(filepath string, data map[string]interface{}, stripQuotes bool) {
	// Read the file
	content, err := ioutil.ReadFile(filepath)
	if err != nil {
		log.Fatalf("Failed to read file: %v", err)
	}

	// Replace the values in the file
	newContent := replaceVariableValues(string(content), data, stripQuotes)

	// Write the modified content to the file
	err = ioutil.WriteFile(filepath, []byte(newContent), 0644)
	if err != nil {
		log.Fatalf("Failed to write file: %v", err)
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
func replaceVariableValues(content string, data map[string]interface{}, stripQuotes bool) string {
	for key, value := range data {
		placeholder := fmt.Sprintf("<%s>", key) // Include angle brackets in the placeholder
		replacement := fmt.Sprintf("%v", value)

		if placeholder == "<db_name>" || placeholder == "<db_username>" {
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

	fmt.Println("Validating DB name")
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
