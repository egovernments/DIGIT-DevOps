package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"strings"
)

func main() {
	// Read the Terraform output from stdin
	input, err := ioutil.ReadAll(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
		os.Exit(1)
	}
	// Unmarshal the JSON output into a Go struct
	type TfOutput struct {
		DBHost struct {
			Value string `json:"value"`
		} `json:"db_instance_endpoint"`
		DBName struct {
			Value string `json:"value"`
		} `json:"db_instance_name"`
	}
	var tfOutput TfOutput
	err = json.Unmarshal(input, &tfOutput)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing JSON: %v\n", err)
		os.Exit(1)
	}
	// Read the YAML file
	yamlFile, err := ioutil.ReadFile("../../../deploy-as-code/helm/environments/egov-demo.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading YAML file: %v\n", err)
		os.Exit(1)
	}
	output := strings.ReplaceAll(string(yamlFile), "<db_host_name>", tfOutput.DBHost.Value)
	output = strings.ReplaceAll(output, "<db_name>", tfOutput.DBName.Value)

	// Write the updated YAML to stdout
	fmt.Println(output)

	err = ioutil.WriteFile("../../../deploy-as-code/helm/environments/egov-demo.yaml", []byte(output), 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error writing YAML file: %v\n", err)
		os.Exit(1)
	}

}
