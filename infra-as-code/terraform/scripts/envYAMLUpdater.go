package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
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
		EsDataVolumeIDs struct {
			Value []string `json:"value"`
		} `json:"es_data_volume_ids"`
		EsMasterVolumeIDs struct {
			Value []string `json:"value"`
		} `json:"es_master_volume_ids"`
		KafkaVolumeIDs struct {
			Value []string `json:"value"`
		} `json:"kafka_vol_ids"`
		ZookeeperVolumeIDs struct {
			Value []string `json:"value"`
		} `json:"zookeeper_volume_ids"`
		DBHost struct {
			Value string `json:"value"`
		} `json:"db_instance_endpoint"`
		DBName struct {
			Value string `json:"value"`
		} `json:"db_instance_name"`
		Zones struct {
			Value []string `json:"value"`
		} `json:"zone"`
		KubeConfig struct {
			Value string `json:"value"`
		} `json:"kubectl_config"`
	}
	var tfOutput TfOutput
	err = json.Unmarshal(input, &tfOutput)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing JSON: %v\n", err)
		os.Exit(1)
	}
	// Read the YAML file
	yamlFile, err := ioutil.ReadFile("../../../config-as-code/environments/egov-demo.yaml")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error reading YAML file: %v\n", err)
		os.Exit(1)
	}
	// Replace the placeholders with the actual volume IDs
	output := strings.ReplaceAll(string(yamlFile), "<elasticsearch-data_volume_id_1>", tfOutput.EsDataVolumeIDs.Value[0])
	output = strings.ReplaceAll(output, "<elasticsearch-data_volume_id_2>", tfOutput.EsDataVolumeIDs.Value[1])
	output = strings.ReplaceAll(output, "<elasticsearch-data_volume_id_3>", tfOutput.EsDataVolumeIDs.Value[2])
	output = strings.ReplaceAll(output, "<elasticsearch-master_volume_id_1>", tfOutput.EsMasterVolumeIDs.Value[0])
	output = strings.ReplaceAll(output, "<elasticsearch-master_volume_id_2>", tfOutput.EsMasterVolumeIDs.Value[1])
	output = strings.ReplaceAll(output, "<elasticsearch-master_volume_id_3>", tfOutput.EsMasterVolumeIDs.Value[2])
	output = strings.ReplaceAll(output, "<db_host_name>", tfOutput.DBHost.Value)
	output = strings.ReplaceAll(output, "<db_name>", tfOutput.DBName.Value)
	output = strings.ReplaceAll(output, "<zone>", tfOutput.Zones.Value[0])

	// Write the updated YAML to stdout
	fmt.Println(output)

	err = ioutil.WriteFile("../../../config-as-code/environments/egov-demo.yaml", []byte(output), 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error writing YAML file: %v\n", err)
		os.Exit(1)
	}

	kubeConfigString := tfOutput.KubeConfig.Value

	// Unescape the input string
	kubeConfigString = strings.ReplaceAll(kubeConfigString, "\\n", "\n")
	kubeConfigString = strings.ReplaceAll(kubeConfigString, "\\\"", "\"")

	// Split the string by newlines
	lines := strings.Split(kubeConfigString, "\n")

	// Remove leading and trailing whitespaces from each line
	for i, line := range lines {
		lines[i] = line
	}

	// Set initial indentation level to 0
	indentationLevel := 0

	// Build the properly indented YAML string
	var builder strings.Builder
	for _, line := range lines {

		// Adjust the indentation level based on the line's content
		if strings.Contains(line, "contexts:") || strings.Contains(line, "users:") {
			indentationLevel = 0
		} else if strings.Contains(line, "- name:") && indentationLevel > 0 {
			indentationLevel--
		}

		// Apply indentation to the line
		indentedLine := strings.Repeat("  ", indentationLevel) + line

		// Append the indented line to the builder
		builder.WriteString(indentedLine)
		builder.WriteString("\n")
	}

	yamlString := builder.String()
	fmt.Println(yamlString)

	// Write the YAML to a new file
	relativePath := "../../../deploy-as-code/deployer/kubeConfig"
	file, err := os.Create(relativePath)
	if err != nil {
		fmt.Println("Error creating file:", err)
		return
	}
	defer file.Close()

	_, err = file.WriteString(yamlString)
	if err != nil {
		fmt.Println("Error writing to file:", err)
		return
	}

	fmt.Println("YAML successfully written to file kubeConfig")

	absolutePath, err := filepath.Abs(relativePath)
	if err != nil {
		fmt.Println("Error:", err)
		return
	}

	fmt.Println("Please run the following command to set the kubeConfig:")
	fmt.Printf("\texport KUBECONFIG=\"%s\"\n", strings.TrimSpace(absolutePath))

}
