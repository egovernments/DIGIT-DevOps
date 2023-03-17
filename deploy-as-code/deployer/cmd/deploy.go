/*
Copyright © 2019 NAME HERE <EMAIL ADDRESS>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
package cmd

import (
	"errors"
	"fmt"
	"deployer/pkg/cmd/deployer"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var options deployer.Options

// deployCmd represents the deploy command
var deployCmd = &cobra.Command{
	Use:   "deploy [IMAGES]",
	Short: "Deploy a comma separated list of images",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,

	PreRunE: func(cmd *cobra.Command, args []string) error {
		if len(args) < 1 {
			return errors.New("At least require one image to deploy")
		}
		options.Images = args[0]

		return nil
	},
	Run: func(cmd *cobra.Command, args []string) {

		options.ConfigDir = viper.GetString("helm-dir")
		deployer.DeployCharts(options)
		fmt.Println("options.ConfigDir: " + options.ConfigDir)

	},
}

func init() {
	// deployCmd.Flags().StringVarP(&images, "images", "i", "", "Images to be deployed")

	deployCmd.Flags().String("helm-dir", "../../config-as-code", "Helm Charts / Configs directory")
	viper.BindPFlag("helm-dir", deployCmd.Flags().Lookup("helm-dir"))

	deployCmd.Flags().StringVarP(&options.Environment, "environment", "e", "", "Environment override to be applied")
	deployCmd.Flags().BoolVarP(&options.ClusterConfigs, "cluster-configs", "c", false, "Deploy cluster configs")
	deployCmd.Flags().BoolVarP(&options.Print, "print", "p", false, "Print templates to stdout")
	// deployCmd.MarkFlagRequired("images")
	deployCmd.MarkFlagRequired("environment")
	rootCmd.AddCommand(deployCmd)

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// deployCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// deployCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
