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
	output = strings.ReplaceAll(output, "<kafka-v2_volume_id_1>", tfOutput.KafkaVolumeIDs.Value[0])
	output = strings.ReplaceAll(output, "<kafka-v2_volume_id_2>", tfOutput.KafkaVolumeIDs.Value[1])
	output = strings.ReplaceAll(output, "<kafka-v2_volume_id_3>", tfOutput.KafkaVolumeIDs.Value[2])
	output = strings.ReplaceAll(output, "<zookeeper-v2_volume_id_1>", tfOutput.ZookeeperVolumeIDs.Value[0])
	output = strings.ReplaceAll(output, "<zookeeper-v2_volume_id_2>", tfOutput.ZookeeperVolumeIDs.Value[1])
	output = strings.ReplaceAll(output, "<zookeeper-v2_volume_id_3>", tfOutput.ZookeeperVolumeIDs.Value[2])
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

}
