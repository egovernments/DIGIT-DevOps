package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"strings"
)

func main() {
	// Read the YAML file
	yamlFile, err := ioutil.ReadFile("../sample-aws/input.yaml")
	if err != nil {
		log.Fatalf("Failed to read YAML file: %v", err)
	}

	// Parse the YAML content
	data, err := parseYAML(yamlFile)
	if err != nil {
		log.Fatalf("Failed to parse YAML: %v", err)
	}

	// Read the variables.tf file
	replaceInFile("../sample-aws/variables.tf", data)
	fmt.Println("variables.tf file updated successfully!")

	replaceInFile("../../../config-as-code/environments/egov-demo.yaml", data)
	fmt.Println("env yaml file updated successfully!")
}

func replaceInFile(filepath string, data map[string]interface{}) {

	// Read the file
	tfFile, err := ioutil.ReadFile(filepath)
	if err != nil {
		log.Fatalf("Failed to read file: %v", err)
	}

	// Replace the values in the  file
	newContent := replaceVariableValues(tfFile, data)

	// Write the modified content to the  file
	err = ioutil.WriteFile(filepath, newContent, 0644)
	if err != nil {
		log.Fatalf("Failed to write file: %v", err)
	}

	fmt.Println("file updated successfully!")

}

// Function to parse the YAML content
func parseYAML(content []byte) (map[string]interface{}, error) {
	data := make(map[string]interface{})
	lines := strings.Split(string(content), "\n")

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

		data[key] = value
	}

	return data, nil
}

// Function to replace the values in the variables.tf file
func replaceVariableValues(content []byte, data map[string]interface{}) []byte {
	for key, value := range data {
		placeholder := fmt.Sprintf("<%v>", key)
		replacement := fmt.Sprintf("%v", value)
		content = bytesReplace(content, []byte(placeholder), []byte(replacement))
	}
	return content
}

// Helper function to replace occurrences in byte slices
func bytesReplace(content []byte, old, new []byte) []byte {
	return []byte(strings.Replace(string(content), string(old), string(new), -1))
}
